# Wrapper script for choco-pack-install
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "src\Choco\choco-pack-install.ps1") @args
