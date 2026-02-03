# Choco-Manager Architecture

Purpose
- Describe how the PowerShell scripts are organized and how requests flow through the tool.

High-Level Overview
- Root wrappers dispatch to `src/` scripts with process-scope execution policy bypass.
- `scripts/choco-manager.ps1` loads core helpers and the main menu UI.
- `scripts/main-menu.ps1` is the interactive hub for user actions.
- `src/Core/core-functions.ps1` contains logging, elevation, menus, and shared parsing helpers.
- Chocolatey and Winget workflows are separated under `src/Choco/` and `src/Winget/`.

Request Flow (Typical)
- User runs `choco-manager.ps1`.
- Wrapper loads `scripts/choco-manager.ps1`.
- `scripts/choco-manager.ps1` loads `src/Core/core-functions.ps1`, then `scripts/main-menu.ps1`.
- Menu selection launches a target script or function, which uses core helpers for logging/elevation.

Entrypoints
- Primary UI:
  - `choco-manager.ps1` -> `scripts/choco-manager.ps1` -> `scripts/main-menu.ps1`
- Utilities:
  - `list-choco-apps.ps1` -> `src/Choco/list-choco-apps.ps1`
  - `choco-pack-install.ps1` -> `src/Choco/choco-pack-install.ps1`
  - `choco-sync.ps1` -> `src/Choco/choco-sync.ps1`
  - `choco-utils.ps1` -> `src/Choco/choco-utils.ps1`
  - `choco-upgrade-interactive.ps1` -> `src/Choco/choco-upgrade-interactive.ps1`
  - `choco-package-explorer.ps1` -> `src/Choco/choco-package-explorer.ps1`
  - `winget-utils.ps1` -> `src/Winget/winget-utils.ps1`

Core Module Responsibilities
- Logging and audit output via `Write-Log` and `Show-AuditLog`.
- Admin detection and elevation via `Test-IsAdmin`, `Invoke-ElevatedAction`, and `Invoke-ElevatedProcess`.
- Package list parsing via `Get-PackageList`, validation via `Get-ValidatedPackageId`.
- Menu UI rendering via `Get-MenuSelection` and `Format-PackageRow`.
- Chocolatey detection and install via `Get-ChocoVersionInfo` and `Install-Chocolatey`.

Data and Logs
- `data/choco_packages.txt` is the default list (git-ignored, user-specific).
- `data/choco_packages.template.txt` is a shareable template.
- `logs/choco-manager.log` is a UTF8 audit log; treat as sensitive.

Menu Structure (Current)
- Inventory: combined list, choco list, winget list.
- Package Lists: export, install, sync.
- Updates: interactive, update all.
- Search and Info: choco search, winget search, info by name.
- Tools: package utilities, winget tools.
- Logs and Help: view audit log.
- System: elevate, install chocolatey.
- Quit.

Safety and Permissions
- Admin rights required for install/update/sync/remove operations.
- Elevation re-launches the same script with preserved parameters.
- External command failures are logged and surfaced in the UI.
