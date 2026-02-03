# Wrapper script for Choco-Manager tools
# Enhanced Version with Logging, Sync, and Multi-tool support

# Core functions are loaded by scripts/choco-manager.ps1

function Show-Header {
    Clear-Host
    Write-Host "============================" -ForegroundColor Cyan
    $appVersion = Get-AppVersion
    Write-Host "   Choco-Manager Pro        " -ForegroundColor Yellow
    if (Test-IsAdmin) {
        Write-Host "   ADMIN MODE               " -ForegroundColor Green
    }
    Write-Host "   Version $appVersion      " -ForegroundColor Gray
    Write-Host "============================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Footer {
    $chocoInfo = Get-ChocoVersionInfo
    $chocoVer = if ($chocoInfo.IsInstalled) { $chocoInfo.InstalledVersion } else { $null }
    $chocoLatest = $chocoInfo.LatestVersion
    $wingetVer = winget --version 2>$null
    Write-Host "----------------------------" -ForegroundColor Gray
    if ($chocoVer) {
        if ($chocoLatest -and $chocoLatest -ne $chocoVer) {
            Write-Host "Choco: v$chocoVer (latest v$chocoLatest)" -NoNewline -ForegroundColor Yellow
        } else {
            Write-Host "Choco: v$chocoVer" -NoNewline -ForegroundColor Green
        }
    } else {
        Write-Host "Choco: NOT FOUND" -NoNewline -ForegroundColor Red
    }
    Write-Host " | " -NoNewline
    if ($wingetVer) { Write-Host "Winget: $wingetVer" -ForegroundColor Green } else { Write-Host "Winget: NOT FOUND" -ForegroundColor Red }
    Write-Host "Admin: " -NoNewline; if (Test-IsAdmin) { Write-Host "YES" -ForegroundColor Green } else { Write-Host "NO" -ForegroundColor Yellow }
    Write-Host "----------------------------" -ForegroundColor Gray
}

function Show-PackageList {
    Write-Host "`nFetching local packages..." -ForegroundColor Gray
    $items = @()

    $chocoRaw = choco list -lo -r
    foreach ($line in $chocoRaw) {
        if ($line -match '\|') {
            $parts = $line -split '\|'
            $name = $parts[0]
            $version = $parts[1]
            if ($name) {
                $items += [PSCustomObject]@{
                    Source = "choco"
                    Id = $name
                    Name = $name
                    Version = $version
                    Display = (Format-PackageRow -Name $name -Version $version -Source "choco")
                }
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
                            $items += [PSCustomObject]@{
                                Source = "winget"
                                Id = $id
                                Name = $name
                                Version = $version
                                Display = (Format-PackageRow -Name $name -Version $version -Source $source)
                            }
                        }
                    }
                }
            }
        } else {
            Write-Log "Winget list failed (Exit Code: $LASTEXITCODE)." "WARN"
        }
    }

    if ($items.Count -eq 0) {
        Write-Log "No local packages found." "WARN"
        return
    }

    $sortModes = @("Name (A-Z)", "Source then Name")
    $script:CurrentSortedItems = @()
    $applySort = {
        param($sortIndex)
        switch ($sortIndex) {
            1 { $script:CurrentSortedItems = $items | Sort-Object Source, Name, Id }
            Default { $script:CurrentSortedItems = $items | Sort-Object Name, Id }
        }
        return $script:CurrentSortedItems | ForEach-Object { $_.Display }
    }

    $displayItems = & $applySort 0
    $selected = Get-MenuSelection -Items $displayItems -Title "--- Package Inventory (Choco + Winget) ---" -EnablePaging -PageSize 10 -SortModes $sortModes -SortIndex 0 -SortHandler $applySort -HeaderRow (Format-PackageRow -Name "Name" -Version "Version" -Source "Source")
    if ($selected) {
        $item = $script:CurrentSortedItems | Where-Object { $_.Display -eq $selected } | Select-Object -First 1
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

# Main Loop
do {
    Show-Header
    $menuItems = @(
        "--- Inventory ---",
        "List/View Packages (Combined)",
        "List Local Packages (Choco)",
        "List Local Packages (Winget)",
        "",
        "--- Package Lists ---",
        "Export/Update List from Local",
        "Install Missing Packages",
        "Synchronize (Full Match)",
        "",
        "--- Updates ---",
        "Interactive Update (Selectable)",
        "Update All Packages (Silent)",
        "",
        "--- Search and Info ---",
        "Search Chocolatey Repository",
        "Search Winget Repository",
        "Package Info (by name)",
        "",
        "--- Tools ---",
        "Package Utilities",
        "Winget Tools",
        "",
        "--- Logs and Help ---",
        "View Audit Log"
    )
    if (-not (Test-IsAdmin)) {
        $menuItems += "Elevate to Admin"
    }
    if (-not (Get-ChocoVersionInfo).IsInstalled) {
        $menuItems += "Install Chocolatey"
    }
    $menuItems += "Quit"

    Show-Footer

    $choice = Get-MenuSelection -Items $menuItems -Title "Main Menu (Use arrows, j/k, Enter, /)" -CommandToken "__COMMAND__"
    if ([string]::IsNullOrWhiteSpace($choice) -or $choice -match '^---') {
        continue
    }

    if ($choice -eq "__COMMAND__") {
        $cmd = Invoke-CommandPalette
        switch ($cmd) {
            "help" { Show-CommandHelp; Pause }
            "quit" { return }
            "list" { Show-PackageList; Pause }
            "search" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\src\Choco\choco-package-explorer.ps1") }
            "logs" { Show-AuditLog; Pause }
            Default {
                if ($cmd) { Write-Host "Unknown command: $cmd" -ForegroundColor Yellow; Pause }
            }
        }
        continue
    }

    switch ($choice) {
        "List/View Packages (Combined)" { Show-PackageList; Pause }
        "List Local Packages (Choco)" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\src\Choco\choco-package-explorer.ps1") -Action ListChoco; Pause }
        "List Local Packages (Winget)" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\src\Winget\winget-utils.ps1") -Action ListOnly; Pause }
        "Export/Update List from Local" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\src\Choco\list-choco-apps.ps1"); Pause }
        "Install Missing Packages" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\src\Choco\choco-pack-install.ps1"); Pause }
        "Synchronize (Full Match)" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\src\Choco\choco-sync.ps1") -Action Sync; Pause }
        "Interactive Update (Selectable)" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\src\Choco\choco-upgrade-interactive.ps1"); Pause }
        "Update All Packages (Silent)" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\src\Choco\choco-utils.ps1") -Action Update; Pause }
        "Search Chocolatey Repository" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\src\Choco\choco-package-explorer.ps1") }
        "Search Winget Repository" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\src\Winget\winget-utils.ps1") -Action Search }
        "Package Info (by name)" {
            $pkg = Read-Host "Enter package name"
            $safePkg = Get-ValidatedPackageId -Id $pkg -Context "Chocolatey"
            if ($safePkg) { choco info $safePkg; Pause }
        }
        "Package Utilities" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\src\Choco\choco-package-explorer.ps1") }
        "Winget Tools" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\src\Winget\winget-utils.ps1") -Action Interactive }
        "View Audit Log" { Show-AuditLog; Pause }
        "Elevate to Admin" {
            Invoke-ElevatedAction -FilePath (Join-Path $PSScriptRoot "choco-manager.ps1")
            return
        }
        "Install Chocolatey" {
            Install-Chocolatey
            Pause
        }
        "Quit" { return }
        Default { }
    }
} until ($false)
