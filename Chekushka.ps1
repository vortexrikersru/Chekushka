<#
.SYNOPSIS
    User account management tool that always queries the PDC Emulator for lockout status,
    and unlocks accounts on both the PDC Emulator and the nearest domain controller.
.DESCRIPTION
    Searches for AD users by login or surname, displays account status (locked, disabled,
    password expiry), and allows unlocking on both the PDC Emulator and the nearest DC.
.NOTES
    Requires ActiveDirectory module and appropriate permissions.
#>

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

# ============================
# XAML UI Definition
# ============================
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Chekushka - Health Bar" Height="520" Width="640"
        WindowStartupLocation="CenterScreen"
        Background="#F4F4F4"
        FontFamily="Segoe UI" FontSize="14">
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Search Box -->
        <Border Grid.Row="0" Background="White" Padding="12" CornerRadius="6" Margin="0,0,0,12">
            <StackPanel>
                <TextBlock Text="Search user (PDC Emulator)" FontWeight="Bold" Margin="0,0,0,8"/>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                    <TextBlock Text="Search by:" VerticalAlignment="Center" Margin="0,0,10,0"/>
                    <RadioButton x:Name="rbLogin" Content="Login" IsChecked="True" Margin="0,0,10,0"/>
                    <RadioButton x:Name="rbSurname" Content="Surname"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal">
                    <TextBox x:Name="tbSearch" Width="300" Height="28" Margin="0,0,10,0"/>
                    <Button x:Name="btnSearch" Content="Search" Width="100" Height="28"
                            Background="#0078D4" Foreground="White" BorderThickness="0"
                            Cursor="Hand"/>
                </StackPanel>
            </StackPanel>
        </Border>

        <!-- Result Box -->
        <Border Grid.Row="1" Background="White" Padding="12" CornerRadius="6" Margin="0,0,0,12">
            <StackPanel>
                <TextBlock Text="User information" FontWeight="Bold" Margin="0,0,0,8"/>
                <Grid Margin="0,4">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="200"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <TextBlock Grid.Row="0" Grid.Column="0" Text="User:"/>
                    <TextBlock x:Name="txtUser" Grid.Row="0" Grid.Column="1"/>

                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Disabled:"/>
                    <TextBlock x:Name="txtDisabled" Grid.Row="1" Grid.Column="1"/>

                    <TextBlock Grid.Row="2" Grid.Column="0" Text="Locked:"/>
                    <StackPanel Grid.Row="2" Grid.Column="1" Orientation="Horizontal">
                        <TextBlock x:Name="txtLocked" Margin="0,0,10,0"/>
                        <Button x:Name="btnUnlock" Content="Unlock" Width="90" Height="24"
                                Background="#D83B01" Foreground="White" BorderThickness="0"
                                Visibility="Collapsed" Cursor="Hand"/>
                    </StackPanel>

                    <TextBlock Grid.Row="3" Grid.Column="0" Text="Password expired:"/>
                    <TextBlock x:Name="txtPwdExpired" Grid.Row="3" Grid.Column="1"/>

                    <TextBlock Grid.Row="4" Grid.Column="0" Text="Account expired:"/>
                    <TextBlock x:Name="txtAccExpired" Grid.Row="4" Grid.Column="1"/>

                    <TextBlock Grid.Row="5" Grid.Column="0" Text="Must change password:"/>
                    <TextBlock x:Name="txtMustChange" Grid.Row="5" Grid.Column="1"/>

                    <TextBlock Grid.Row="6" Grid.Column="0" Text="Password expires:"/>
                    <TextBlock x:Name="txtPwdExpires" Grid.Row="6" Grid.Column="1"/>
                </Grid>
            </StackPanel>
        </Border>

        <!-- Status Bar -->
        <Border Grid.Row="3" Background="#EDEDED" Padding="8" CornerRadius="4">
            <TextBlock x:Name="txtStatus" Foreground="Black"/>
        </Border>
    </Grid>
</Window>
"@

# ============================
# Helper Functions
# ============================

