# Agent Guide for choco-manager

Purpose
- This repository is a PowerShell-based toolset for managing Chocolatey and Winget packages.
- Agents should follow the established script layout and logging/elevation patterns.
- Keep changes safe for end-users on Windows with PowerShell 5.1+.

Spec Document
- See `docs/SPEC.md` for a full project spec, workflow mapping, and menu reorg plan.
- See `docs/ARCHITECTURE.md` for the system flow overview.

Scope and Required Context
- Primary entrypoint: `choco-manager.ps1` (wrapper) -> `scripts/choco-manager.ps1`.
- Core helpers: `src/Core/core-functions.ps1` (logging, elevation, menus, validation).
- Choco workflows: `src/Choco/*.ps1`.
- Winget workflows: `src/Winget/winget-utils.ps1`.
- Data: `data/choco_packages.txt` (git-ignored), template in `data/choco_packages.template.txt`.
- Logs: `logs/choco-manager.log` (treat as sensitive inventory data).

Build / Lint / Test Commands
- No dedicated build system in this repo (no Makefile, package.json, or CI config found).
- No lint tooling configured (no PSScriptAnalyzer settings found).
- No test framework detected (no Pester usage found).

Manual Run Commands
- Launch the main UI:
  - `powershell -ExecutionPolicy Bypass -File .\choco-manager.ps1`
- Export package list:
  - `powershell -ExecutionPolicy Bypass -File .\list-choco-apps.ps1`
- Install from package list:
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

Single-Test / Single-Lint Command
- Not applicable: no test or lint runner is configured in this repo.
- If you add tests later (e.g., Pester), document a single-test command here.

Agent Rules (Cursor/Copilot)
- No `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` found.
- If those files are added later, include their requirements here verbatim.

Code Style Guidelines (PowerShell)

Imports and Script Structure
- Scripts typically dot-source core helpers:
  - `. (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "src\Core\core-functions.ps1")`
- Keep wrapper scripts small; use them to pass args to `src/*` scripts.
- Prefer `Join-Path` and `$PSScriptRoot` for paths; avoid hard-coded absolute paths.

Formatting and Layout
- Use 4 spaces for indentation; align `param(...)` blocks in a readable way.
- Keep braces on the same line for `try {` / `catch {` and `if (...) {` patterns.
- Use blank lines to separate logical blocks (setup, validation, main logic, cleanup).
- Use `[PSCustomObject]@{}` for structured data and `@()` for arrays.

Naming Conventions
- Functions: Verb-Noun with PascalCase (e.g., `Write-Log`, `Invoke-ElevatedAction`).
- Parameters: PascalCase with clear nouns (`PackageName`, `InputFile`).
- Variables: camelCase for locals (`$installedPackages`, `$safeName`).
- Use `Get-ValidatedPackageId` to sanitize user or file inputs.

Types and Parameters
- Use `param(...)` at top of script for inputs; use `[Parameter(Mandatory=$true)]` when needed.
- Validate arguments with `[ValidateSet(...)]` for constrained values.
- Use `[string]`, `[int]`, `[switch]`, and `[string[]]` explicitly when helpful.

Error Handling and Exit Codes
- Prefer `try { ... } catch { ... }` for external commands and file IO.
- Use `Write-Log` with `INFO`, `WARN`, `ERROR`, `SUCCESS` levels.
- Use `throw` for unrecoverable errors that should fail the script.
- Check `$LASTEXITCODE` after `choco` or `winget` calls; log failures.
- Use `exit 1` for script-level fatal errors (e.g., missing core functions).

Logging and UX
- Use `Write-Log` for actions that change system state.
- Use `Write-Host` for UI prompts and menus (as in current scripts).
- Keep log lines succinct and actionable; include package id or action context.

Elevation and Security
- Use `Test-IsAdmin` and `Invoke-ElevatedAction` for operations requiring elevation.
- When elevating, re-launch the same script with `-ArgumentList` preserving inputs.
- Validate package IDs with `Test-SafePackageId` / `Get-ValidatedPackageId`.
- Treat `data/choco_packages.txt` and `logs/choco-manager.log` as sensitive.

Data File Handling
- Default list path: `data/choco_packages.txt` (git-ignored).
- When reading lists, skip blank/commented lines and de-duplicate entries.
- Always write package lists with UTF8 encoding.

Consistency Guidelines
- Keep menu output consistent with `Get-MenuSelection` and `Format-PackageRow`.
- Prefer `Sort-Object` and `Select-Object -Unique` when normalizing lists.
- Maintain wrapper script pattern in repo root for new tools.

What Not to Do
- Do not add auto-elevation or privileged actions without user confirmation.
- Do not commit user-specific `data/choco_packages.txt` or logs.
- Do not change execution policy beyond process scope.

When Adding New Scripts
- Add a wrapper script in repo root if it is user-facing.
- Source `src/Core/core-functions.ps1` and use existing helpers.
- Update this file with new commands, lint/test tools, or style rules.
