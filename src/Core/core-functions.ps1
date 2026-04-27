# Core functions for Choco-Manager
# Includes Logging, Elevation, and Shared Utilities

function Get-ProjectRoot {
    $root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
    return $root.Path
}

function Get-DataDirectory {
    return (Join-Path (Get-ProjectRoot) "data")
}

function Get-LogDirectory {
    return (Join-Path (Get-ProjectRoot) "logs")
}

function Get-DefaultPackageListPath {
    return (Join-Path (Get-DataDirectory) "choco_packages.txt")
}

function Get-NormalizedPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Path is required."
    }

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
    if (Test-Path $expandedPath) {
        return (Resolve-Path $expandedPath).Path
    }

    return [System.IO.Path]::GetFullPath($expandedPath)
}

function Test-PathUnderDirectory {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$Directory
    )

    $normalizedPath = Get-NormalizedPath -Path $Path
    $normalizedDirectory = (Get-NormalizedPath -Path $Directory).TrimEnd('\')
    $comparison = [System.StringComparison]::OrdinalIgnoreCase

    return $normalizedPath.Equals($normalizedDirectory, $comparison) -or
        $normalizedPath.StartsWith("$normalizedDirectory\", $comparison)
}

function Resolve-ManagedDataFilePath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [string]$Purpose = "package list"
    )

    $resolvedPath = Get-NormalizedPath -Path $Path
    $dataDirectory = Get-DataDirectory
    if (-not (Test-PathUnderDirectory -Path $resolvedPath -Directory $dataDirectory)) {
        throw "$Purpose path must remain under '$dataDirectory'."
    }

    return $resolvedPath
}

$LogPath = Join-Path (Get-ProjectRoot) "logs\choco-manager.log"

function Get-LogFileLevels {
    $configuredLevels = @("WARN", "ERROR")
    if ($env:CHOCO_MANAGER_LOG_FILE_LEVELS) {
        $parsedLevels = $env:CHOCO_MANAGER_LOG_FILE_LEVELS.Split(',') | ForEach-Object {
            $_.Trim().ToUpperInvariant()
        } | Where-Object { $_ }
        if ($parsedLevels.Count -gt 0) {
            $configuredLevels = $parsedLevels
        }
    }

    return $configuredLevels
}

function Test-ShouldPersistLogEntry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Level
    )

    return (Get-LogFileLevels) -contains $Level.ToUpperInvariant()
}

function Get-TrustedPowerShellPath {
    $candidatePaths = @()
    if ($env:WINDIR) {
        if ($env:PROCESSOR_ARCHITEW6432) {
            $candidatePaths += (Join-Path $env:WINDIR "Sysnative\WindowsPowerShell\v1.0\powershell.exe")
        }
        $candidatePaths += (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe")
    }
    $candidatePaths += (Join-Path $PSHOME "powershell.exe")

    foreach ($candidatePath in ($candidatePaths | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path $candidatePath) {
            return (Resolve-Path $candidatePath).Path
        }
    }

    throw "Unable to locate a trusted Windows PowerShell executable."
}

function Resolve-TrustedCommandPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CommandName
    )

    $name = [System.IO.Path]::GetFileNameWithoutExtension($CommandName).ToLowerInvariant()
    switch ($name) {
        "powershell" {
            return (Get-TrustedPowerShellPath)
        }
        "choco" {
            $command = Get-Command choco -CommandType Application -ErrorAction SilentlyContinue
            if (-not $command) {
                throw "Chocolatey executable was not found."
            }

            $commandPath = Get-NormalizedPath -Path $command.Source
            $allowedRoots = @(
                $env:ChocolateyInstall,
                (Join-Path $env:ProgramData "chocolatey"),
                (Join-Path $env:ProgramFiles "Chocolatey")
            ) | Where-Object { $_ } | Select-Object -Unique

            foreach ($allowedRoot in $allowedRoots) {
                if (Test-PathUnderDirectory -Path $commandPath -Directory $allowedRoot) {
                    return $commandPath
                }
            }

            throw "Rejected Chocolatey executable outside trusted directories: $commandPath"
        }
        "winget" {
            $command = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue
            if (-not $command) {
                throw "Winget executable was not found."
            }

            $commandPath = Get-NormalizedPath -Path $command.Source
            $allowedRoots = @(
                (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"),
                (Join-Path $env:ProgramFiles "WindowsApps"),
                (Join-Path $env:SystemRoot "System32")
            ) | Where-Object { $_ } | Select-Object -Unique

            foreach ($allowedRoot in $allowedRoots) {
                if (Test-PathUnderDirectory -Path $commandPath -Directory $allowedRoot) {
                    return $commandPath
                }
            }

            throw "Rejected Winget executable outside trusted directories: $commandPath"
        }
        default {
            if (-not [System.IO.Path]::IsPathRooted($CommandName)) {
                throw "Executable path must be absolute or use a trusted command alias."
            }

            return (Get-NormalizedPath -Path $CommandName)
        }
    }
}

