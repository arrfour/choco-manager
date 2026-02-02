# Core functions for Choco-Manager
# Includes Logging, Elevation, and Shared Utilities

function Get-ProjectRoot {
    $root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
    return $root.Path
}

$LogPath = Join-Path (Get-ProjectRoot) "logs\choco-manager.log"

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Console Output with Colors
    $color = switch ($Level) {
        "INFO"    { "Gray" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
        Default   { "White" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
    
    # File Output
    try {
        $logDir = Split-Path -Parent $LogPath
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logEntry | Out-File -FilePath $LogPath -Append -Encoding UTF8
    }
    catch {
        Write-Warning "Failed to write to log file: $($_.Exception.Message)"
    }
}

function Invoke-CommandPalette {
    param(
        [string]$Prompt = "Command"
    )

    $cmd = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }
    return $cmd.Trim().ToLowerInvariant()
}

function Show-CommandHelp {
    Write-Host "Commands:" -ForegroundColor Cyan
    Write-Host "help"
    Write-Host "quit"
    Write-Host "list"
    Write-Host "search"
    Write-Host "logs"
}

function Show-AuditLog {
    $logPath = Join-Path (Get-ProjectRoot) "logs\choco-manager.log"
    if (Test-Path $logPath) {
        Get-Content $logPath -Tail 20
    } else {
        Write-Host "No log file found." -ForegroundColor Yellow
    }
}

function Get-ChocoVersionInfo {
    $info = [PSCustomObject]@{
        IsInstalled = $false
        InstalledVersion = $null
        LatestVersion = $null
    }

    $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
    if (-not $chocoCmd) { return $info }

    $info.IsInstalled = $true
    try { $info.InstalledVersion = (choco --version 2>$null).Trim() } catch { }
    try {
        $raw = choco list chocolatey --exact -r 2>$null
        foreach ($line in $raw) {
            if ($line -match '\|') {
                $parts = $line -split '\|'
                if ($parts[0] -eq 'chocolatey') {
                    $info.LatestVersion = $parts[1]
                    break
                }
            }
        }
    } catch { }

    return $info
}

function Install-Chocolatey {
    Write-Host "This will install Chocolatey from community.chocolatey.org." -ForegroundColor Yellow
    $confirm = Read-Host "Proceed? (y/n)"
    if ($confirm -ne 'y') { return }

    $command = "& {" +
        " Set-ExecutionPolicy Bypass -Scope Process -Force;" +
        " [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072;" +
        " iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))" +
        " }"

    Invoke-ElevatedProcess -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command)
}

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-AppVersion {
    param(
        [string]$Path = (Join-Path (Get-ProjectRoot) "VERSION")
    )

    if (Test-Path $Path) {
        $ver = Get-Content $Path -TotalCount 1
        return $ver.Trim()
    }

    return "unknown"
}

function Invoke-ElevatedAction {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    
    $args = @("-ExecutionPolicy", "Bypass", "-File", $FilePath) + $ArgumentList

    if (Test-IsAdmin) {
        Write-Log "Running as Administrator: $FilePath $($ArgumentList -join ' ')" "INFO"
        Start-Process -FilePath "powershell.exe" -ArgumentList $args -Wait -NoNewWindow
    }
    else {
        Write-Log "Requesting Elevation for: $FilePath" "WARN"
        try {
            Start-Process -FilePath "powershell.exe" -ArgumentList $args -Verb RunAs -Wait
            Write-Log "Elevated process completed." "SUCCESS"
        }
        catch {
            Write-Log "Elevation failed or was cancelled: $($_.Exception.Message)" "ERROR"
            throw $_
        }
    }
}

function Invoke-ElevatedProcess {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    if (Test-IsAdmin) {
        Write-Log "Running as Administrator: $FilePath $($ArgumentList -join ' ')" "INFO"
        Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -NoNewWindow
    }
    else {
        Write-Log "Requesting Elevation for: $FilePath" "WARN"
        try {
            Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Verb RunAs -Wait
            Write-Log "Elevated process completed." "SUCCESS"
        }
        catch {
            Write-Log "Elevation failed or was cancelled: $($_.Exception.Message)" "ERROR"
            throw $_
        }
    }
}

