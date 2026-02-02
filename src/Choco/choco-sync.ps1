# Sync and Remove logic
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Sync", "Remove")]
    [string]$Action,
    
    [string]$PackageName, # Used for Remove
    [string]$InputFile
)

# Load core functions
. (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "src\Core\core-functions.ps1")

if (-not $InputFile) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $InputFile = Join-Path (Resolve-Path (Join-Path $scriptRoot "..\..")) "data\choco_packages.txt"
}

if (-not (Test-IsAdmin)) {
    Write-Log "Elevation required for $Action. Re-launching..." "WARN"
    Invoke-ElevatedAction -FilePath $MyInvocation.MyCommand.Path -ArgumentList @("-Action", $Action, "-PackageName", $PackageName, "-InputFile", $InputFile)
    exit
}

if ($Action -eq "Remove") {
    if (-not $PackageName) {
        Write-Log "Package name required for Remove." "ERROR"
        return
    }

    $safeName = Get-ValidatedPackageId -Id $PackageName -Context "Chocolatey"
    if (-not $safeName) { return }
    
    Write-Log "Uninstalling package: $safeName..." "INFO"
    choco uninstall $safeName -y
    
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Successfully uninstalled $safeName. Updating list..." "SUCCESS"
        $packages = Get-PackageList -Path $InputFile
        $newPackages = $packages | Where-Object { $_ -ne $safeName }
        $newPackages | Sort-Object | Out-File -FilePath $InputFile -Encoding UTF8 -Force
    }
    else {
        Write-Log "Failed to uninstall $PackageName." "ERROR"
    }
}
elseif ($Action -eq "Sync") {
    Write-Log "Synchronizing local system with $InputFile..." "INFO"
    
    $targetPackages = Get-PackageList -Path $InputFile
    $installedPackages = choco list --local-only --limit-output | ForEach-Object { $_.Split('|')[0] }
    
    # 1. Install missing
    $toInstall = $targetPackages | Where-Object { $installedPackages -notcontains $_ }
    foreach ($p in $toInstall) {
        $safeName = Get-ValidatedPackageId -Id $p -Context "Chocolatey"
        if (-not $safeName) { continue }
        Write-Log "Sync: Installing missing package $safeName..." "INFO"
        choco install $safeName -y
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Sync: Failed to install $safeName (Exit Code: $LASTEXITCODE)." "ERROR"
        }
    }
    
    # 2. Remove orphaned (installed but not in list)
    $toRemove = $installedPackages | Where-Object { 
        # Skip chocolatey itself and other essential stuff if needed
        $targetPackages -notcontains $_ -and $_ -ne "chocolatey" -and $_ -ne "chocolatey-core.extension"
    }
    
    if ($toRemove) {
        Write-Log "Found orphaned packages: $($toRemove -join ', ')" "WARN"
        $confirm = Read-Host "Remove these packages to match list? (y/n)"
        if ($confirm -eq 'y') {
            foreach ($p in $toRemove) {
                $safeName = Get-ValidatedPackageId -Id $p -Context "Chocolatey"
                if (-not $safeName) { continue }
                Write-Log "Sync: Removing orphaned package $safeName..." "INFO"
                choco uninstall $safeName -y
                if ($LASTEXITCODE -ne 0) {
                    Write-Log "Sync: Failed to uninstall $safeName (Exit Code: $LASTEXITCODE)." "ERROR"
                }
            }
        }
    }
    
    Write-Log "Sync complete." "SUCCESS"
}
