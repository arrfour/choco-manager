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
    $InputFile = Get-DefaultPackageListPath
}

$InputFile = Resolve-ManagedDataFilePath -Path $InputFile -Purpose "package list"

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
    Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("uninstall", $safeName, "-y")
    
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
    $installedPackages = Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("list", "--local-only", "--limit-output") | ForEach-Object { $_.Split('|')[0] }
    
    # 1. Install missing
    $toInstall = $targetPackages | Where-Object { $installedPackages -notcontains $_ }
    if ($toInstall.Count -gt 0) {
        Write-Host "Trusted Chocolatey source: $(Get-TrustedChocolateySource)" -ForegroundColor DarkGray
        if (-not (Read-Confirmation -Prompt "Install $($toInstall.Count) missing package(s) from the approved source? Type y to continue" -ExpectedValue "y")) {
            Write-Log "Sync install phase cancelled by user." "WARN"
            $toInstall = @()
        }
    }
    foreach ($p in $toInstall) {
        $safeName = Get-ValidatedPackageId -Id $p -Context "Chocolatey"
        if (-not $safeName) { continue }
        Write-Log "Sync: Installing missing package $safeName..." "INFO"
        Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("install", $safeName, "-y", "--source", (Get-TrustedChocolateySource))
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
        if (Read-Confirmation -Prompt "Remove $($toRemove.Count) orphaned package(s) to match the approved list? Type y to continue" -ExpectedValue "y") {
            foreach ($p in $toRemove) {
                $safeName = Get-ValidatedPackageId -Id $p -Context "Chocolatey"
                if (-not $safeName) { continue }
                Write-Log "Sync: Removing orphaned package $safeName..." "INFO"
                Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("uninstall", $safeName, "-y")
                if ($LASTEXITCODE -ne 0) {
                    Write-Log "Sync: Failed to uninstall $safeName (Exit Code: $LASTEXITCODE)." "ERROR"
                }
            }
        } else {
            Write-Log "Sync remove phase cancelled by user." "WARN"
        }
    }
    
    Write-Log "Sync complete." "SUCCESS"
}
