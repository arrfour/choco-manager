# choco-upgrade-interactive.ps1
# Interactive selection for Chocolatey package upgrades

# 1. Load core functions
$corePath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "src\Core\core-functions.ps1"
if (Test-Path $corePath) { . $corePath }

# 2. Ensure Elevation (required for choco upgrade)
if (-not (Test-IsAdmin)) {
    Write-Log "Elevation required for Chocolatey upgrades. Attempting to relaunch..." "WARN"
    Invoke-ElevatedAction -FilePath $MyInvocation.MyCommand.Path
    exit
}

# 3. Get and Parse Outdated Packages
Write-Log "Checking for outdated packages (this may take a moment)..." "INFO"
# -r (or --limit-output) returns: name|current|available|pinned
$outdatedRaw = Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("outdated", "-r", "--source", (Get-TrustedChocolateySource))

$outdatedPackages = @()
foreach ($line in $outdatedRaw) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split '\|'
    # Ensure it's a data line and not a header/empty line
    if ($parts.Count -ge 3 -and $parts[0] -notmatch "^Chocolatey") {
        $outdatedPackages += [PSCustomObject]@{
            Name      = $parts[0]
            Current   = $parts[1]
            Available = $parts[2]
        }
    }
}

if ($outdatedPackages.Count -eq 0) {
    Write-Log "All packages are up to date!" "SUCCESS"
    return
}

# 4. Present Interactive Menu
Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   Interactive Chocolatey Update Menu     " -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

for ($i = 0; $i -lt $outdatedPackages.Count; $i++) {
    $p = $outdatedPackages[$i]
    $index = ($i + 1).ToString().PadRight(3)
    Write-Host "[$index] " -NoNewline -ForegroundColor White
    Write-Host "$($p.Name.PadRight(25))" -NoNewline -ForegroundColor Cyan
    Write-Host " $($p.Current) -> " -NoNewline -ForegroundColor Gray
    Write-Host "$($p.Available)" -ForegroundColor Green
}

Write-Host "`n[A]   Upgrade ALL packages" -ForegroundColor Yellow
Write-Host "[Q]   Quit" -ForegroundColor Red
Write-Host ""

$selection = Read-Host "Select package numbers (e.g. 1,3,5) or 'A' to upgrade"

# 5. Process Selection and Execute
if ($selection -match 'q') {
    return
}
elseif ($selection -match 'a') {
    Write-Log "Upgrading all outdated packages..." "INFO"
    Write-Host "Trusted Chocolatey source: $(Get-TrustedChocolateySource)" -ForegroundColor DarkGray
    if (-not (Read-Confirmation -Prompt "Upgrade all outdated packages from the approved source? Type y to continue" -ExpectedValue "y")) {
        Write-Log "Upgrade all cancelled by user." "WARN"
        return
    }
    Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("upgrade", "all", "-y", "--source", (Get-TrustedChocolateySource))
}
else {
    # Parse comma-separated input
    $indices = $selection -split ',' | ForEach-Object { $_.Trim() }
    $toUpgrade = @()
    
    foreach ($idxStr in $indices) {
        if ([int]::TryParse($idxStr, [ref]$idx) -and $idx -le $outdatedPackages.Count -and $idx -gt 0) {
            $toUpgrade += $outdatedPackages[$idx - 1].Name
        }
    }
    
    if ($toUpgrade.Count -gt 0) {
        Write-Log "Upgrading selected packages: $($toUpgrade -join ', ')" "INFO"
        foreach ($pkg in $toUpgrade) {
            $safeName = Get-ValidatedPackageId -Id $pkg -Context "Chocolatey"
            if (-not $safeName) { continue }
            Write-Log "Starting upgrade for $safeName..." "INFO"
            Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("upgrade", $safeName, "-y", "--source", (Get-TrustedChocolateySource))
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Successfully upgraded $safeName" "SUCCESS"
            } else {
                Write-Log "Failed to upgrade $safeName (Exit Code: $LASTEXITCODE)" "ERROR"
            }
        }
    }
    else {
        Write-Log "No valid packages selected." "WARN"
    }
}

Write-Log "Update process complete." "SUCCESS"
