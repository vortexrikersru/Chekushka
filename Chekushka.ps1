Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

# XAML UI
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Chekushka" Height="480" Width="600" WindowStartupLocation="CenterScreen">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <GroupBox Header="Search" Grid.Row="0" Margin="0,0,0,10">
            <Grid Margin="10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Label Grid.Row="0" Grid.Column="0" Content="Search by:" VerticalAlignment="Center" Margin="0,0,10,0"/>

                <StackPanel Grid.Row="0" Grid.Column="1" Orientation="Horizontal">
                    <RadioButton x:Name="rbLogin" Content="Login" IsChecked="True" Margin="0,0,10,0"/>
                    <RadioButton x:Name="rbSurname" Content="Surname"/>
                </StackPanel>

                <TextBox x:Name="tbSearch" Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,10,10,0" Height="24"/>

                <Button x:Name="btnSearch" Grid.Row="1" Grid.Column="2" Content="Search" Width="80" Height="24" Margin="0,10,0,0"/>
            </Grid>
        </GroupBox>

        <GroupBox Header="Result" Grid.Row="1" Margin="0,0,0,10">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Label Grid.Row="0" Grid.Column="0" Content="User:" Margin="0,0,10,5"/>
                <TextBlock x:Name="txtUser" Grid.Row="0" Grid.Column="1"/>

                <Label Grid.Row="1" Grid.Column="0" Content="Disabled:" Margin="0,0,10,5"/>
                <TextBlock x:Name="txtDisabled" Grid.Row="1" Grid.Column="1"/>

                <Label Grid.Row="2" Grid.Column="0" Content="Locked:" Margin="0,0,10,5"/>
                <StackPanel Grid.Row="2" Grid.Column="1" Orientation="Horizontal">
                    <TextBlock x:Name="txtLocked" Margin="0,0,10,0"/>
                    <Button x:Name="btnUnlock" Content="Unlock" Width="80" Height="22" Visibility="Collapsed"/>
                </StackPanel>

                <Label Grid.Row="3" Grid.Column="0" Content="Password expired:" Margin="0,0,10,5"/>
                <TextBlock x:Name="txtPwdExpired" Grid.Row="3" Grid.Column="1"/>

                <Label Grid.Row="4" Grid.Column="0" Content="Account expired:" Margin="0,0,10,5"/>
                <TextBlock x:Name="txtAccExpired" Grid.Row="4" Grid.Column="1"/>

                <Label Grid.Row="5" Grid.Column="0" Content="Must change password at next logon:" Margin="0,0,10,5"/>
                <TextBlock x:Name="txtMustChange" Grid.Row="5" Grid.Column="1"/>

                <Label Grid.Row="6" Grid.Column="0" Content="Password expires:" Margin="0,0,10,0"/>
                <TextBlock x:Name="txtPwdExpires" Grid.Row="6" Grid.Column="1"/>
            </Grid>
        </GroupBox>

        <TextBlock x:Name="txtStatus" Grid.Row="2" Foreground="DarkRed" TextWrapping="Wrap"/>
    </Grid>
</Window>
"@

# Load XAML
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Controls
$rbLogin     = $window.FindName("rbLogin")
$rbSurname   = $window.FindName("rbSurname")
$tbSearch    = $window.FindName("tbSearch")
$btnSearch   = $window.FindName("btnSearch")
$btnUnlock   = $window.FindName("btnUnlock")

$txtUser      = $window.FindName("txtUser")
$txtDisabled  = $window.FindName("txtDisabled")
$txtLocked    = $window.FindName("txtLocked")
$txtPwdExpired= $window.FindName("txtPwdExpired")
$txtAccExpired= $window.FindName("txtAccExpired")
$txtMustChange= $window.FindName("txtMustChange")
$txtPwdExpires= $window.FindName("txtPwdExpires")
$txtStatus    = $window.FindName("txtStatus")

# current user SamAccountName for actions
$script:CurrentSam = $null

function Clear-Result {
    $txtUser.Text       = ""
    $txtDisabled.Text   = ""
    $txtLocked.Text     = ""
    $txtPwdExpired.Text = ""
    $txtAccExpired.Text = ""
    $txtMustChange.Text = ""
    $txtPwdExpires.Text = ""
    $txtStatus.Text     = ""

    foreach ($c in @($txtDisabled,$txtLocked,$txtPwdExpired,$txtAccExpired,$txtMustChange,$txtPwdExpires)) {
        $c.Foreground = "Black"
        $c.FontWeight = "Normal"
    }

    $btnUnlock.Visibility = "Collapsed"
    $script:CurrentSam = $null
}

# --- NEW: Read Default Domain Policy MaxPasswordAge ---
function Get-DefaultDomainMaxPasswordAgeDays {
    try {
        $domain = Get-ADDomain
        $policy = Get-ADDefaultDomainPasswordPolicy -Identity $domain.DistinguishedName -ErrorAction Stop
        return [int]$policy.MaxPasswordAge.TotalDays
    }
    catch {
        return 120   # fallback
    }
}

$Global:MaxPasswordAgeDays = Get-DefaultDomainMaxPasswordAgeDays

function Format-Date {
    param([datetime]$dt)
    return $dt.ToString("dd/MM/yyyy")
}

function Mark-RedBold {
    param($control)
    $control.Foreground = "Red"
    $control.FontWeight = "Bold"
}

