[CmdletBinding()]
param(
    [switch]$StartupCleanup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir 'node-config.json'
if (-not (Test-Path $configPath)) {
    throw "Node configuration not found at $configPath"
}

$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
$logDir = if ($config.logDirectory) { $config.logDirectory } else { Join-Path $scriptDir 'logs' }
$null = New-Item -Path $logDir -ItemType Directory -Force
$logFile = Join-Path $logDir 'watchdog.log'

function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$stamp $Message" | Tee-Object -FilePath $logFile -Append | Out-Null
}

function Stop-ProcessSafe {
    param([System.Diagnostics.Process]$Process)
    try {
        $name = $Process.ProcessName
        $Process | Stop-Process -Force -ErrorAction Stop
        Write-Log "Stopped lingering process $name (PID $($Process.Id))"
    } catch {
        Write-Log "Failed to stop process: $_"
    }
}

function Get-NodeProcesses {
    Get-CimInstance -ClassName Win32_Process -Filter "Name='java.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine.ToLower().Contains('selenium-server')
    }
}

# Clean unnecessary Edge driver instances
function Cleanup-EdgeArtifacts {
    $targets = @('msedgedriver', 'msedgewebview2', 'msedge')
    foreach ($name in $targets) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object { Stop-ProcessSafe -Process $_ }
    }
}

if ($StartupCleanup) {
    Write-Log 'Running startup cleanup routine.'
    Cleanup-EdgeArtifacts
    Get-NodeProcesses | ForEach-Object {
        try {
            $proc = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
            if ($proc) {
                Stop-ProcessSafe -Process $proc
            }
        } catch {
            Write-Log "Failed to stop Selenium process during cleanup: $_"
        }
    }
    return
}

$nodeProcesses = @()
Get-NodeProcesses | ForEach-Object {
    $proc = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
    if ($proc) {
        $nodeProcesses += $proc
    }
}

if (-not $nodeProcesses -or $nodeProcesses.Count -eq 0) {
    Write-Log 'Selenium node process not detected. Restarting via start-node.ps1.'
    $startScript = Join-Path $scriptDir 'start-node.ps1'
    Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`"" -WindowStyle Hidden | Out-Null
} else {
    Write-Log "Node process healthy (count: $($nodeProcesses.Count))."
}

Cleanup-EdgeArtifacts
