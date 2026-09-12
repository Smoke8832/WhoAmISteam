<#
.SYNOPSIS
  Rejoin test: host + 2 bot clients; one client is killed mid-round and relaunched with the
  same rejoin token. Passes if the host log shows the player coming back and the round continues.
.EXAMPLE
  .\tools\test_rejoin.ps1
#>
param(
    [int]$Port = 7799,
    [string]$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\godot_console.exe"
)
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $project ".logs\rejoin-$stamp"
New-Item -ItemType Directory -Force $logDir | Out-Null
$token = "rejointest-$stamp"

function Start-Inst([string]$label, [string[]]$userArgs, [int]$x) {
    $args = @("--path", $project, "--resolution", "800x450", "--position", "$x,60", "--") + $userArgs + @("--name", $label, "--bot", "--fast", "--no-steam")
    return Start-Process -FilePath $Godot -ArgumentList $args -PassThru -RedirectStandardOutput (Join-Path $logDir "$label.log") -RedirectStandardError (Join-Path $logDir "$label.err.log")
}

$host_ = Start-Inst "Host" @("--host", "--port", "$Port", "--quit-after", "75") 20
Start-Sleep -Seconds 3
$c1 = Start-Inst "Client1" @("--join", "127.0.0.1", "--port", "$Port", "--quit-after", "75") 840
$c2 = Start-Inst "Rejoiner" @("--join", "127.0.0.1", "--port", "$Port", "--rejoin-token", $token, "--quit-after", "60") 20
Write-Host "Waiting for the round to reach GUESSING..."
$deadline = (Get-Date).AddSeconds(50)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    if (Select-String -Path (Join-Path $logDir "Host.log") -Pattern "screenshot .*guessing" -Quiet -ErrorAction SilentlyContinue) { break }
}
Write-Host "Killing Rejoiner mid-round..."
if (-not $c2.HasExited) { $c2.Kill() }
Start-Sleep -Seconds 4
Write-Host "Relaunching Rejoiner with the same token..."
$c3 = Start-Inst "Rejoiner2" @("--join", "127.0.0.1", "--port", "$Port", "--rejoin-token", $token, "--quit-after", "30") 20
$c3.WaitForExit(45000) | Out-Null
foreach ($p in @($host_, $c1, $c3)) { if (-not $p.HasExited) { $p.WaitForExit(20000) | Out-Null }; if (-not $p.HasExited) { $p.Kill() } }
Write-Host "--- host log (rejoin-related)"
Select-String -Path (Join-Path $logDir "Host.log") -Pattern "disconnected|is back|Round|round\]|secrecy" | ForEach-Object { $_.Line } | Select-Object -First 40
Write-Host "--- rejoiner2 log"
Select-String -Path (Join-Path $logDir "Rejoiner2.log") -Pattern "secrecy|screenshot|bot\]" | ForEach-Object { $_.Line } | Select-Object -First 12
Write-Host "--- errors"
Get-ChildItem $logDir -Filter *.err.log | ForEach-Object { $e = Select-String -Path $_.FullName -Pattern "SCRIPT ERROR|ERROR" ; "{0}: {1} error lines" -f $_.Name, $e.Count; $e | Select-Object -First 3 | ForEach-Object { "   $($_.Line)" } }
