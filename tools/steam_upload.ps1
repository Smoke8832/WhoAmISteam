<#
.SYNOPSIS
  Uploads exports\windows\ to Steam with steamcmd (SteamPipe).
.EXAMPLE
  .\tools\steam_upload.ps1 -AppId 1234560 -DepotId 1234561 -Username mysteamlogin -Branch playtest
.NOTES
  Requires steamcmd (https://developer.valvesoftware.com/wiki/SteamCMD) and a Steamworks account
  with upload rights. The first run asks for the Steam Guard code interactively.
  Fill APP_ID / DEPOT_ID once you have them (docs/STEAM.md).
#>
param(
    [Parameter(Mandatory=$true)][int]$AppId,
    [Parameter(Mandatory=$true)][int]$DepotId,
    [Parameter(Mandatory=$true)][string]$Username,
    [string]$Branch = "",
    [string]$Description = "Who Am I? Party build $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    [string]$SteamCmd = "steamcmd"
)
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$content = Join-Path $project "exports\windows"
if (-not (Test-Path (Join-Path $content "WhoAmIParty.exe"))) { throw "Run tools\export_windows.ps1 first." }
$buildDir = Join-Path $project "exports\steam"
New-Item -ItemType Directory -Force $buildDir | Out-Null
$vdf = @"
"AppBuild"
{
    "AppID" "$AppId"
    "Desc" "$Description"
    "SetLive" "$Branch"
    "ContentRoot" "$content"
    "BuildOutput" "$buildDir\output"
    "Depots"
    {
        "$DepotId"
        {
            "FileMapping"
            {
                "LocalPath" "*"
                "DepotPath" "."
                "recursive" "1"
            }
            "FileExclusion" "*.log"
            "FileExclusion" "smoke.err"
            "FileExclusion" "steam_appid.txt"
        }
    }
}
"@
$vdfPath = Join-Path $buildDir "app_build.vdf"
Set-Content -Path $vdfPath -Value $vdf -Encoding ASCII
Write-Host "Uploading with $vdfPath"
& $SteamCmd +login $Username +run_app_build $vdfPath +quit