function Set-StatusMessage {
    param(
        [string]$Message,
        [bool]$IsError = $false
    )
    $script:txtStatus.Text = $Message
    $script:txtStatus.Foreground = if ($IsError) { 'DarkRed' } else { 'DarkGreen' }
}

function Clear-ResultFields {
    $fields = @($txtUser, $txtDisabled, $txtLocked, $txtPwdExpired,
                $txtAccExpired, $txtMustChange, $txtPwdExpires)
    foreach ($field in $fields) { $field.Text = '' }

    $highlightControls = @($txtDisabled, $txtLocked, $txtPwdExpired,
                           $txtAccExpired, $txtMustChange, $txtPwdExpires)
    foreach ($ctrl in $highlightControls) {
        $ctrl.Foreground = 'Black'
        $ctrl.FontWeight = 'Normal'
    }

    $script:btnUnlock.Visibility = 'Collapsed'
    $script:CurrentSam = $null
    Set-StatusMessage ''
}

function Set-RedBold {
    param($Control)
    $Control.Foreground = 'Red'
    $Control.FontWeight = 'Bold'
}

function Format-DateShort {
    param([datetime]$Date)
    $Date.ToString('dd/MM/yyyy')
}

# ============================
# Core Business Logic
# ============================

function Get-PDCEmulator {
    try {
        $domain = Get-ADDomain -ErrorAction Stop
        return $domain.PDCEmulator
    }
    catch {
        throw "Unable to determine PDC Emulator: $($_.Exception.Message)"
    }
}

# === CHANGED: New function to get a nearest DC (different from PDC) ===
function Get-NearestDC {
    try {
        # Get current AD site
        $currentSite = (Get-ADDomainController -Discover -ErrorAction Stop).Site
        if (-not $currentSite) {
            throw "Could not determine current AD site."
        }

        # Find all DCs in the same site, exclude PDC, pick the first one
        $otherDCs = Get-ADDomainController -Filter "Site -eq '$currentSite' -and IsReadOnly -eq `$false" -ErrorAction Stop |
                    Where-Object { $_.HostName -ne $script:PDCServer }

        if (-not $otherDCs) {
            # Fallback: just pick any writable DC other than PDC
            $otherDCs = Get-ADDomainController -Filter "IsReadOnly -eq `$false" -ErrorAction Stop |
                        Where-Object { $_.HostName -ne $script:PDCServer }
        }

        if ($otherDCs) {
            $nearestDC = $otherDCs[0].HostName
            Write-Verbose "Nearest DC (non-PDC): $nearestDC"
            return $nearestDC
        }
        else {
            Write-Warning "No other writable DC found besides PDC."
            return $null
        }
    }
    catch {
        Write-Warning "Failed to find nearest DC: $($_.Exception.Message)"
        return $null
    }
}

function Get-DefaultPasswordAge {
    param([string]$PDCServer)
    try {
        $policy = Get-ADDefaultDomainPasswordPolicy -Server $PDCServer -ErrorAction Stop
        return [int]$policy.MaxPasswordAge.TotalDays
    }
    catch {
        Write-Warning "Could not retrieve password policy from PDC. Using fallback 120 days."
        return 120
    }
}

function Get-PasswordExpiryInfo {
    param(
        [Microsoft.ActiveDirectory.Management.ADUser]$User,
        [string]$PDCServer,
        [int]$DefaultMaxAge
    )
    try {
        $fgpp = Get-ADUserResultantPasswordPolicy -Identity $User.SamAccountName -Server $PDCServer -ErrorAction Stop
        $maxAge = [int]$fgpp.MaxPasswordAge.TotalDays
    }
    catch {
        $maxAge = $DefaultMaxAge
    }

    if ($User.PasswordNeverExpires) {
        return @{ Expired = $false; ExpiryText = 'Password never expires' }
    }
    if ($User.pwdLastSet -eq 0) {
        return @{ Expired = $false; ExpiryText = 'Must change at next logon' }
    }
    if (-not $User.PasswordLastSet) {
        return @{ Expired = $false; ExpiryText = 'PasswordLastSet unknown' }
    }

    $expiry = $User.PasswordLastSet.AddDays($maxAge)
    $expired = $expiry -lt (Get-Date)

    return @{
        Expired    = $expired
        ExpiryText = if ($expired) {
            "Expired on $(Format-DateShort $expiry)"
        } else {
            "Will expire on $(Format-DateShort $expiry)"
        }
    }
}

