Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

# ============================
# Modern Clean UI (Style A)
# ============================
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Chekushka" Height="520" Width="640"
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

        <!-- SEARCH BOX -->
        <Border Grid.Row="0" Background="White" Padding="12" CornerRadius="6" Margin="0,0,0,12">
            <StackPanel>
                <TextBlock Text="Search user" FontWeight="Bold" Margin="0,0,0,8"/>

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

        <!-- RESULT BOX -->
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

        <!-- STATUS BAR -->
        <Border Grid.Row="3" Background="#EDEDED" Padding="8" CornerRadius="4">
            <TextBlock x:Name="txtStatus" Foreground="Black"/>
        </Border>
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

# Current user for unlock
$script:CurrentSam = $null

# ============================
# Helper Functions
# ============================

function Set-Status {
    param([string]$Message, [bool]$IsError = $false)

    $txtStatus.Text = $Message
    $txtStatus.Foreground = if ($IsError) { "DarkRed" } else { "DarkGreen" }
}

function Clear-Result {
    foreach ($tb in @(
        $txtUser,$txtDisabled,$txtLocked,$txtPwdExpired,
        $txtAccExpired,$txtMustChange,$txtPwdExpires
    )) { $tb.Text = "" }

    foreach ($c in @(
        $txtDisabled,$txtLocked,$txtPwdExpired,
        $txtAccExpired,$txtMustChange,$txtPwdExpires
    )) {
        $c.Foreground = "Black"
        $c.FontWeight = "Normal"
    }

    $btnUnlock.Visibility = "Collapsed"
    $script:CurrentSam = $null
    Set-Status ""
}

function Mark-RedBold {
    param($control)
    $control.Foreground = "Red"
    $control.FontWeight = "Bold"
}

function Format-Date {
    param([datetime]$dt)
    $dt.ToString("dd/MM/yyyy")
}

# Cache default domain policy
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $Global:MaxPasswordAgeDays = [int](Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.TotalDays
} catch {
    $Global:MaxPasswordAgeDays = 120
}

function Get-PasswordExpiryInfo {
    param($User)

    try {
        $fgpp = Get-ADUserResultantPasswordPolicy -Identity $User.SamAccountName -ErrorAction Stop
        $maxAgeDays = [int]$fgpp.MaxPasswordAge.TotalDays
    } catch {
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

    $expiry = $User.PasswordLastSet.AddDays($maxAgeDays)
    $expired = $expiry -lt (Get-Date)

    return @{
        Expired = $expired
        ExpiryText = if ($expired) {
            "Expired on $(Format-Date $expiry)"
        } else {
            "Will expire on $(Format-Date $expiry)"
        }
    }
}

# ============================
# Main Search Logic
# ============================

function Run-Search {

    Clear-Result
    $searchValue = $tbSearch.Text.Trim()

    if (-not $searchValue) {
        Set-Status "Please enter a search value." $true
        return
    }

    $props = @(
        "Enabled","LockedOut","AccountExpirationDate",
        "pwdLastSet","PasswordLastSet","PasswordNeverExpires",
        "SamAccountName","Name"
    )

    try {
        if ($rbLogin.IsChecked) {
            $user = Get-ADUser -Filter "sAMAccountName -eq '$searchValue'" -Properties $props
            if (-not $user) { Set-Status "Login '$searchValue' not found." $true; return }
        }
        else {
            $users = @(Get-ADUser -Filter "sn -like '$searchValue*'" -Properties $props)

            if ($users.Count -eq 0) {
                Set-Status "Surname '$searchValue' not found." $true
                return
            }

            if ($users.Count -gt 1) {
                $selection = $users |
                    Select-Object Name, SamAccountName, DistinguishedName |
                    Out-GridView -Title "Select user" -PassThru

                if (-not $selection) {
                    Set-Status "Selection cancelled." $true
                    return
                }

                $user = Get-ADUser -Identity $selection.SamAccountName -Properties $props
            }
            else {
                $user = $users[0]
            }
        }
    }
    catch {
        Set-Status "Search error: $($_.Exception.Message)" $true
        return
    }

    $script:CurrentSam = $user.SamAccountName

    # Fill UI
    $txtUser.Text = "$($user.Name) ($($user.SamAccountName))"

    if (-not $user.Enabled) {
        $txtDisabled.Text = "Yes"
        Mark-RedBold $txtDisabled
    } else {
        $txtDisabled.Text = "No"
    }

    if ($user.LockedOut) {
        $txtLocked.Text = "Yes"
        Mark-RedBold $txtLocked
        $btnUnlock.Visibility = "Visible"
    } else {
        $txtLocked.Text = "No"
    }

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

    if ($user.pwdLastSet -eq 0) {
        $txtMustChange.Text = "Yes"
        Mark-RedBold $txtMustChange
    } else {
        $txtMustChange.Text = "No"
    }

    $pwdInfo = Get-PasswordExpiryInfo $user
    $txtPwdExpired.Text = if ($pwdInfo.Expired) { "Yes" } else { "No" }
    $txtPwdExpires.Text = $pwdInfo.ExpiryText

    if ($pwdInfo.Expired) {
        Mark-RedBold $txtPwdExpired
        Mark-RedBold $txtPwdExpires
    }

    Set-Status "User loaded successfully."
}

# ============================
# Unlock Handler
# ============================

$btnUnlock.Add_Click({
    if (-not $script:CurrentSam) {
        Set-Status "No user selected." $true
        return
    }

    try {
        Unlock-ADAccount -Identity $script:CurrentSam -ErrorAction Stop
        Set-Status "Account '$script:CurrentSam' unlocked."
        Run-Search
    }
    catch {
        Set-Status "Unlock failed: $($_.Exception.Message)" $true
    }
})

# Enter triggers search
$window.Add_KeyDown({
    if ($_.Key -eq "Enter") { Run-Search }
})

# Search button
$btnSearch.Add_Click({ Run-Search })

# Show window
$window.ShowDialog() | Out-Null