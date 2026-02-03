# Basic Winget wrapper for Choco-Manager
param(
    [ValidateSet("Install", "List", "Search", "Info", "Remove", "Interactive", "ListOnly")]
    [string]$Action = "Interactive",
    
    [string]$PackageId,
    [string]$Query
)

# Load core functions
. (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "src\Core\core-functions.ps1")

function Test-Winget {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    return $null -ne $winget
}

if (-not (Test-Winget)) {
    Write-Log "Winget not found on this system." "ERROR"
    return
}

function Invoke-WingetList {
    Write-Log "Fetching Winget packages..." "INFO"
    $raw = winget list
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Winget list failed (Exit Code: $LASTEXITCODE)." "ERROR"
        return
    }

    $packages = @()
    foreach ($line in $raw) {
        if ($line -match '^\s*Name\s+Id\s+Version') { continue }
        if ($line -match '^-{2,}') { continue }
        if ($line -match '^\S') {
            $parts = $line -split '\s{2,}'
            if ($parts.Count -ge 3) {
                $name = $parts[0]
                $id = $parts[1]
                $version = $parts[2]
                $source = if ($parts.Count -ge 4) { $parts[-1] } else { "winget" }
                if ($id) {
                    $packages += [PSCustomObject]@{ Id = $id; Name = $name; Version = $version; Display = (Format-PackageRow -Name $name -Version $version -Source $source) }
                }
            }
        }
    }

    if ($packages.Count -eq 0) {
        Write-Log "No Winget packages found." "WARN"
        return
    }

    $sortModes = @("Name (A-Z)")
    $script:CurrentSortedWingetList = @()
    $applySort = {
        param($sortIndex)
        $script:CurrentSortedWingetList = $packages | Sort-Object Id
        return $script:CurrentSortedWingetList | ForEach-Object { $_.Display }
    }

    $displayItems = & $applySort 0
    $selected = Get-MenuSelection -Items $displayItems -Title "--- Winget Packages ---" -EnablePaging -PageSize 10 -SortModes $sortModes -SortIndex 0 -SortHandler $applySort -HeaderRow (Format-PackageRow -Name "Name" -Version "Version" -Source "Source")
    if ($selected) {
        $pkgId = ($script:CurrentSortedWingetList | Where-Object { $_.Display -eq $selected }).Id
        $safeId = Get-ValidatedPackageId -Id $pkgId -Context "Winget"
        if ($safeId) {
            Write-Host "`n--- Winget Info for $safeId ---" -ForegroundColor Yellow
            winget show --id $safeId
            Pause
        }
    }
}

function Invoke-WingetInstall {
    param([string]$Id)
    $safeId = Get-ValidatedPackageId -Id $Id -Context "Winget"
    if (-not $safeId) { return }

    Write-Log "Installing '$safeId' via Winget..." "INFO"
    winget install --id $safeId --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Successfully installed $safeId via Winget." "SUCCESS"
    }
    else {
        Write-Log "Winget failed to install $safeId (Exit Code: $LASTEXITCODE)." "ERROR"
    }
}

function Invoke-WingetInfo {
    param([string]$Id)
    $safeId = Get-ValidatedPackageId -Id $Id -Context "Winget"
    if (-not $safeId) { return }

    Write-Log "Fetching Winget info for '$safeId'..." "INFO"
    winget show --id $safeId
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Winget info failed for $safeId (Exit Code: $LASTEXITCODE)." "ERROR"
    }
}

function Invoke-WingetRemove {
    param([string]$Id)
    $safeId = Get-ValidatedPackageId -Id $Id -Context "Winget"
    if (-not $safeId) { return }

    Write-Log "Uninstalling '$safeId' via Winget..." "INFO"
    winget uninstall --id $safeId --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Successfully uninstalled $safeId via Winget." "SUCCESS"
    }
    else {
        Write-Log "Winget failed to uninstall $safeId (Exit Code: $LASTEXITCODE)." "ERROR"
    }
}