function Find-User {
    param(
        [string]$SearchValue,
        [bool]$SearchByLogin,
        [string]$PDCServer
    )
    $properties = @('Enabled', 'LockedOut', 'AccountExpirationDate',
                    'pwdLastSet', 'PasswordLastSet', 'PasswordNeverExpires',
                    'SamAccountName', 'Name')

    if ($SearchByLogin) {
        $user = Get-ADUser -Server $PDCServer -Filter "sAMAccountName -eq '$SearchValue'" -Properties $properties -ErrorAction Stop
        if (-not $user) { throw "Login '$SearchValue' not found." }
        return $user
    }
    else {
        $users = @(Get-ADUser -Server $PDCServer -Filter "sn -like '$SearchValue*'" -Properties $properties -ErrorAction Stop)
        if ($users.Count -eq 0) { throw "Surname '$SearchValue' not found." }
        if ($users.Count -eq 1) { return $users[0] }

        # Multiple matches – let user choose
        $selection = $users |
            Select-Object Name, SamAccountName, DistinguishedName |
            Out-GridView -Title "Select user" -PassThru

        if (-not $selection) { throw "Selection cancelled." }
        return Get-ADUser -Server $PDCServer -Identity $selection.SamAccountName -Properties $properties -ErrorAction Stop
    }
}

function Update-UIWithUser {
    param([Microsoft.ActiveDirectory.Management.ADUser]$User)

    $script:CurrentSam = $User.SamAccountName
    $script:txtUser.Text = "$($User.Name) ($($User.SamAccountName))"

    # Disabled
    if (-not $User.Enabled) {
        $script:txtDisabled.Text = 'Yes'
        Set-RedBold $script:txtDisabled
    } else {
        $script:txtDisabled.Text = 'No'
    }

    # Locked
    if ($User.LockedOut) {
        $script:txtLocked.Text = 'Yes'
        Set-RedBold $script:txtLocked
        $script:btnUnlock.Visibility = 'Visible'
    } else {
        $script:txtLocked.Text = 'No'
    }

    # Account expiration
    if ($User.AccountExpirationDate) {
        if ($User.AccountExpirationDate -lt (Get-Date)) {
            $script:txtAccExpired.Text = "Yes (expired $(Format-DateShort $User.AccountExpirationDate))"
            Set-RedBold $script:txtAccExpired
        } else {
            $script:txtAccExpired.Text = "No (expires $(Format-DateShort $User.AccountExpirationDate))"
        }
    } else {
        $script:txtAccExpired.Text = 'No (no expiration)'
    }

    # Must change password
    if ($User.pwdLastSet -eq 0) {
        $script:txtMustChange.Text = 'Yes'
        Set-RedBold $script:txtMustChange
    } else {
        $script:txtMustChange.Text = 'No'
    }

    # Password expiry
    $pwdInfo = Get-PasswordExpiryInfo -User $User -PDCServer $script:PDCServer -DefaultMaxAge $script:DefaultMaxPasswordAge
    $script:txtPwdExpired.Text = if ($pwdInfo.Expired) { 'Yes' } else { 'No' }
    $script:txtPwdExpires.Text = $pwdInfo.ExpiryText
    if ($pwdInfo.Expired) {
        Set-RedBold $script:txtPwdExpired
        Set-RedBold $script:txtPwdExpires
    }
}

function Invoke-Search {
    Clear-ResultFields

    $searchValue = $script:tbSearch.Text.Trim()
    if (-not $searchValue) {
        Set-StatusMessage 'Please enter a search value.' -IsError $true
        return
    }

    try {
        $user = Find-User -SearchValue $searchValue `
                          -SearchByLogin $script:rbLogin.IsChecked `
                          -PDCServer $script:PDCServer
        Update-UIWithUser -User $user
        Set-StatusMessage "User loaded successfully from PDC Emulator ($($script:PDCServer))."
    }
    catch {
        Set-StatusMessage $_.Exception.Message -IsError $true
    }
}

