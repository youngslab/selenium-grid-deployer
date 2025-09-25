[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logRoot = 'C:\Provisioning\logs'
$null = New-Item -Path $logRoot -ItemType Directory -Force
$logFile = Join-Path $logRoot 'packer-install.log'

Start-Transcript -Path $logFile -Append | Out-Null

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] $Message"
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $defaultSeleniumVersion = '4.23.0'
    $defaultHubIp = '192.168.0.10'
    $defaultGridUser = 'griduser'
    $defaultGridPass = 'GridUser!ChangeMe'
    $defaultEdgeChannel = 'Stable'

    $seleniumVersion = if ($env:PKR_SELENIUM_VERSION) { $env:PKR_SELENIUM_VERSION } else { $defaultSeleniumVersion }
    $hubIp           = if ($env:PKR_HUB_IP)           { $env:PKR_HUB_IP }           else { $defaultHubIp }
    $gridUser        = if ($env:PKR_GRID_USER)        { $env:PKR_GRID_USER }        else { $defaultGridUser }
    $gridPass        = if ($env:PKR_GRID_PASS)        { $env:PKR_GRID_PASS }        else { $defaultGridPass }
    $edgeChannel     = if ($env:PKR_EDGE_CHANNEL)     { $env:PKR_EDGE_CHANNEL }     else { $defaultEdgeChannel }

    Write-Log "Using settings: Selenium v$seleniumVersion, Hub $hubIp, Grid user $gridUser"

    $seleniumRoot = 'C:\selenium'
    $seleniumLogDir = Join-Path $seleniumRoot 'logs'
    $driverRoot = Join-Path $seleniumRoot 'drivers'
    foreach ($path in @($seleniumRoot, $seleniumLogDir, $driverRoot)) {
        $null = New-Item -Path $path -ItemType Directory -Force
    }

    function Ensure-Chocolatey {
        $chocoExe = 'C:\\ProgramData\\chocolatey\\bin\\choco.exe'
        if (Test-Path $chocoExe) {
            Write-Log 'Chocolatey already installed.'
            return $chocoExe
        }

        Write-Log 'Installing Chocolatey (bootstrap).'
        Set-ExecutionPolicy Bypass -Scope Process -Force
        $installer = 'https://chocolatey.org/install.ps1'
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString($installer))
        if (-not (Test-Path $chocoExe)) {
            throw 'Chocolatey installation failed.'
        }
        & $chocoExe feature enable -n allowGlobalConfirmation | Out-Null
        return $chocoExe
    }

    $choco = Ensure-Chocolatey

    function Install-ChocoPackage {
        param(
            [string]$PackageName,
            [string]$Version
        )

        $args = @('install', $PackageName, '--limit-output', '--yes')
        if ($Version) {
            $args += @('--version', $Version)
        }
        Write-Log "Installing package via choco: $PackageName"
        & $choco @args | Out-Null
    }

    Install-ChocoPackage -PackageName 'temurin17jre'

    switch ($edgeChannel.ToLowerInvariant()) {
        'beta'    { Install-ChocoPackage -PackageName 'microsoft-edge-beta' }
        'dev'     { Install-ChocoPackage -PackageName 'microsoft-edge-dev' }
        default   { Install-ChocoPackage -PackageName 'microsoft-edge' }
    }

    # Ensure Edge WebDriver matches installed Edge
    function Install-EdgeDriver {
        $edgeExe = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
        if (-not (Test-Path $edgeExe)) {
            throw 'Microsoft Edge is not installed. Cannot download matching WebDriver.'
        }

        $edgeVersion = (Get-Item $edgeExe).VersionInfo.ProductVersion
        Write-Log "Detected Edge version $edgeVersion"
        $edgeMajor = $edgeVersion.Split('.')[0]
        $driverVersionUri = "https://msedgedriver.azureedge.net/LATEST_RELEASE_$edgeMajor"
        $driverVersion = (Invoke-WebRequest -Uri $driverVersionUri -UseBasicParsing).Content.Trim()
        Write-Log "Matched Edge WebDriver version $driverVersion"

        $driverZip = Join-Path $env:TEMP 'msedgedriver.zip'
        $driverUrl = "https://msedgedriver.azureedge.net/$driverVersion/edgedriver_win64.zip"
        Write-Log "Downloading Edge WebDriver from $driverUrl"
        Invoke-WebRequest -Uri $driverUrl -OutFile $driverZip -UseBasicParsing

        if (Test-Path $driverRoot) {
            Get-ChildItem -Path $driverRoot -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
        $null = New-Item -Path $driverRoot -ItemType Directory -Force

        Expand-Archive -Path $driverZip -DestinationPath $driverRoot -Force
        $driverExe = Get-ChildItem -Path $driverRoot -Filter 'msedgedriver.exe' -Recurse | Select-Object -First 1
        if (-not $driverExe) {
            throw 'Edge WebDriver binary was not found after extraction.'
        }

        Copy-Item -Path $driverExe.FullName -Destination (Join-Path $seleniumRoot 'msedgedriver.exe') -Force
        Remove-Item $driverZip -Force
    }

    Install-EdgeDriver

    # Download Selenium Server jar
    $seleniumJarName = "selenium-server-$seleniumVersion.jar"
    $seleniumJarPath = Join-Path $seleniumRoot $seleniumJarName
    if (-not (Test-Path $seleniumJarPath)) {
        $seleniumUrl = "https://github.com/SeleniumHQ/selenium/releases/download/selenium-$seleniumVersion/$seleniumJarName"
        Write-Log "Downloading Selenium Server from $seleniumUrl"
        Invoke-WebRequest -Uri $seleniumUrl -OutFile $seleniumJarPath -UseBasicParsing
    } else {
        Write-Log 'Selenium Server jar already present - skipping download.'
    }

    # Persist configuration for node scripts
    $configPath = Join-Path $seleniumRoot 'node-config.json'
    $config = [ordered]@{
        hubAddress      = $hubIp
        hubPort         = 4444
        seleniumVersion = $seleniumVersion
        port            = 5555
        maxSessions     = 1
        logDirectory    = $seleniumLogDir
        gridNodeName    = $env:COMPUTERNAME
    }
    $config | ConvertTo-Json -Depth 3 | Set-Content -Path $configPath -Encoding UTF8

    # Copy helper scripts from Packer temp upload location
    $uploadedStart = 'C:\\Windows\\Temp\\start-node.ps1'
    $uploadedWatchdog = 'C:\\Windows\\Temp\\watchdog.ps1'
    if (-not (Test-Path $uploadedStart) -or -not (Test-Path $uploadedWatchdog)) {
        throw 'Required helper scripts were not uploaded.'
    }

    Copy-Item -Path $uploadedStart -Destination (Join-Path $seleniumRoot 'start-node.ps1') -Force
    Copy-Item -Path $uploadedWatchdog -Destination (Join-Path $seleniumRoot 'watchdog.ps1') -Force

    # Create least privilege autologon account
    $securePassword = ConvertTo-SecureString $gridPass -AsPlainText -Force
    $existingUser = Get-LocalUser -Name $gridUser -ErrorAction SilentlyContinue
    if ($existingUser) {
        Write-Log "Updating existing account $gridUser"
        Set-LocalUser -Name $gridUser -Password $securePassword
        Set-LocalUser -Name $gridUser -AccountNeverExpires $true
    } else {
        Write-Log "Creating local account $gridUser"
        New-LocalUser -Name $gridUser -Password $securePassword -FullName 'Selenium Grid Node' -Description 'Autologon account for Selenium Grid Node' -PasswordNeverExpires $true -AccountNeverExpires $true | Out-Null
    }
    try {
        & wmic useraccount where "Name='$gridUser'" set PasswordExpires=false | Out-Null
    } catch {
        Write-Log "Unable to mark password as non-expiring via WMIC: $_"
    }

    Add-LocalGroupMember -Group 'Users' -Member $gridUser -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $gridUser -ErrorAction SilentlyContinue
    Set-LocalUser -Name $gridUser -UserMayChangePassword $false

    # Configure Autologon registry keys
    $winlogonKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-ItemProperty -Path $winlogonKey -Name 'AutoAdminLogon' -Value '1'
    Set-ItemProperty -Path $winlogonKey -Name 'ForceAutoLogon' -Value '1'
    Set-ItemProperty -Path $winlogonKey -Name 'DefaultUserName' -Value $gridUser
    Set-ItemProperty -Path $winlogonKey -Name 'DefaultPassword' -Value $gridPass
    Set-ItemProperty -Path $winlogonKey -Name 'DefaultDomainName' -Value $env:COMPUTERNAME
    Remove-ItemProperty -Path $winlogonKey -Name 'AutoLogonCount' -ErrorAction SilentlyContinue

    # Disable sleep / lock
    Write-Log 'Disabling system sleep, lock screen, and screen saver.'
    powercfg -change -monitor-timeout-ac 0
    powercfg -change -monitor-timeout-dc 0
    powercfg -change -standby-timeout-ac 0
    powercfg -change -standby-timeout-dc 0
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v NoLockScreen /t REG_DWORD /d 1 /f | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableLockWorkstation /t REG_DWORD /d 1 /f | Out-Null
    reg add "HKU\\.DEFAULT\Control Panel\Desktop" /v ScreenSaveActive /t REG_SZ /d 0 /f | Out-Null

    # Expose helpful environment variables
    [Environment]::SetEnvironmentVariable('GRID_HUB_IP', $hubIp, 'Machine')
    [Environment]::SetEnvironmentVariable('GRID_HUB_URL', "http://$hubIp:4444", 'Machine')
    [Environment]::SetEnvironmentVariable('SELENIUM_VERSION', $seleniumVersion, 'Machine')
    [Environment]::SetEnvironmentVariable('SELENIUM_HOME', $seleniumRoot, 'Machine')

    # Register scheduled tasks
    Import-Module ScheduledTasks

    $taskPath = '\\SeleniumGrid\\'
    $principal = New-ScheduledTaskPrincipal -UserId $gridUser -LogonType InteractiveToken -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)

    $startAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$seleniumRoot\start-node.ps1`""
    $startTrigger = New-ScheduledTaskTrigger -AtLogOn -User $gridUser
    Register-ScheduledTask -TaskName 'StartNodeOnLogon' -TaskPath $taskPath -Action $startAction -Trigger $startTrigger -Principal $principal -Settings $settings -Force | Out-Null

    $watchAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$seleniumRoot\watchdog.ps1`""
    $watchTrigger = New-ScheduledTaskTrigger -Once (Get-Date).AddMinutes(1)
    $watchTrigger.RepetitionInterval = [TimeSpan]::FromMinutes(5)
    $watchTrigger.RepetitionDuration = [TimeSpan]::FromDays(3650)
    Register-ScheduledTask -TaskName 'NodeWatchdog' -TaskPath $taskPath -Action $watchAction -Trigger $watchTrigger -Principal $principal -Settings $settings -Force | Out-Null

    $cleanupAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$seleniumRoot\watchdog.ps1`" -StartupCleanup"
    $cleanupTrigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName 'StartupCleanup' -TaskPath $taskPath -Action $cleanupAction -Trigger $cleanupTrigger -Principal $principal -Settings $settings -Force | Out-Null

    Write-Log 'Provisioning completed successfully.'
}
catch {
    Write-Log "ERROR: $_"
    throw
}
finally {
    Stop-Transcript | Out-Null
}
