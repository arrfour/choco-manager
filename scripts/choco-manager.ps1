# Entry script for Choco-Manager

# Load core functions with process-scope policy + unblock
$corePath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "src\Core\core-functions.ps1"
if (-not (Test-Path $corePath)) {
    Write-Error "Core functions not found at $corePath"
    exit 1
}

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Unblock-File -Path $corePath -ErrorAction SilentlyContinue
    . $corePath
} catch {
    Write-Error "Failed to load core functions: $($_.Exception.Message)"
    exit 1
}

# Verify critical function loaded
if (-not (Get-Command Test-IsAdmin -CommandType Function -ErrorAction SilentlyContinue)) {
    Write-Error "Test-IsAdmin not loaded from $corePath"
    exit 1
}

# Main menu logic
. (Join-Path $PSScriptRoot "main-menu.ps1")
