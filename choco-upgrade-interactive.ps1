# Wrapper script for choco-upgrade-interactive
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "src\Choco\choco-upgrade-interactive.ps1") @args
