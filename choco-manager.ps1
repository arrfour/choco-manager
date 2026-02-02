# Wrapper script for Choco-Manager tools
# Enhanced Version with Logging, Sync, and Multi-tool support

# Load core functions with process-scope policy + unblock
$corePath = Join-Path $PSScriptRoot "core-functions.ps1"
if (-not (Test-Path $corePath)) {
    Write-Error "Core functions not found at $corePath"
    exit 1
}

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Unblock-File -Path $corePath -ErrorAction SilentlyContinue
    . $corePath
} catch {
    Write-Error "Failed to load core functions: $($_.Exception.Message)"
    exit 1
}

# Verify critical function loaded
if (-not (Get-Command Test-IsAdmin -CommandType Function -ErrorAction SilentlyContinue)) {
    Write-Error "Test-IsAdmin not loaded from $corePath"
    exit 1
}

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
    $chocoVer = choco --version 2>$null
    $wingetVer = winget --version 2>$null
    Write-Host "----------------------------" -ForegroundColor Gray
    if ($chocoVer) { Write-Host "Choco: v$chocoVer" -NoNewline -ForegroundColor Green } else { Write-Host "Choco: NOT FOUND" -NoNewline -ForegroundColor Red }
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
        "Package Utilities (Search/Info/Remove)",
        "List/View Packages",
        "Export/Update List from Local",
        "Install Missing Packages",
        "Interactive Update (Selectable)",
        "Update All Packages (Silent)",
        "Synchronize (Full Match)",
        "Winget Tools",
        "View Audit Log"
    )
    if (-not (Test-IsAdmin)) {
        $menuItems += "Elevate to Admin"
    }
    $menuItems += "Quit"

    Show-Footer

    $choice = Get-MenuSelection -Items $menuItems -Title "Main Menu (Use arrows, j/k, Enter, /)" -CommandToken "__COMMAND__"

    if ($choice -eq "__COMMAND__") {
        $cmd = Invoke-CommandPalette
        switch ($cmd) {
            "help" { Show-CommandHelp; Pause }
            "quit" { return }
            "list" { Show-PackageList; Pause }
            "search" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "choco-package-explorer.ps1") }
            "logs" { Show-AuditLog; Pause }
            Default {
                if ($cmd) { Write-Host "Unknown command: $cmd" -ForegroundColor Yellow; Pause }
            }
        }
        continue
    }

    switch ($choice) {
        "Package Utilities (Search/Info/Remove)" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "choco-package-explorer.ps1") }
        "List/View Packages" { Show-PackageList; Pause }
        "Export/Update List from Local" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "list-choco-apps.ps1"); Pause }
        "Install Missing Packages" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "choco-pack-install.ps1"); Pause }
        "Interactive Update (Selectable)" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "choco-upgrade-interactive.ps1"); Pause }
        "Update All Packages (Silent)" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "choco-utils.ps1") -Action Update; Pause }
        "Synchronize (Full Match)" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "choco-sync.ps1") -Action Sync; Pause }
        "Winget Tools" { powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "winget-utils.ps1") -Action Interactive }
        "View Audit Log" { Show-AuditLog; Pause }
        "Elevate to Admin" {
            Invoke-ElevatedAction -FilePath $MyInvocation.MyCommand.Path
            return
        }
        "Quit" { return }
        Default { }
    }
} until ($false)
