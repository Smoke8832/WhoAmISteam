<#
.SYNOPSIS
  Exports the Windows build to exports\windows\ and smoke-tests the executable.
.EXAMPLE
  .\tools\export_windows.ps1            # release build
  .\tools\export_windows.ps1 -Debug     # debug build
.NOTES
  Needs the Godot 4.7.2 export templates installed in %APPDATA%\Godot\export_templates\4.7.2.stable\
  (tools\install_templates.ps1 downloads them).
#>
param(
    [switch]$Debug,
    [string]$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\godot_console.exe"
)
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$out = Join-Path $project "exports\windows"
New-Item -ItemType Directory -Force $out | Out-Null
$exe = Join-Path $out "WhoAmIParty.exe"
$mode = if ($Debug) { "--export-debug" } else { "--export-release" }
Write-Host "Exporting ($mode)..."
& $Godot --headless --path $project $mode "Windows Desktop" $exe
if (-not (Test-Path $exe)) { throw "Export failed: $exe not found" }
# Steam API next to the executable (GDExtension expects it), plus the dev app id file.
Copy-Item (Join-Path $project "addons\godotsteam\win64\steam_api64.dll") $out -Force
Copy-Item (Join-Path $project "steam_appid.txt") $out -Force -ErrorAction SilentlyContinue
Get-ChildItem $out | Select-Object Name, @{n="MB";e={[math]::Round($_.Length/1MB,1)}}
Write-Host "Smoke test: hosting a LAN room for 8 seconds..."
$p = Start-Process -FilePath $exe -ArgumentList @("--", "--host", "--no-steam", "--name", "ExportSmoke", "--bot", "--quit-after", "8") -PassThru -RedirectStandardOutput (Join-Path $out "smoke.log") -RedirectStandardError (Join-Path $out "smoke.err")
$p.WaitForExit(30000) | Out-Null
if (-not $p.HasExited) { $p.Kill(); Write-Host "smoke test timed out" }
Get-Content (Join-Path $out "smoke.log") | Select-Object -First 8
Write-Host "Done: $exe"