function Invoke-WingetSearchInteractive {
    param([string]$Term)

    $term = $Term
    if ([string]::IsNullOrWhiteSpace($term)) {
        $term = Read-Host "Enter search keyword"
    }
    if ([string]::IsNullOrWhiteSpace($term)) { return }
    $term = $term.Trim()

    Write-Log "Searching Winget for '$term'..." "INFO"
    $raw = winget search $term
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Winget search failed (Exit Code: $LASTEXITCODE)." "ERROR"
        return
    }

    $results = @()
    foreach ($line in $raw) {
        if ($line -match '^\S') {
            $parts = $line -split '\s{2,}'
            if ($parts.Count -ge 3 -and $parts[2] -notmatch '^-+$') {
                $name = $parts[0]
                $id = $parts[1]
                $version = $parts[2]
                $results += [PSCustomObject]@{ Name = $name; Id = $id; Version = $version; Display = (Format-PackageRow -Name $name -Version $version -Source "winget") }
            }
        }
    }

    if ($results.Count -eq 0) {
        Write-Log "No results found for '$term'." "WARN"
        return
    }

    $sortModes = @("Name (A-Z)")
    $script:CurrentSortedWingetSearch = @()
    $applySort = {
        param($sortIndex)
        $script:CurrentSortedWingetSearch = $results | Sort-Object Id
        return $script:CurrentSortedWingetSearch | ForEach-Object { $_.Display }
    }

    $displayItems = & $applySort 0
    $selected = Get-MenuSelection -Items $displayItems -Title "--- Winget Search Results ---" -EnablePaging -PageSize 10 -SortModes $sortModes -SortIndex 0 -SortHandler $applySort -HeaderRow (Format-PackageRow -Name "Name" -Version "Version" -Source "Source")
    if (-not $selected) { return }
    $selectedId = ($script:CurrentSortedWingetSearch | Where-Object { $_.Display -eq $selected }).Id
    if (-not $selectedId) { return }

    $action = Get-MenuSelection -Items @("Info", "Install", "Remove", "Back") -Title "--- Winget Action ---"
    switch ($action) {
        "Info" { Invoke-WingetInfo -Id $selectedId; Pause }
        "Install" { Invoke-WingetInstall -Id $selectedId; Pause }
        "Remove" { Invoke-WingetRemove -Id $selectedId; Pause }
        Default { }
    }
}

function Invoke-WingetInteractive {
    do {
        Clear-Host
        Write-Host "============================" -ForegroundColor Cyan
        Write-Host "       Winget Tools         " -ForegroundColor Yellow
        Write-Host "============================" -ForegroundColor Cyan

        $action = Get-MenuSelection -Items @(
            "List Installed",
            "Search",
            "Info (by ID)",
            "Install (by ID)",
            "Remove (by ID)",
            "Back"
        ) -Title "Use arrows to select an action" -CommandToken "__COMMAND__"

        if ($action -eq "__COMMAND__") {
            $cmd = Invoke-CommandPalette
            switch ($cmd) {
                "help" { Show-CommandHelp; Pause }
                "quit" { return }
                "list" { Invoke-WingetList; Pause }
                "search" { Invoke-WingetSearchInteractive -Term $null; Pause }
                "logs" { Show-AuditLog; Pause }
                Default {
                    if ($cmd) { Write-Host "Unknown command: $cmd" -ForegroundColor Yellow; Pause }
                }
            }
            continue
        }

        switch ($action) {
            "List Installed" {
                Write-Host "Note: Source = Winget" -ForegroundColor DarkGray
                Invoke-WingetList; Pause
            }
            "Search" { Invoke-WingetSearchInteractive -Term $null; Pause }
            "Info (by ID)" {
                $id = Read-Host "Enter Winget ID"
                if ($id) {
                    Write-Host "Note: Source = Winget" -ForegroundColor DarkGray
                    Invoke-WingetInfo -Id $id; Pause
                }
            }
            "Install (by ID)" {
                $id = Read-Host "Enter Winget ID"
                if ($id) { Invoke-WingetInstall -Id $id; Pause }
            }
            "Remove (by ID)" {
                $id = Read-Host "Enter Winget ID"
                if ($id) { Invoke-WingetRemove -Id $id; Pause }
            }
            "Back" { return }
            Default { return }
        }
    } until ($false)
}

switch ($Action) {
    "List" { Invoke-WingetList }
    "ListOnly" { Invoke-WingetList }
    "Install" { if (-not $PackageId) { Write-Log "Package ID required for Winget Install." "ERROR"; return }; Invoke-WingetInstall -Id $PackageId }
    "Search" { Invoke-WingetSearchInteractive -Term $Query }
    "Info" { if (-not $PackageId) { Write-Log "Package ID required for Winget Info." "ERROR"; return }; Invoke-WingetInfo -Id $PackageId }
    "Remove" { if (-not $PackageId) { Write-Log "Package ID required for Winget Remove." "ERROR"; return }; Invoke-WingetRemove -Id $PackageId }
    Default { Invoke-WingetInteractive }
}
