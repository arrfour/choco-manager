# Choco-List Manager

![Version](https://img.shields.io/badge/version-20260211.01-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

**Version 20260211.01**

A set of PowerShell scripts to manage and synchronize your Chocolatey packages across Windows machines.

> **Open Source Philosophy**: This project is completely open source. You are encouraged to fork, modify, script, and share your own versions. Contributions are welcome!

## Features

-   **Smart Elevation**: Automatically detects when Administrator privileges are needed (e.g., for installation) and prompts for elevation on-demand. Safe, secure, and user-conrolled.
-   **Export**: Generates a clean, sorted list of your currently installed Chocolatey packages.
-   **Install**: Reads that list and installs missing packages on any machine, intelligently skipping those already installed.

## Future Features

-   **Sync**: Synchronize package lists between machines.
-   **Update**: Update installed packages to the latest version.
-   **Remove**: Remove packages from the list and uninstall them from the target machine.
-   **info**: Display information about a specific package.
-   **Enhanced Auditing**: track warnings and errors when running scripts.
-   **Robust error handling**: handle errors gracefully and provide useful feedback.
-   **Parameterization**: Move away from hardcoded file paths to allow for more flexible integration with deployment tools like Intune or Ansible.
-   **Expanded Tooling**: Consider adding a wrapper for winget to provide a unified Windows package management experience.


## Usage

### **Recommended: Use the Terminal UI**

For the easiest experience, run the manager script:
```powershell
.\choco-manager.ps1
```
This interactive tool allows you to check status, export lists, and install packages from a simple menu.

Notes:
- If Chocolatey is missing, the main menu will show an "Install Chocolatey" option.
- The footer shows the installed Chocolatey version and, when different, the latest available version.
- The wrappers now invoke the project scripts directly instead of forcing a blanket process-scope execution policy bypass.

## Project Layout

- `choco-manager.ps1`: primary entrypoint (wrapper)
- `scripts/`: entry scripts
- `src/Core/`: shared functions and UI helpers
- `src/Choco/`: Chocolatey workflows
- `src/Winget/`: Winget workflows
- `data/`: templates and sample data
- `logs/`: runtime logs

## Data Files

- `data/choco_packages.txt`: default package list (user-specific, git-ignored)
- `data/choco_packages.template.txt`: template list

---

### Manual Usage

### 1. Export Package List (Source Machine)

Run the list script to generate `choco_packages.txt`:

```powershell
.\list-choco-apps.ps1
```
This creates a sorted list of your currently installed packages.

**Note**: `choco_packages.txt` is git-ignored by default to protect your personal environment list. Use `choco_packages.template.txt` as a starting point if you want to commit a shared list of packages.

### 2. Install Packages (Target Machine)

Copy the `choco_packages.txt` and `choco-pack-install.ps1` to the target machine.

Run the install script:

```powershell
.\choco-pack-install.ps1
```

The script will:
- Check for Chocolatey updates.
- Parse the package list.
- Compare against currently installed packages.
- Install only the missing packages.

## Requirements

- Windows
- PowerShell 5.1+
- [Chocolatey](https://chocolatey.org/install) installed

## Security Guidance

- Run the scripts from a trusted, access-controlled directory.
- Prefer `RemoteSigned` or stronger execution policies. The project no longer forces routine `ExecutionPolicy Bypass` for normal menu and wrapper launches.
- Chocolatey installs, searches, and upgrades are restricted to `https://community.chocolatey.org/api/v2/` by default.
- Winget installs and searches are restricted to the `winget` source by default.
- Review `data/choco_packages.txt` before running install, update, or sync actions. Managed package list reads and writes are restricted to the repository `data\` directory.
- The Chocolatey bootstrap flow now downloads the package locally, shows its SHA256 hash, and requires explicit confirmation before executing the local installer.
- Avoid copying scripts from unknown sources or locations with weak ACLs.
- Treat `logs/choco-manager.log` as sensitive inventory data. By default, only warning and error events are persisted; set `CHOCO_MANAGER_LOG_FILE_LEVELS` if you need broader local audit logging.

## Disclaimer

Always review the `choco_packages.txt` file before running the install script to ensure you are installing only what you intend.