function Get-PackageList {
    param(
        [string]$Path = (Join-Path (Get-ProjectRoot) "data\choco_packages.txt")
    )
    
    if (-not (Test-Path $Path)) {
        Write-Log "Package list not found at $Path" "ERROR"
        return @()
    }
    
    $packages = Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not [string]::IsNullOrWhiteSpace($line) -and -not $line.StartsWith("#")) {
            # Extract package name (first token before space or pipe)
            $packageName = $line -split '[\s|]+' | Select-Object -First 1
            if ($packageName) { $packageName }
        }
    }
    
    return $packages | Select-Object -Unique
}

function Test-SafePackageId {
    param(
        [string]$Id
    )

    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    return $Id -match '^[A-Za-z0-9][A-Za-z0-9\.\-_+]*$'
}

function Get-ValidatedPackageId {
    param(
        [string]$Id,
        [string]$Context = "package"
    )

    if (Test-SafePackageId -Id $Id) { return $Id }
    Write-Log "Rejected invalid $Context id: '$Id'" "WARN"
    return $null
}

function Format-PackageRow {
    param(
        [string]$Name,
        [string]$Version,
        [string]$Source,
        [int]$NameWidth = 36,
        [int]$VersionWidth = 12,
        [int]$SourceWidth = 10
    )

    $nameText = if ($Name) { $Name } else { "" }
    if ($nameText.Length -gt $NameWidth) { $nameText = $nameText.Substring(0, $NameWidth) }
    $versionText = if ($Version) { $Version } else { "" }
    if ($versionText.Length -gt $VersionWidth) { $versionText = $versionText.Substring(0, $VersionWidth) }
    $sourceText = if ($Source) { $Source } else { "" }
    if ($sourceText.Length -gt $SourceWidth) { $sourceText = $sourceText.Substring(0, $SourceWidth) }

    return "$($nameText.PadRight($NameWidth)) $($versionText.PadRight($VersionWidth)) $($sourceText.PadRight($SourceWidth))"
}

function Get-DefaultSortMode {
    return "Name"
}

