<#
.SYNOPSIS
  Runs the unit tests headless. Exit code 0 = all passed.
.EXAMPLE
  .\tools\run_tests.ps1
#>
param(
    [string]$Godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\godot_console.exe"
)
$project = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& $Godot --headless --path $project res://tests/TestMain.tscn
exit $LASTEXITCODE
