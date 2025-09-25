[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir 'node-config.json'
if (-not (Test-Path $configPath)) {
    throw "Node configuration not found at $configPath"
}

$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
$hubPort = if ($config.hubPort) { [int]$config.hubPort } else { 4444 }
$hubUrl = if ($config.hubAddress) { "http://$($config.hubAddress):$hubPort" } elseif ($config.hubUrl) { $config.hubUrl } else { 'http://127.0.0.1:4444' }
$nodePort = if ($config.port) { [int]$config.port } else { 5555 }
$maxSessions = if ($config.maxSessions) { [int]$config.maxSessions } else { 1 }
$logDir = if ($config.logDirectory) { $config.logDirectory } else { Join-Path $scriptDir 'logs' }
$nodeId = if ($config.gridNodeName) { $config.gridNodeName } else { $env:COMPUTERNAME }

$null = New-Item -Path $logDir -ItemType Directory -Force

$jarFilter = if ($config.seleniumVersion) { "selenium-server-$($config.seleniumVersion).jar" } else { 'selenium-server-*.jar' }
$seleniumJar = Get-ChildItem -Path $scriptDir -Filter $jarFilter -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $seleniumJar) {
    $seleniumJar = Get-ChildItem -Path $scriptDir -Filter 'selenium-server-*.jar' | Sort-Object FullName -Descending | Select-Object -First 1
}
if (-not $seleniumJar) {
    throw 'Unable to locate selenium-server jar. '
}

$javaCmd = Get-Command java.exe -ErrorAction SilentlyContinue
if (-not $javaCmd) {
    throw 'java.exe not found in PATH. Ensure Temurin 17 JRE is installed.'
}

function Get-ExistingNodeProcesses {
    Get-CimInstance -ClassName Win32_Process -Filter "Name='java.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine.ToLower().Contains('selenium-server')
    }
}

Get-ExistingNodeProcesses | ForEach-Object {
    try {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
    } catch {
        Write-Host "Failed to stop stale Selenium process (PID $($_.ProcessId)): $_"
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $logDir "selenium-node-$timestamp.log"

$env:GRID_NODE_NAME = $nodeId
$env:GRID_HUB_URL = $hubUrl

$arguments = @(
    '-jar', $seleniumJar.FullName,
    'node',
    '--hub', $hubUrl,
    '--port', $nodePort,
    '--max-sessions', $maxSessions,
    '--selenium-manager', 'true'
)

if ($config.driverOverride) {
    $arguments += @('--drivers', $config.driverOverride)
}

Write-Host "Starting Selenium Node. Hub: $hubUrl Port: $nodePort"

$process = Start-Process -FilePath $javaCmd.Source -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $logFile -RedirectStandardError $logFile -PassThru
$process | Out-Null
