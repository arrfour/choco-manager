# Wrapper script for choco-package-explorer
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "src\Choco\choco-package-explorer.ps1") @args
