# Wrapper script for winget-utils
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "src\Winget\winget-utils.ps1") @args
