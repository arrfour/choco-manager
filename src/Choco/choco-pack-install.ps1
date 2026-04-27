# Install Chocolatey packages from a file
param(
    [string]$InputFile,
    [switch]$SkipUpgradeChoco
)

# Load core functions
. (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "src\Core\core-functions.ps1")

if (-not $InputFile) {
    $InputFile = Get-DefaultPackageListPath
}

$InputFile = Resolve-ManagedDataFilePath -Path $InputFile -Purpose "package list"

if (-not (Test-IsAdmin)) {
    Write-Log "Elevation required for installation. Re-launching..." "WARN"
    Invoke-ElevatedAction -FilePath $MyInvocation.MyCommand.Path -ArgumentList @("-InputFile", $InputFile)
    exit
}

Write-Log "Starting installation process..." "INFO"

if (-not $SkipUpgradeChoco) {
    Write-Log "Checking for Chocolatey updates..." "INFO"
    Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("upgrade", "chocolatey", "-y", "--source", (Get-TrustedChocolateySource))
}

# Get currently installed packages for comparison
$installedPackages = Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("list", "--local-only", "--limit-output") | ForEach-Object { $_.Split('|')[0] }
$installedPackageSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($installedPackage in $installedPackages) {
    if (-not [string]::IsNullOrWhiteSpace($installedPackage)) {
        $null = $installedPackageSet.Add($installedPackage)
    }
}

# Read target packages using core helper
$targetPackages = Get-PackageList -Path $InputFile

if ($targetPackages.Count -eq 0) {
    Write-Log "No packages found in $InputFile to install." "WARN"
    exit
}

$missingPackages = $targetPackages | Where-Object { -not $installedPackageSet.Contains($_) }
if ($missingPackages.Count -eq 0) {
    Write-Log "All packages from $InputFile are already installed." "SUCCESS"
    exit
}

Write-Host "Trusted Chocolatey source: $(Get-TrustedChocolateySource)" -ForegroundColor DarkGray
if (-not (Read-Confirmation -Prompt "Install $($missingPackages.Count) missing package(s)? Type y to continue" -ExpectedValue "y")) {
    Write-Log "Installation cancelled by user." "WARN"
    exit
}

foreach ($packageName in $missingPackages) {
    $safeName = Get-ValidatedPackageId -Id $packageName -Context "Chocolatey"
    if (-not $safeName) { continue }

    Write-Log "Installing '$safeName'..." "INFO"
    Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("install", $safeName, "-y", "--source", (Get-TrustedChocolateySource))
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Successfully installed '$safeName'." "SUCCESS"
    }
    else {
        Write-Log "Failed to install '$safeName' (Exit Code: $LASTEXITCODE)." "ERROR"
    }
}

Write-Log "Installation process finished." "SUCCESS"