# --- FGPP-AWARE PASSWORD EXPIRY LOGIC ---
function Get-PasswordExpiryInfo {
    param([Microsoft.ActiveDirectory.Management.ADUser]$User)

    # Try to get FGPP
    $fgpp = $null
    try {
        $fgpp = Get-ADUserResultantPasswordPolicy -Identity $User.SamAccountName -ErrorAction Stop
    } catch {}

    # Determine max password age
    if ($fgpp -and $fgpp.MaxPasswordAge) {
        $maxAgeDays = [int]$fgpp.MaxPasswordAge.TotalDays
    } else {
        $maxAgeDays = $Global:MaxPasswordAgeDays
    }

    if ($User.PasswordNeverExpires) {
        return @{ Expired = $false; ExpiryText = "Password never expires" }
    }

    if ($User.pwdLastSet -eq 0) {
        return @{ Expired = $false; ExpiryText = "Must change at next logon" }
    }

    if (-not $User.PasswordLastSet) {
        return @{ Expired = $false; ExpiryText = "PasswordLastSet unknown" }
    }

    $expiryDate = $User.PasswordLastSet.AddDays($maxAgeDays)

    if ($expiryDate -lt (Get-Date)) {
        return @{ Expired = $true; ExpiryText = "Expired on $(Format-Date $expiryDate)" }
    }

    return @{ Expired = $false; ExpiryText = "Will expire on $(Format-Date $expiryDate)" }
}

function Run-Search {

    Clear-Result
    $searchValue = $tbSearch.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($searchValue)) {
        $txtStatus.Text = "Please enter a search value."
        return
    }

    try { Import-Module ActiveDirectory -ErrorAction Stop }
    catch { $txtStatus.Text = "ActiveDirectory module not available."; return }

    try {
        if ($rbLogin.IsChecked) {
            $user = Get-ADUser -Filter "sAMAccountName -eq '$searchValue'" -Properties * -ErrorAction Stop
            if (-not $user) { $txtStatus.Text = "Login '$searchValue' not found."; return }
        }
        else {
            $users = @(Get-ADUser -Filter "sn -like '$searchValue'" -Properties * -ErrorAction Stop)

            if ($users.Count -eq 0) {
                $txtStatus.Text = "Surname '$searchValue' not found."
                return
            }

            if ($users.Count -gt 1) {
                $selection = $users |
                    Select-Object Name, SamAccountName, DistinguishedName |
                    Out-GridView -Title "Select user for surname '$searchValue'" -PassThru

                if (-not $selection) {
                    $txtStatus.Text = "Selection cancelled."
                    return
                }

                $user = Get-ADUser -Identity $selection.SamAccountName -Properties * -ErrorAction Stop
            }
            else {
                $user = $users[0]
            }
        }
    }
    catch {
        $txtStatus.Text = "Search error: $($_.Exception.Message)"
        return
    }

    # store current user identity for unlock
    $script:CurrentSam = $user.SamAccountName

    # Fill UI
    $txtUser.Text = "$($user.Name) ($($user.SamAccountName))"

    # Disabled
    if ($user.Enabled -eq $false) {
        $txtDisabled.Text = "Yes"
        Mark-RedBold $txtDisabled
    } else {
        $txtDisabled.Text = "No"
    }

    # Locked
    if ($user.LockedOut) {
        $txtLocked.Text = "Yes"
        Mark-RedBold $txtLocked
        $btnUnlock.Visibility = "Visible"
    } else {
        $txtLocked.Text = "No"
        $btnUnlock.Visibility = "Collapsed"
    }

    # Account expiration
    if ($user.AccountExpirationDate) {
        if ($user.AccountExpirationDate -lt (Get-Date)) {
            $txtAccExpired.Text = "Yes (expired $(Format-Date $user.AccountExpirationDate))"
            Mark-RedBold $txtAccExpired
        } else {
            $txtAccExpired.Text = "No (expires $(Format-Date $user.AccountExpirationDate))"
        }
    } else {
        $txtAccExpired.Text = "No (no expiration)"
    }

    # Must change password
    if ($user.pwdLastSet -eq 0) {
        $txtMustChange.Text = "Yes"
        Mark-RedBold $txtMustChange
    } else {
        $txtMustChange.Text = "No"
    }

    # Password expiry
    $pwdInfo = Get-PasswordExpiryInfo -User $user
    $txtPwdExpired.Text = if ($pwdInfo.Expired) { "Yes" } else { "No" }

    if ($pwdInfo.Expired) {
        Mark-RedBold $txtPwdExpired
        Mark-RedBold $txtPwdExpires
    }

    $txtPwdExpires.Text = $pwdInfo.ExpiryText
}

# Unlock button handler
$btnUnlock.Add_Click({
    if (-not $script:CurrentSam) {
        $txtStatus.Text = "No user selected to unlock."
        return
    }
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Unlock-ADAccount -Identity $script:CurrentSam -ErrorAction Stop
        $txtStatus.Text = "Account '$script:CurrentSam' unlocked successfully."
        Run-Search
    }
    catch {
        $txtStatus.Text = "Unlock failed: $($_.Exception.Message)"
    }
})

# Enter key triggers search
$window.Add_KeyDown({
    if ($_.Key -eq "Enter") { Run-Search }
})

# Search button
$btnSearch.Add_Click({ Run-Search })

$window.ShowDialog() | Out-Null