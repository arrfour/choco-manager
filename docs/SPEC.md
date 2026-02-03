# Choco-Manager Project Spec

Purpose
- Provide a PowerShell-based toolkit to manage Chocolatey and Winget packages across Windows machines.
- Enable export/import of package lists, install missing packages, sync to a desired list, and interactive package discovery.
- Offer a terminal UI with logging, audit history, and elevation-aware workflows.
- See `docs/ARCHITECTURE.md` for the system flow overview.

Target Environment
- Windows 10/11 or Windows Server.
- PowerShell 5.1+.
- Chocolatey installed for choco workflows; Winget optional for winget workflows.

Repository Layout
- Root wrappers (thin entrypoints):
  - `choco-manager.ps1`
  - `list-choco-apps.ps1`
  - `choco-pack-install.ps1`
  - `choco-sync.ps1`
  - `choco-utils.ps1`
  - `choco-upgrade-interactive.ps1`
  - `choco-package-explorer.ps1`
  - `winget-utils.ps1`
- UI and bootstrapping:
  - `scripts/choco-manager.ps1` (load core + main menu)
  - `scripts/main-menu.ps1` (interactive UI)
- Core helpers:
  - `src/Core/core-functions.ps1`
- Chocolatey workflows:
  - `src/Choco/list-choco-apps.ps1`
  - `src/Choco/choco-pack-install.ps1`
  - `src/Choco/choco-sync.ps1`
  - `src/Choco/choco-utils.ps1`
  - `src/Choco/choco-upgrade-interactive.ps1`
  - `src/Choco/choco-package-explorer.ps1`
- Winget workflows:
  - `src/Winget/winget-utils.ps1`
- Data and logs:
  - `data/choco_packages.txt` (git-ignored)
  - `data/choco_packages.template.txt`
  - `logs/choco-manager.log`
- Version file:
  - `VERSION`

Primary Entrypoints
- Main UI: `choco-manager.ps1` -> `scripts/choco-manager.ps1` -> `scripts/main-menu.ps1`.
- Each root wrapper executes its `src/` script with `@args` and process-scope bypass.

Core Behavior and Responsibilities
- Logging:
  - `Write-Log` writes to console with level colors and appends to `logs/choco-manager.log` in UTF8.
  - Levels: INFO, WARN, ERROR, SUCCESS.
- Elevation:
  - `Test-IsAdmin` determines admin state.
  - `Invoke-ElevatedAction` re-launches PowerShell scripts with `-Verb RunAs`.
  - `Invoke-ElevatedProcess` runs executables (e.g., choco) elevated.
- Package list handling:
  - `Get-PackageList` reads the list file, skips blank/comment lines, de-dupes.
  - `Test-SafePackageId` and `Get-ValidatedPackageId` sanitize identifiers.
- Menu framework:
  - `Get-MenuSelection` provides paging, sorting, multi-column rendering, and command palette.
  - `Format-PackageRow` formats display rows with aligned columns.
- Version and system info:
  - `Get-AppVersion` reads `VERSION`.
  - `Get-ChocoVersionInfo` detects installed and latest Chocolatey versions.
- Chocolatey install:
  - `Install-Chocolatey` prompts user and runs the official install script via elevation.

Feature Workflows
- Export list (Choco):
  - `src/Choco/list-choco-apps.ps1` runs `choco list --idonly --limit-output`, sorts, saves UTF8.
- Install missing (Choco):
  - `src/Choco/choco-pack-install.ps1` checks admin, optionally upgrades choco, installs missing.
- Sync (Choco):
  - `src/Choco/choco-sync.ps1` installs missing and optionally removes orphans after confirmation.
- Update and Info (Choco):
  - `src/Choco/choco-utils.ps1` supports `Update` and `Info` actions.
- Interactive upgrade (Choco):
  - `src/Choco/choco-upgrade-interactive.ps1` reads `choco outdated` and upgrades selected packages.
- Package utilities (Choco + Winget):
  - `src/Choco/choco-package-explorer.ps1` lists, searches, and shows info.
- Winget tools:
  - `src/Winget/winget-utils.ps1` lists, searches, installs, removes, and shows info.

Menu Flow (Current)
- Main menu in `scripts/main-menu.ps1`:
  - Package Utilities (Search/Info/Remove)
  - List/View Packages (combined)
  - Export/Update List from Local
  - Install Missing Packages
  - Interactive Update (Selectable)
  - Update All Packages (Silent)
  - Synchronize (Full Match)
  - Winget Tools
  - View Audit Log
  - Conditional: Elevate to Admin, Install Chocolatey, Quit
- Command palette (/) supports help, quit, list, search, logs.

Manual Run Commands
- Main UI:
  - `powershell -ExecutionPolicy Bypass -File .\choco-manager.ps1`
- Export list:
  - `powershell -ExecutionPolicy Bypass -File .\list-choco-apps.ps1`
- Install from list:
  - `powershell -ExecutionPolicy Bypass -File .\choco-pack-install.ps1`
- Sync/remove using the list:
  - `powershell -ExecutionPolicy Bypass -File .\choco-sync.ps1 -Action Sync`
  - `powershell -ExecutionPolicy Bypass -File .\choco-sync.ps1 -Action Remove -PackageName <id>`
- Package utilities UI:
  - `powershell -ExecutionPolicy Bypass -File .\choco-package-explorer.ps1`
