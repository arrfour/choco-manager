# Wrapper script for choco-utils
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "src\Choco\choco-utils.ps1") @args
