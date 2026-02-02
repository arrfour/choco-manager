# choco-package-explorer.ps1
# Interactive package utilities: List, Search, and Info

# 1. Load core functions
$corePath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "src\Core\core-functions.ps1"
if (Test-Path $corePath) { . $corePath }

function Show-ChocoLocalPackages {
    Write-Host "`nFetching local Chocolatey packages..." -ForegroundColor Gray
    $raw = choco list -lo -r
    $packages = @()
    foreach ($line in $raw) {
        if ($line -match '\|') {
            $parts = $line -split '\|'
            $name = $parts[0]
            $version = $parts[1]
            $packages += [PSCustomObject]@{ Id = $name; Name = $name; Version = $version; Display = (Format-PackageRow -Name $name -Version $version -Source "choco") }
        }
    }

    if ($packages.Count -eq 0) {
        Write-Host "No local Chocolatey packages found." -ForegroundColor Yellow
        Pause
        return
    }

    $sortModes = @("Name (A-Z)")
    $script:CurrentSortedPackages = @()
    $applySort = {
        param($sortIndex)
        $script:CurrentSortedPackages = $packages | Sort-Object Id
        return $script:CurrentSortedPackages | ForEach-Object { $_.Display }
    }

    $displayItems = & $applySort 0
    $selected = Get-MenuSelection -Items $displayItems -Title "--- Local Chocolatey Packages ---" -EnablePaging -PageSize 10 -SortModes $sortModes -SortIndex 0 -SortHandler $applySort -HeaderRow (Format-PackageRow -Name "Name" -Version "Version" -Source "Source")
    if ($selected) {
        $pkgId = ($script:CurrentSortedPackages | Where-Object { $_.Display -eq $selected }).Id
        $safeId = Get-ValidatedPackageId -Id $pkgId -Context "Chocolatey"
        if ($safeId) {
            Write-Host "`n--- Info for $safeId ---" -ForegroundColor Yellow
            choco info $safeId
            Pause
        }
    }
}

function Show-WingetLocalPackages {
    Write-Host "`nFetching local Winget packages..." -ForegroundColor Gray
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-Host "Winget not found on this system." -ForegroundColor Yellow
        Pause
        return
    }

    $raw = winget list
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Winget list failed (Exit Code: $LASTEXITCODE)." -ForegroundColor Yellow
        Pause
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
        Write-Host "No local Winget packages found." -ForegroundColor Yellow
        Pause
        return
    }

    $sortModes = @("Name (A-Z)")
    $script:CurrentSortedWingetPackages = @()
    $applySort = {
        param($sortIndex)
        $script:CurrentSortedWingetPackages = $packages | Sort-Object Id
        return $script:CurrentSortedWingetPackages | ForEach-Object { $_.Display }
    }

    $displayItems = & $applySort 0
    $selected = Get-MenuSelection -Items $displayItems -Title "--- Local Winget Packages ---" -EnablePaging -PageSize 10 -SortModes $sortModes -SortIndex 0 -SortHandler $applySort -HeaderRow (Format-PackageRow -Name "Name" -Version "Version" -Source "Source")
    if ($selected) {
        $pkgId = ($script:CurrentSortedWingetPackages | Where-Object { $_.Display -eq $selected }).Id
        $safeId = Get-ValidatedPackageId -Id $pkgId -Context "Winget"
        if ($safeId) {
            Write-Host "`n--- Info for $safeId ---" -ForegroundColor Yellow
            winget show --id $safeId
            Pause
        }
    }
}

function Show-CombinedLocalPackages {
    Write-Host "`nFetching local packages (Choco + Winget)..." -ForegroundColor Gray
    $items = @()

    $chocoRaw = choco list -lo -r
    foreach ($line in $chocoRaw) {
        if ($line -match '\|') {
            $parts = $line -split '\|'
            $name = $parts[0]
            $version = $parts[1]
            if ($name) {
                $items += [PSCustomObject]@{ Source = "choco"; Id = $name; Name = $name; Version = $version; Display = (Format-PackageRow -Name $name -Version $version -Source "choco") }
            }
        }
    }

    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        $wingetRaw = winget list
        if ($LASTEXITCODE -eq 0) {
            foreach ($line in $wingetRaw) {
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
                            $items += [PSCustomObject]@{ Source = "winget"; Id = $id; Name = $name; Version = $version; Display = (Format-PackageRow -Name $name -Version $version -Source $source) }
                        }
                    }
                }
            }
        }
    }

    if ($items.Count -eq 0) {
        Write-Host "No local packages found." -ForegroundColor Yellow
        Pause
        return
    }

    $sortModes = @("Name (A-Z)", "Source then Name")
    $script:CurrentSortedCombined = @()
    $applySort = {
        param($sortIndex)
        switch ($sortIndex) {
            1 { $script:CurrentSortedCombined = $items | Sort-Object Source, Name, Id }
            Default { $script:CurrentSortedCombined = $items | Sort-Object Name, Id }
        }
        return $script:CurrentSortedCombined | ForEach-Object { $_.Display }
    }

    $displayItems = & $applySort 0
    $selected = Get-MenuSelection -Items $displayItems -Title "--- Local Package Inventory ---" -EnablePaging -PageSize 10 -SortModes $sortModes -SortIndex 0 -SortHandler $applySort -HeaderRow (Format-PackageRow -Name "Name" -Version "Version" -Source "Source")
    if ($selected) {
        $item = $script:CurrentSortedCombined | Where-Object { $_.Display -eq $selected } | Select-Object -First 1
        if ($item) {
            if ($item.Source -eq "winget") {
                $safeId = Get-ValidatedPackageId -Id $item.Id -Context "Winget"
                if ($safeId) {
                    Write-Host "`n--- Winget Info for $safeId ---" -ForegroundColor Yellow
                    winget show --id $safeId
                    Pause
                }
            } else {
                $safeId = Get-ValidatedPackageId -Id $item.Id -Context "Chocolatey"
                if ($safeId) {
                    Write-Host "`n--- Chocolatey Info for $safeId ---" -ForegroundColor Yellow
                    choco info $safeId
                    Pause
                }
            }
        }
    }
}