# === CHANGED: Unlock on both PDC and nearest DC ===
function Invoke-Unlock {
    if (-not $script:CurrentSam) {
        Set-StatusMessage 'No user selected.' -IsError $true
        return
    }

    $pdcResult = $false
    $nearestResult = $false
    $pdcError = $null
    $nearestError = $null

    # 1. Unlock on PDC Emulator
    try {
        Unlock-ADAccount -Server $script:PDCServer -Identity $script:CurrentSam -ErrorAction Stop
        $pdcResult = $true
    }
    catch {
        $pdcError = $_.Exception.Message
    }

    # 2. Unlock on nearest DC (if available and different from PDC)
    $nearestDC = Get-NearestDC
    if ($nearestDC -and $nearestDC -ne $script:PDCServer) {
        try {
            Unlock-ADAccount -Server $nearestDC -Identity $script:CurrentSam -ErrorAction Stop
            $nearestResult = $true
        }
        catch {
            $nearestError = $_.Exception.Message
        }
    }
    else {
        if (-not $nearestDC) {
            $nearestError = "No additional DC found (skipped)."
        }
        elseif ($nearestDC -eq $script:PDCServer) {
            $nearestError = "Nearest DC was the same as PDC (skipped)."
        }
    }

    # Build status message
    $statusLines = @()
    if ($pdcResult) { $statusLines += "✓ Unlocked on PDC ($($script:PDCServer))" }
    else { $statusLines += "✗ Failed on PDC: $pdcError" }

    if ($nearestResult) { $statusLines += "✓ Unlocked on nearest DC ($nearestDC)" }
    elseif ($nearestError) { $statusLines += "⚠ Nearest DC skip/error: $nearestError" }

    $finalStatus = $statusLines -join "`n"
    $isAnyError = (-not $pdcResult) -or (-not $nearestResult -and $nearestError -and $nearestError -notlike "*skipped*")
    Set-StatusMessage $finalStatus -IsError $isAnyError

    # Always refresh user status from PDC after unlock attempt
    Invoke-Search
}

# ============================
# UI Initialization & Event Wiring
# ============================

function Initialize-UI {
    # Load XAML
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # Store controls in script scope for access from event handlers
    $script:window      = $window
    $script:rbLogin     = $window.FindName('rbLogin')
    $script:rbSurname   = $window.FindName('rbSurname')
    $script:tbSearch    = $window.FindName('tbSearch')
    $script:btnSearch   = $window.FindName('btnSearch')
    $script:btnUnlock   = $window.FindName('btnUnlock')
    $script:txtUser     = $window.FindName('txtUser')
    $script:txtDisabled = $window.FindName('txtDisabled')
    $script:txtLocked   = $window.FindName('txtLocked')
    $script:txtPwdExpired = $window.FindName('txtPwdExpired')
    $script:txtAccExpired = $window.FindName('txtAccExpired')
    $script:txtMustChange = $window.FindName('txtMustChange')
    $script:txtPwdExpires = $window.FindName('txtPwdExpires')
    $script:txtStatus   = $window.FindName('txtStatus')

    # Wire events
    $script:btnSearch.Add_Click({ Invoke-Search })
    $script:btnUnlock.Add_Click({ Invoke-Unlock })
    $script:window.Add_KeyDown({
        if ($_.Key -eq 'Enter') { Invoke-Search }
    })
}

# ============================
# Main Entry Point
# ============================

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    [System.Windows.MessageBox]::Show(
        "Active Directory module is required.`nPlease install RSAT or load the module manually.",
        "Missing Dependency", "OK", "Error"
    )
    exit 1
}

# Initialize PDC and default settings
try {
    $script:PDCServer = Get-PDCEmulator
    $script:DefaultMaxPasswordAge = Get-DefaultPasswordAge -PDCServer $script:PDCServer
}
catch {
    [System.Windows.MessageBox]::Show($_.Exception.Message, "PDC Emulator Error", "OK", "Error")
    exit 1
}

# Build and show UI
Initialize-UI
$script:window.ShowDialog() | Out-Null