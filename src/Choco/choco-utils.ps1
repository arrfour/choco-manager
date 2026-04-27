# Helper script for Update and Info features
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Update", "Info")]
    [string]$Action,
    
    [string]$PackageName, # If null, Update applies to all in list
    [string]$InputFile
)

# Load core functions
. (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "src\Core\core-functions.ps1")

if (-not $InputFile) {
    $InputFile = Get-DefaultPackageListPath
}

$InputFile = Resolve-ManagedDataFilePath -Path $InputFile -Purpose "package list"

if ($Action -eq "Update") {
    if (-not (Test-IsAdmin)) {
        Write-Log "Elevation required for Update. Re-launching..." "WARN"
        Invoke-ElevatedAction -FilePath $MyInvocation.MyCommand.Path -ArgumentList @("-Action", "Update", "-PackageName", $PackageName, "-InputFile", $InputFile)
        exit
    }

    if ($PackageName) {
        $safeName = Get-ValidatedPackageId -Id $PackageName -Context "Chocolatey"
        if (-not $safeName) { return }
        Write-Log "Updating package: $safeName..." "INFO"
        Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("upgrade", $safeName, "-y", "--source", (Get-TrustedChocolateySource))
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to update $safeName (Exit Code: $LASTEXITCODE)." "ERROR"
        }
    }
    else {
        Write-Log "Updating all packages in $InputFile..." "INFO"
        $packages = Get-PackageList -Path $InputFile
        if ($packages.Count -eq 0) {
            Write-Log "No packages found in $InputFile to update." "WARN"
            return
        }
        Write-Host "Trusted Chocolatey source: $(Get-TrustedChocolateySource)" -ForegroundColor DarkGray
        if (-not (Read-Confirmation -Prompt "Upgrade $($packages.Count) package(s) from the approved source? Type y to continue" -ExpectedValue "y")) {
            Write-Log "Update action cancelled by user." "WARN"
            return
        }
        foreach ($p in $packages) {
            $safeName = Get-ValidatedPackageId -Id $p -Context "Chocolatey"
            if (-not $safeName) { continue }
            Write-Log "Upgrading $safeName..." "INFO"
            Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("upgrade", $safeName, "-y", "--source", (Get-TrustedChocolateySource))
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Failed to update $safeName (Exit Code: $LASTEXITCODE)." "ERROR"
            }
        }
    }
    Write-Log "Update action complete." "SUCCESS"
}
elseif ($Action -eq "Info") {
    if (-not $PackageName) {
        Write-Log "Package name is required for Info action." "ERROR"
        return
    }
    
    $safeName = Get-ValidatedPackageId -Id $PackageName -Context "Chocolatey"
    if (-not $safeName) { return }
    Write-Log "Fetching info for $safeName..." "INFO"
    Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("info", $safeName, "--source", (Get-TrustedChocolateySource))
}