function Search-Packages {
    param([string]$Repo = "Chocolatey")
    
        $keyword = Read-Host "Enter search keyword"
        if ([string]::IsNullOrWhiteSpace($keyword)) { return }
        $keyword = $keyword.Trim()
    
    Write-Log "Searching $Repo for '$keyword'..." "INFO"
    
    $results = @()
    if ($Repo -eq "Chocolatey") {
        $raw = choco search $keyword -r
        foreach ($line in $raw) {
            if ($line -match '\|') {
                $parts = $line -split '\|'
                $name = $parts[0]
                $version = $parts[1]
                $results += [PSCustomObject]@{ Id = $name; Name = $name; Version = $version; Display = (Format-PackageRow -Name $name -Version $version -Source "choco") }
            }
        }
    } else {
        # Winget Search
        $raw = winget search $keyword
        winget search $keyword
        $id = Read-Host "`nEnter Package ID for more info (or press Enter to skip)"
        if ($id) { winget show $id; Pause }
        return
    }
    
    if ($results.Count -eq 0) {
        Write-Log "No results found for '$keyword'." "WARN"
        Pause
        return
    }
    
    $sortModes = @("Name (A-Z)")
    $script:CurrentSortedSearch = @()
    $applySort = {
        param($sortIndex)
        $script:CurrentSortedSearch = $results | Sort-Object Id
        return $script:CurrentSortedSearch | ForEach-Object { $_.Display }
    }

    $displayItems = & $applySort 0
    $selected = Get-MenuSelection -Items $displayItems -Title "--- Search Results ($Repo) ---" -EnablePaging -PageSize 10 -SortModes $sortModes -SortIndex 0 -SortHandler $applySort -HeaderRow (Format-PackageRow -Name "Name" -Version "Version" -Source "Source")
    if ($selected) {
        $pkgId = ($script:CurrentSortedSearch | Where-Object { $_.Display -eq $selected }).Id
        $safePkgId = Get-ValidatedPackageId -Id $pkgId -Context "Chocolatey"
        if (-not $safePkgId) { Pause; return }
        Write-Host "`n--- Info for $pkgId ---" -ForegroundColor Yellow
        choco info $safePkgId
        
        $ins = Read-Host "`nWould you like to install $pkgId? (y/n)"
        if ($ins -eq 'y') {
            if (-not (Test-IsAdmin)) {
                Invoke-ElevatedProcess -FilePath "choco" -ArgumentList @("install", $safePkgId, "-y")
            } else {
                choco install $safePkgId -y
            }
        }
        Pause
    }
}

# Sub-menu Loop
do {
    Clear-Host
    Write-Host "============================" -ForegroundColor Cyan
    Write-Host "    Package Utilities       " -ForegroundColor Yellow
    Write-Host "============================" -ForegroundColor Cyan
    
    $menuItems = @(
        "Search Chocolatey Repository",
        "Search Winget Repository",
        "Package Info (by name)",
        "List Local Packages (Combined)",
        "List Local Packages (Choco)",
        "List Local Packages (Winget)",
        "Uninstall Package",
        "Back to Main Menu"
    )

    $choice = Get-MenuSelection -Items $menuItems -Title "Package Utilities (Use arrows, j/k, Enter, /)" -CommandToken "__COMMAND__"

    if ($choice -eq "__COMMAND__") {
        $cmd = Invoke-CommandPalette
        switch ($cmd) {
            "help" { Show-CommandHelp; Pause }
            "quit" { return }
            "list" { Show-CombinedLocalPackages }
            "search" { return }
            "logs" { Show-AuditLog; Pause }
            Default {
                if ($cmd) { Write-Host "Unknown command: $cmd" -ForegroundColor Yellow; Pause }
            }
        }
        continue
    }

    switch ($choice) {
        "Search Chocolatey Repository" { Search-Packages -Repo "Chocolatey" }
        "Search Winget Repository" { Search-Packages -Repo "Winget" }
        "Package Info (by name)" {
            $pkg = Read-Host "Enter package name"
            $safePkg = Get-ValidatedPackageId -Id $pkg -Context "Chocolatey"
            if ($safePkg) { choco info $safePkg; Pause }
        }
        "List Local Packages (Combined)" { Show-CombinedLocalPackages }
        "List Local Packages (Choco)" { Show-ChocoLocalPackages }
        "List Local Packages (Winget)" { Show-WingetLocalPackages }
        "Uninstall Package" {
            $pkg = Read-Host "Enter package name to uninstall"
            $safePkg = Get-ValidatedPackageId -Id $pkg -Context "Chocolatey"
            if ($safePkg) {
                $confirm = Read-Host "Are you sure you want to uninstall $safePkg? (y/n)"
                if ($confirm -eq 'y') {
                    if (-not (Test-IsAdmin)) {
                        Invoke-ElevatedProcess -FilePath "choco" -ArgumentList @("uninstall", $safePkg, "-y")
                    } else {
                        choco uninstall $safePkg -y
                    }
                }
            }
            Pause
        }
        "Back to Main Menu" { return }
        Default { }
    }
} until ($false)