function Resolve-ProjectScriptPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $scriptPath = Get-NormalizedPath -Path $Path
    if (-not (Test-Path $scriptPath)) {
        throw "Script file not found: $scriptPath"
    }

    if ([System.IO.Path]::GetExtension($scriptPath) -ne ".ps1") {
        throw "Only PowerShell script paths are allowed: $scriptPath"
    }

    if (-not (Test-PathUnderDirectory -Path $scriptPath -Directory (Get-ProjectRoot))) {
        throw "Script path must remain under the project root: $scriptPath"
    }

    return $scriptPath
}

function Invoke-ScriptFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $trustedPowerShell = Get-TrustedPowerShellPath
    $resolvedScriptPath = Resolve-ProjectScriptPath -Path $FilePath
    $processArguments = @("-NoProfile", "-File", $resolvedScriptPath) + $ArgumentList

    Write-Log "Launching script: $resolvedScriptPath" "INFO"
    Start-Process -FilePath $trustedPowerShell -ArgumentList $processArguments -Wait -NoNewWindow
}

function Invoke-TrustedExecutable {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CommandName,
        [string[]]$ArgumentList = @()
    )

    $resolvedCommandPath = Resolve-TrustedCommandPath -CommandName $CommandName
    return & $resolvedCommandPath @ArgumentList
}

function Get-TrustedChocolateySource {
    return "https://community.chocolatey.org/api/v2/"
}

function Get-TrustedWingetSource {
    return "winget"
}

function Get-SecureBootstrapDirectory {
    $baseDirectory = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA "Choco-Manager\bootstrap"
    }
    else {
        Join-Path (Get-ProjectRoot) "logs\bootstrap"
    }

    if (-not (Test-Path $baseDirectory)) {
        New-Item -ItemType Directory -Path $baseDirectory -Force | Out-Null
    }

    return (Get-NormalizedPath -Path $baseDirectory)
}

function Read-Confirmation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Prompt,
        [string]$ExpectedValue = "y"
    )

    $response = Read-Host $Prompt
    return $response -ceq $ExpectedValue
}

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
    if (Test-ShouldPersistLogEntry -Level $Level) {
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
        Write-Host "No persisted log entries found. Adjust CHOCO_MANAGER_LOG_FILE_LEVELS to capture more detail." -ForegroundColor Yellow
    }
}

