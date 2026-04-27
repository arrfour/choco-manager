# Export local Chocolatey packages to a file
param(
    [string]$OutputFile
)

# Load core functions
. (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "src\Core\core-functions.ps1")

if (-not $OutputFile) {
    $OutputFile = Get-DefaultPackageListPath
}

$OutputFile = Resolve-ManagedDataFilePath -Path $OutputFile -Purpose "package export"

Write-Log "Exporting local Chocolatey packages to $OutputFile..." "INFO"

try {
    # Query choco for installed packages
    # --idonly and --limit-output provide a clean list
    $packages = Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("list", "--idonly", "--limit-output")
    
    if ($LASTEXITCODE -ne 0) {
        throw "Chocolatey command failed with exit code $LASTEXITCODE"
    }

    $sortedPackages = $packages | Sort-Object | Select-Object -Unique

    # Save to file
    $outputDirectory = Split-Path -Parent $OutputFile
    if (-not (Test-Path $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    $sortedPackages | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
    
    Write-Log "Successfully exported $($sortedPackages.Count) packages." "SUCCESS"
}
catch {
    Write-Log "Failed to export packages: $($_.Exception.Message)" "ERROR"
    exit 1
}
