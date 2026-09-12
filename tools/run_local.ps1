<#
.SYNOPSIS
  Launches a local host plus N clients of Who Am I? Party over ENet for testing.
.EXAMPLE
  .\tools\run_local.ps1 -Clients 2 -Bot -Duration 40
  .\tools\run_local.ps1 -Clients 1                # play with yourself, two windows
.NOTES
  Godot is expected via winget (godot_console.exe). Override with -Godot <path>.
  Logs go to .logs\, screenshots (bot mode) to screenshots\<timestamp>\.
#>
param(
    [int]$Clients = 2,
    [switch]$Bot,
    [int]$Duration = 0,
    [int]$Port = 7777,
    [string]$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\godot_console.exe",
    [string]$ScreenshotDir = "",
    [switch]$Headless,
    [switch]$Fast
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $project ".logs\$stamp"
New-Item -ItemType Directory -Force $logDir | Out-Null
if ($ScreenshotDir -eq "") { $ScreenshotDir = Join-Path $project "screenshots\$stamp" }

function Start-Instance([string]$label, [string[]]$userArgs, [int]$x, [int]$y) {
    $args = @("--path", $project, "--resolution", "960x540", "--position", "$x,$y")
    if ($Headless) { $args = @("--path", $project, "--headless") }
    $args += "--"
    $args += $userArgs
    $args += @("--name", $label)
    if ($Bot) { $args += @("--bot", "--screenshot-dir", $ScreenshotDir) }
    if ($Fast) { $args += "--fast" }
    if ($Duration -gt 0) { $args += @("--quit-after", "$Duration") }
    $out = Join-Path $logDir "$label.log"
    $err = Join-Path $logDir "$label.err.log"
    Write-Host "▶ $label : godot $($args -join ' ')"
    return Start-Process -FilePath $Godot -ArgumentList $args -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Normal
}

$procs = @()
$procs += Start-Instance "Host" @("--host", "--port", "$Port") 20 40
Start-Sleep -Seconds 3
for ($i = 1; $i -le $Clients; $i++) {
    $x = 20 + ($i % 2) * 980
    $y = 40 + [math]::Floor($i / 2) * 580
    $procs += Start-Instance "Client$i" @("--join", "127.0.0.1", "--port", "$Port") $x $y
    Start-Sleep -Milliseconds 800
}

Write-Host "Launched $($procs.Count) instances. Logs: $logDir"
if ($Duration -gt 0) {
    $deadline = (Get-Date).AddSeconds($Duration + 10)
    while ((Get-Date) -lt $deadline -and ($procs | Where-Object { -not $_.HasExited }).Count -gt 0) {
        Start-Sleep -Seconds 1
    }
    $procs | Where-Object { -not $_.HasExited } | ForEach-Object { $_.Kill() }
    Write-Host "--- summary"
    Get-ChildItem $logDir -Filter *.log | ForEach-Object {
        $errors = Select-String -Path $_.FullName -Pattern "ERROR|SCRIPT ERROR|Parse Error|Failed" -SimpleMatch:$false
        Write-Host ("{0}: {1} lines, {2} error lines" -f $_.Name, (Get-Content $_.FullName).Count, $errors.Count)
        $errors | Select-Object -First 5 | ForEach-Object { Write-Host "   $($_.Line)" }
    }
    if ($Bot) { Write-Host "Screenshots: $ScreenshotDir"; Get-ChildItem $ScreenshotDir -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name }
}
