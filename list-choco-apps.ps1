# Wrapper script for list-choco-apps
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "src\Choco\list-choco-apps.ps1") @args