function Get-ChocoVersionInfo {
    $info = [PSCustomObject]@{
        IsInstalled = $false
        InstalledVersion = $null
        LatestVersion = $null
    }

    try {
        $null = Resolve-TrustedCommandPath -CommandName "choco"
    }
    catch {
        return $info
    }

    $info.IsInstalled = $true
    try {
        $info.InstalledVersion = ((Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("--version")) | Select-Object -First 1).Trim()
    }
    catch {
        Write-Log "Unable to determine the installed Chocolatey version: $($_.Exception.Message)" "WARN"
    }
    try {
        $raw = Invoke-TrustedExecutable -CommandName "choco" -ArgumentList @("list", "chocolatey", "--exact", "-r", "--source", (Get-TrustedChocolateySource)) 2>$null
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
    Write-Host "The installer will download the Chocolatey package, display its SHA256 hash, and require explicit confirmation before running the local install script." -ForegroundColor Yellow
    if (-not (Read-Confirmation -Prompt "Proceed with the secured bootstrap flow? Type y to continue" -ExpectedValue "y")) { return }

    $bootstrapDirectory = Get-SecureBootstrapDirectory
    $bootstrapPath = Join-Path $bootstrapDirectory ("bootstrap-{0}.ps1" -f ([Guid]::NewGuid().ToString("N")))
    $bootstrapScript = @'
param(
    [Parameter(Mandatory=$true)]
    [string]$PackageUrl,
    [Parameter(Mandatory=$true)]
    [string]$SelfPath
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072

$packageUri = [Uri]$PackageUrl
if ($packageUri.Scheme -ne "https" -or $packageUri.Host -ne "community.chocolatey.org") {
    throw "Rejected Chocolatey package URL: $PackageUrl"
}

$bootstrapRoot = if ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA "Choco-Manager\bootstrap"
} else {
    Join-Path $env:TEMP "Choco-Manager-bootstrap"
}
$tempRoot = Join-Path $bootstrapRoot ("install-" + [Guid]::NewGuid().ToString("N"))
$packagePath = Join-Path $tempRoot "chocolatey.nupkg"
$extractPath = Join-Path $tempRoot "package"

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Invoke-WebRequest -Uri $packageUri.AbsoluteUri -OutFile $packagePath -UseBasicParsing
    $hash = (Get-FileHash -Path $packagePath -Algorithm SHA256).Hash
    Write-Host "Downloaded Chocolatey package hash (SHA256): $hash" -ForegroundColor Yellow
    $approval = Read-Host "Type INSTALL to execute the local Chocolatey package installer"
    if ($approval -cne "INSTALL") {
        throw "Chocolatey installation cancelled by user."
    }

    Expand-Archive -Path $packagePath -DestinationPath $extractPath -Force
    $installScript = Get-ChildItem -Path $extractPath -Recurse -Filter "chocolateyInstall.ps1" | Select-Object -First 1 -ExpandProperty FullName
    if (-not $installScript) {
        throw "Could not locate chocolateyInstall.ps1 inside the Chocolatey package."
    }

    try {
        Unblock-File -Path $installScript -ErrorAction Stop
    }
    catch {
        Write-Warning "Unable to remove the downloaded file zone marker from $installScript: $($_.Exception.Message)"
    }
    & $installScript
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "Chocolatey installer exited with code $LASTEXITCODE."
    }
}
finally {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $SelfPath -Force -ErrorAction SilentlyContinue
}
'@

    Set-Content -Path $bootstrapPath -Value $bootstrapScript -Encoding UTF8

    try {
        $trustedPowerShell = Get-TrustedPowerShellPath
        Invoke-ElevatedProcess -FilePath $trustedPowerShell -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $bootstrapPath, "-PackageUrl", "https://community.chocolatey.org/api/v2/package/chocolatey", "-SelfPath", $bootstrapPath)
    }
    catch {
        Remove-Item -Path $bootstrapPath -Force -ErrorAction SilentlyContinue
        throw
    }
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
    
    $trustedPowerShell = Get-TrustedPowerShellPath
    $resolvedScriptPath = Resolve-ProjectScriptPath -Path $FilePath
    $args = @("-NoProfile", "-File", $resolvedScriptPath) + $ArgumentList

    if (Test-IsAdmin) {
        Write-Log "Running as Administrator: $resolvedScriptPath $($ArgumentList -join ' ')" "INFO"
        Start-Process -FilePath $trustedPowerShell -ArgumentList $args -Wait -NoNewWindow
    }
    else {
        Write-Log "Requesting Elevation for: $resolvedScriptPath" "WARN"
        try {
            Start-Process -FilePath $trustedPowerShell -ArgumentList $args -Verb RunAs -Wait
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

    $resolvedFilePath = Resolve-TrustedCommandPath -CommandName $FilePath

    if (Test-IsAdmin) {
        Write-Log "Running as Administrator: $resolvedFilePath $($ArgumentList -join ' ')" "INFO"
        Start-Process -FilePath $resolvedFilePath -ArgumentList $ArgumentList -Wait -NoNewWindow
    }
    else {
        Write-Log "Requesting Elevation for: $resolvedFilePath" "WARN"
        try {
            Start-Process -FilePath $resolvedFilePath -ArgumentList $ArgumentList -Verb RunAs -Wait
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

    $rawUi = $null
    $rawUiAvailable = $false
    try {
        $rawUi = $Host.UI.RawUI
        if ($null -ne $rawUi) { $rawUiAvailable = $true }
    } catch {
        $rawUiAvailable = $false
    }

    if (-not $rawUiAvailable) {
        Write-Host $Title -ForegroundColor Cyan
        for ($i = 0; $i -lt $Items.Count; $i++) {
            Write-Host ("[{0}] {1}" -f ($i + 1), $Items[$i])
        }
        $prompt = if ($CommandToken) { "Select number, '/' for commands, or Q to quit" } else { "Select number or Q to quit" }
        $input = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace($input)) { return $null }
        if ($CommandToken -and $input.Trim() -eq "/") { return $CommandToken }
        if ($input.Trim().ToLowerInvariant() -eq "q") { return $null }
        $index = 0
        if ([int]::TryParse($input.Trim(), [ref]$index)) {
            if ($index -ge 1 -and $index -le $Items.Count) { return $Items[$index - 1] }
        }
        return $null
    }

    if ($EnableMultiColumn -and -not $EnablePaging) {
        $EnablePaging = $true
    }

    $selectedIndex = 0
    $startPosition = $rawUi.CursorPosition
    $running = $true
    $needsRender = $true
    $lastWindowSize = $rawUi.WindowSize
    $effectivePageSize = $Items.Count
    $currentSortIndex = if ($SortIndex -ge 0 -and $SortIndex -lt $SortModes.Count) { $SortIndex } else { 0 }
    $lastRenderLines = 0
    $selectedResult = $null
    $originalCursorSize = $null

    try { $originalCursorSize = $rawUi.CursorSize } catch {}
    try { $rawUi.CursorSize = 0 } catch {}

    try {
        while ($running) {
            $windowSize = $rawUi.WindowSize
            if ($windowSize.Width -ne $lastWindowSize.Width -or $windowSize.Height -ne $lastWindowSize.Height) {
                $needsRender = $true
                $lastWindowSize = $windowSize
            }

            if ($needsRender) {
                $rawUi.CursorPosition = $startPosition

                $headerLines = if ($SortModes.Count -gt 1) { 3 } else { 2 }
                if ($HeaderRow) { $headerLines += 1 }
                $footerLines = 2
                $bufferWidth = $rawUi.BufferSize.Width
                $lineWidth = [Math]::Max(1, ([Math]::Min($windowSize.Width, $bufferWidth) - 1))
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

            if ($rawUi.KeyAvailable) {
                $key = $rawUi.ReadKey("NoEcho,IncludeKeyDown")
                $char = $key.Character
                $handled = $false
                if ($char) {
                    $lowerChar = $char.ToString().ToLowerInvariant()
                    switch ($lowerChar) {
                        "j" { $selectedIndex = ($selectedIndex + 1) % $Items.Count; $needsRender = $true; $handled = $true }
                        "k" { $selectedIndex = ($selectedIndex - 1 + $Items.Count) % $Items.Count; $needsRender = $true; $handled = $true }
                        "q" { $selectedResult = $null; $running = $false; $handled = $true }
                        "/" { $selectedResult = $CommandToken; $running = $false; $handled = $true }
                    }
                }
                if (-not $handled) {
                    switch ($key.VirtualKeyCode) {
                        38 { $selectedIndex = ($selectedIndex - 1 + $Items.Count) % $Items.Count; $needsRender = $true } # Up
                        40 { $selectedIndex = ($selectedIndex + 1) % $Items.Count; $needsRender = $true } # Down
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
                        13 { $selectedResult = $Items[$selectedIndex]; $running = $false } # Enter
                        27 { $selectedResult = $null; $running = $false } # Esc
                        83 {
                            if ($SortModes.Count -gt 1 -and $SortHandler) {
                                $currentSortIndex = ($currentSortIndex + 1) % $SortModes.Count
                                $Items = & $SortHandler $currentSortIndex
                                if (-not $Items) { $Items = @() }
                                if ($Items.Count -eq 0) { $selectedResult = $null; $running = $false }
                                $selectedIndex = 0
                                $needsRender = $true
                            }
                        } # S
                    }
                }
            } else {
                Start-Sleep -Milliseconds 25
            }
        }
    }
    finally {
        if ($null -ne $originalCursorSize) {
            try { $rawUi.CursorSize = $originalCursorSize } catch {}
        }
    }

    return $selectedResult
}

# Ensure functions are available when dot-sourced
# (Removed experimental module export logic to prevent loading interference)
