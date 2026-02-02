# Wrapper script for choco-sync
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "src\Choco\choco-sync.ps1") @args