- Interactive upgrade menu:
  - `powershell -ExecutionPolicy Bypass -File .\choco-upgrade-interactive.ps1`
- Winget utilities UI:
  - `powershell -ExecutionPolicy Bypass -File .\winget-utils.ps1`

Error Handling and Exit Codes
- Fail fast on missing core functions or script prerequisites (exit 1).
- Wrap external commands in try/catch when needed.
- Check `$LASTEXITCODE` after choco/winget calls and log failures.

Data and Log Handling
- `data/choco_packages.txt` is git-ignored; treat as sensitive.
- Always write package lists as UTF8.
- `logs/choco-manager.log` is sensitive inventory data; avoid check-in.

Spec for Recreating the Project
- Implement root wrappers that forward `@args` to `src/` scripts with process-scope bypass.
- Implement `src/Core/core-functions.ps1` with logging, elevation helpers, menu utilities, and package parsing.
- Implement Choco workflows for list export, install, sync, update/info, interactive upgrade, and package explorer.
- Implement Winget workflows for list, search, install, remove, info, and interactive UI.
- Implement `scripts/choco-manager.ps1` to set process execution policy, unblock core, and load menu.
- Implement `scripts/main-menu.ps1` to show header/footer, menu, command palette, and execute actions.
- Add `VERSION`, `data/`, and `logs/` directories and ensure defaults match this spec.

Proposed Menu Reorganization (Improved UX)
- Inventory
  - List/View Packages (Combined)
  - List Local Packages (Choco)
  - List Local Packages (Winget)
- Package Lists
  - Export/Update List from Local
  - Install Missing Packages
  - Synchronize (Full Match)
- Updates
  - Interactive Update (Selectable)
  - Update All Packages (Silent)
- Search and Info
  - Search Chocolatey Repository
  - Search Winget Repository
  - Package Info (by name/ID)
- Tools
  - Package Utilities
  - Winget Tools
- Logs and Help
  - View Audit Log
- System
  - Elevate to Admin (conditional)
  - Install Chocolatey (conditional)
- Quit

Rationale for Menu Changes
- Group by task domain so common workflows are adjacent.
- Promote list management and updates to first-class sections.
- Keep system actions isolated from package operations.
- Reduce duplication by centralizing search/info at top level.

Menu Reorg Implementation Plan
- Add a grouped top-level menu in `scripts/main-menu.ps1` with category headings.
- Map Inventory items to existing functions or scripts:
  - Combined list: `Show-PackageList`.
  - Choco-only list: call `src/Choco/choco-package-explorer.ps1` and add a new entry to open its Choco list mode, or add a small helper to list choco locally.
  - Winget-only list: call `src/Winget/winget-utils.ps1` with a new list-only action or reuse existing list selection.
- Map Package Lists to existing scripts:
  - Export/Update List: `src/Choco/list-choco-apps.ps1`.
  - Install Missing: `src/Choco/choco-pack-install.ps1`.
  - Synchronize: `src/Choco/choco-sync.ps1 -Action Sync`.
- Map Updates to existing scripts:
  - Interactive Update: `src/Choco/choco-upgrade-interactive.ps1`.
  - Update All: `src/Choco/choco-utils.ps1 -Action Update`.
- Map Search and Info to existing scripts:
  - Choco search/info: `src/Choco/choco-package-explorer.ps1`.
  - Winget search/info: `src/Winget/winget-utils.ps1`.
- Map Tools to the existing submenus:
  - Package Utilities: `src/Choco/choco-package-explorer.ps1`.
  - Winget Tools: `src/Winget/winget-utils.ps1`.
- Map Logs and System to current functions:
  - Audit log: `Show-AuditLog`.
  - Elevate: `Invoke-ElevatedAction`.
  - Install Chocolatey: `Install-Chocolatey`.
- Keep command palette entries aligned with the new top-level structure (list/search/logs).

Flow Tables (Command -> Script -> Core Functions)
- Main UI launch -> `choco-manager.ps1` -> `scripts/choco-manager.ps1` -> `scripts/main-menu.ps1` -> `Get-MenuSelection`/`Write-Log`.
- Export list -> `list-choco-apps.ps1` -> `src/Choco/list-choco-apps.ps1` -> `Get-PackageList`/`Write-Log`.
- Install from list -> `choco-pack-install.ps1` -> `src/Choco/choco-pack-install.ps1` -> `Test-IsAdmin`/`Invoke-ElevatedAction`/`Get-PackageList`.
- Sync -> `choco-sync.ps1 -Action Sync` -> `src/Choco/choco-sync.ps1` -> `Test-IsAdmin`/`Get-PackageList`/`Get-ValidatedPackageId`.
- Interactive update -> `choco-upgrade-interactive.ps1` -> `src/Choco/choco-upgrade-interactive.ps1` -> `Test-IsAdmin`/`Write-Log`.
- Update all -> `choco-utils.ps1 -Action Update` -> `src/Choco/choco-utils.ps1` -> `Test-IsAdmin`/`Get-PackageList`.
- Package utilities -> `choco-package-explorer.ps1` -> `src/Choco/choco-package-explorer.ps1` -> `Get-MenuSelection`/`Format-PackageRow`.
- Winget tools -> `winget-utils.ps1` -> `src/Winget/winget-utils.ps1` -> `Get-MenuSelection`/`Get-ValidatedPackageId`.