function Get-MenuSelection {
    param(
        [Parameter(Mandatory=$true)]
        [Array]$Items,
        [string]$Title = "Use arrow keys to select and press Enter:",
        [switch]$EnablePaging,
        [switch]$EnableMultiColumn,
        [int]$PageSize = 0,
        [int]$Columns = 0,
        [int]$ColumnPadding = 2,
        [string[]]$SortModes = @(),
        [int]$SortIndex = 0,
        [scriptblock]$SortHandler = $null,
        [string]$HeaderRow = "",
        [string]$CommandToken = "__COMMAND__"
    )

    if ($Items.Count -eq 0) { return $null }

    if ($EnableMultiColumn -and -not $EnablePaging) {
        $EnablePaging = $true
    }

    $selectedIndex = 0
    $startPosition = $Host.UI.RawUI.CursorPosition
    $running = $true
    $needsRender = $true
    $lastWindowSize = $Host.UI.RawUI.WindowSize
    $effectivePageSize = $Items.Count
    $currentSortIndex = if ($SortIndex -ge 0 -and $SortIndex -lt $SortModes.Count) { $SortIndex } else { 0 }
    $lastRenderLines = 0

    try { $Host.UI.RawUI.CursorSize = 0 } catch {}

    while ($running) {
        $windowSize = $Host.UI.RawUI.WindowSize
        if ($windowSize.Width -ne $lastWindowSize.Width -or $windowSize.Height -ne $lastWindowSize.Height) {
            $needsRender = $true
            $lastWindowSize = $windowSize
        }

        if ($needsRender) {
            $Host.UI.RawUI.CursorPosition = $startPosition

            $headerLines = if ($SortModes.Count -gt 1) { 3 } else { 2 }
            if ($HeaderRow) { $headerLines += 1 }
            $footerLines = 2
            $lineWidth = [Math]::Max(1, $windowSize.Width - 1)
            $availableRows = [Math]::Max(1, $windowSize.Height - ($headerLines + $footerLines))

            $effectivePageSize = $Items.Count
            $columnCount = 1
            $columnWidth = 0

            if ($EnableMultiColumn) {
                $maxItemLength = 0
                foreach ($item in $Items) {
                    $len = [string]$item
                    if ($len.Length -gt $maxItemLength) { $maxItemLength = $len.Length }
                }
                $columnWidth = $maxItemLength + 3 + $ColumnPadding
                if ($columnWidth -lt 10) { $columnWidth = 10 }
                if ($columnWidth -gt $lineWidth) { $columnWidth = $lineWidth }
                $maxColumns = [Math]::Max(1, [Math]::Floor($windowSize.Width / $columnWidth))
                $columnCount = if ($Columns -gt 0) { [Math]::Min($Columns, $maxColumns) } else { $maxColumns }
                if ($columnCount -lt 1) { $columnCount = 1 }
            }

            if ($EnablePaging) {
                if ($EnableMultiColumn) {
                    $effectivePageSize = $availableRows * $columnCount
                } elseif ($PageSize -gt 0) {
                    $effectivePageSize = $PageSize
                } else {
                    $effectivePageSize = $availableRows
                }

                if ($effectivePageSize -lt 1) { $effectivePageSize = 1 }
            }

            $pageStart = if ($EnablePaging) { [Math]::Floor($selectedIndex / $effectivePageSize) * $effectivePageSize } else { 0 }
            $pageEnd = [Math]::Min($Items.Count, $pageStart + $effectivePageSize) - 1
            $pageItems = if ($pageEnd -ge $pageStart) { $Items[$pageStart..$pageEnd] } else { @() }

            Write-Host "$Title" -ForegroundColor Cyan
            if ($SortModes.Count -gt 1) {
                $sortLabel = $SortModes[$currentSortIndex]
                Write-Host "Sort: $sortLabel (S to change)" -ForegroundColor DarkGray
            }
            if ($HeaderRow) {
                $headerText = $HeaderRow
                if ($headerText.Length -gt $lineWidth) { $headerText = $headerText.Substring(0, $lineWidth) }
                Write-Host $headerText -ForegroundColor Gray
            }
            Write-Host ""

            $renderedRows = 0
            if ($EnableMultiColumn -and $columnCount -gt 1) {
                $rows = [Math]::Ceiling($pageItems.Count / $columnCount)
                $renderedRows = $rows
                for ($r = 0; $r -lt $rows; $r++) {
                    for ($c = 0; $c -lt $columnCount; $c++) {
                        $index = ($r * $columnCount) + $c
                        if ($index -lt $pageItems.Count) {
                            $itemIndex = $pageStart + $index
                            $prefix = if ($itemIndex -eq $selectedIndex) { " > " } else { "   " }
                            $text = "$prefix$($Items[$itemIndex])"
                            if ($text.Length -gt $columnWidth) { $text = $text.Substring(0, $columnWidth) }
                            $cell = $text.PadRight($columnWidth)
                            if ($itemIndex -eq $selectedIndex) {
                                Write-Host $cell -NoNewline -BackgroundColor White -ForegroundColor Black
                            } else {
                                Write-Host $cell -NoNewline
                            }
                        } else {
                            Write-Host ("".PadRight($columnWidth)) -NoNewline
                        }
                    }
                    Write-Host ""
                }
            } else {
                $renderedRows = $pageItems.Count
                for ($i = 0; $i -lt $pageItems.Count; $i++) {
                    $itemIndex = $pageStart + $i
                    if ($itemIndex -eq $selectedIndex) {
                        $prefix = " > "
                        $available = [Math]::Max(1, $lineWidth - $prefix.Length)
                        $itemText = "$($Items[$itemIndex])"
                        if ($itemText.Length -gt $available) { $itemText = $itemText.Substring(0, $available) }
                        $lineText = "$prefix$itemText"
                        $padCount = $lineWidth - $lineText.Length
                        if ($padCount -lt 0) { $padCount = 0 }
                        Write-Host $prefix -NoNewline -ForegroundColor Yellow
                        Write-Host $itemText -NoNewline -BackgroundColor White -ForegroundColor Black
                        if ($padCount -gt 0) {
                            Write-Host ("".PadRight($padCount)) -BackgroundColor White -ForegroundColor Black
                        } else {
                            Write-Host ""
                        }
                    } else {
                        $prefix = "   "
                        $available = [Math]::Max(1, $lineWidth - $prefix.Length)
                        $itemText = "$($Items[$itemIndex])"
                        if ($itemText.Length -gt $available) { $itemText = $itemText.Substring(0, $available) }
                        $lineText = "$prefix$itemText"
                        if ($lineText.Length -lt $lineWidth) {
                            $lineText = $lineText.PadRight($lineWidth)
                        }
                        Write-Host $lineText
                    }
                }
            }

            $footer = "(Arrows: Navigate | Enter: Select | Esc/Q: Quit)"
            if ($SortModes.Count -gt 1) { $footer = "$footer | S: Sort" }
            Write-Host "`n$footer" -ForegroundColor Gray

            $currentRenderLines = $headerLines + $renderedRows + $footerLines
            if ($lastRenderLines -gt $currentRenderLines) {
                $extra = $lastRenderLines - $currentRenderLines
                for ($i = 0; $i -lt $extra; $i++) {
                    Write-Host ("".PadRight($lineWidth))
                }
            }
            $lastRenderLines = $currentRenderLines
            $needsRender = $false
        }

        if ($Host.UI.RawUI.KeyAvailable) {
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            switch ($key.VirtualKeyCode) {
                38 { $selectedIndex = ($selectedIndex - 1 + $Items.Count) % $Items.Count; $needsRender = $true } # Up
                40 { $selectedIndex = ($selectedIndex + 1) % $Items.Count; $needsRender = $true } # Down
                74 { $selectedIndex = ($selectedIndex + 1) % $Items.Count; $needsRender = $true } # J
                75 { $selectedIndex = ($selectedIndex - 1 + $Items.Count) % $Items.Count; $needsRender = $true } # K
                33 {
                    $jump = if ($EnablePaging) { $effectivePageSize } else { 1 }
                    $selectedIndex = [Math]::Max(0, $selectedIndex - $jump)
                    $needsRender = $true
                } # PageUp
                34 {
                    $jump = if ($EnablePaging) { $effectivePageSize } else { 1 }
                    $selectedIndex = [Math]::Min($Items.Count - 1, $selectedIndex + $jump)
                    $needsRender = $true
                } # PageDown
                36 { $selectedIndex = 0; $needsRender = $true } # Home
                35 { $selectedIndex = $Items.Count - 1; $needsRender = $true } # End
                13 { $running = $false; return $Items[$selectedIndex] } # Enter
                27 { $running = $false; return $null } # Esc
                81 { $running = $false; return $null } # Q
                191 { $running = $false; return $CommandToken } # /
                83 {
                    if ($SortModes.Count -gt 1 -and $SortHandler) {
                        $currentSortIndex = ($currentSortIndex + 1) % $SortModes.Count
                        $Items = & $SortHandler $currentSortIndex
                        if (-not $Items) { $Items = @() }
                        if ($Items.Count -eq 0) { return $null }
                        $selectedIndex = 0
                        $needsRender = $true
                    }
                } # S
            }
        } else {
            Start-Sleep -Milliseconds 50
        }
    }
    try { $Host.UI.RawUI.CursorSize = 25 } catch {}
}

# Ensure functions are available when dot-sourced
# (Removed experimental module export logic to prevent loading interference)
