# Install Chocolatey packages from a file
param(
    [string]$InputFile,
    [switch]$SkipUpgradeChoco
)

# Load core functions
. (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "src\Core\core-functions.ps1")

if (-not $InputFile) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $InputFile = Join-Path (Resolve-Path (Join-Path $scriptRoot "..\..")) "data\choco_packages.txt"
}

if (-not (Test-IsAdmin)) {
    Write-Log "Elevation required for installation. Re-launching..." "WARN"
    Invoke-ElevatedAction -FilePath $MyInvocation.MyCommand.Path -ArgumentList @("-InputFile", $InputFile)
    exit
}

Write-Log "Starting installation process..." "INFO"

if (-not $SkipUpgradeChoco) {
    Write-Log "Checking for Chocolatey updates..." "INFO"
    choco upgrade chocolatey -y
}

# Get currently installed packages for comparison
$installedPackages = choco list --local-only --limit-output | ForEach-Object { $_.Split('|')[0] }

# Read target packages using core helper
    $targetPackages = Get-PackageList -Path $InputFile

if ($targetPackages.Count -eq 0) {
    Write-Log "No packages found in $InputFile to install." "WARN"
    exit
}

foreach ($packageName in $targetPackages) {
    $safeName = Get-ValidatedPackageId -Id $packageName -Context "Chocolatey"
    if (-not $safeName) { continue }
    if ($installedPackages -contains $safeName) {
        Write-Log "Skipping '$safeName' - already installed." "INFO"
    }
    else {
        Write-Log "Installing '$safeName'..." "INFO"
        choco install $safeName -y
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Successfully installed '$safeName'." "SUCCESS"
        }
        else {
            Write-Log "Failed to install '$safeName' (Exit Code: $LASTEXITCODE)." "ERROR"
        }
    }
}

Write-Log "Installation process finished." "SUCCESS"
