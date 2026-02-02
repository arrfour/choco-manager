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
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $InputFile = Join-Path (Resolve-Path (Join-Path $scriptRoot "..\..")) "data\choco_packages.txt"
}

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
        choco upgrade $safeName -y
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to update $safeName (Exit Code: $LASTEXITCODE)." "ERROR"
        }
    }
    else {
        Write-Log "Updating all packages in $InputFile..." "INFO"
        $packages = Get-PackageList -Path $InputFile
        foreach ($p in $packages) {
            $safeName = Get-ValidatedPackageId -Id $p -Context "Chocolatey"
            if (-not $safeName) { continue }
            Write-Log "Upgrading $safeName..." "INFO"
            choco upgrade $safeName -y
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
    choco info $safeName
}
