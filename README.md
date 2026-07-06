# Janitor

## Overview
This PowerShell script performs a **safe deep cleanup** of Windows systems.  
It targets temporary files, caches, update leftovers, logs, and recycle bins across all user profiles while avoiding critical system files.  
The script is designed to reclaim disk space without harming normal Windows operation.

---

## ✨ Features
- **System-wide cleanup**
  - Windows Temp, Prefetch, and SoftwareDistribution caches  
  - CBS servicing logs  
  - Recycle Bin (all drives)

- **Per-user cleanup**
  - Temp folders  
  - Browser caches (Chrome, Edge, Firefox)  
  - Microsoft Teams and Zoom caches/logs  
  - Installer leftovers (`*.tmp`, `*.log`)  
  - Crash dumps (`*.dmp`)

- **Service handling**
  - Stops Windows Update (`wuauserv`) and BITS (`bits`) temporarily  
  - Restarts services after cleanup  

- **Component Store cleanup**
  - Runs `dism.exe /Online /Cleanup-Image /StartComponentCleanup`  
  - Safely reduces the size of the WinSxS folder  

- **Space reporting**
  - Reports free space before and after  
  - Displays total GB freed  

---

## 🚀 Usage

### 1. Run as Administrator
Open PowerShell **as Administrator**.

### 2. Execute the script
```powershell
.\janitor.ps1


---

## Updated Script Header

```powershell
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Safe Windows disk cleanup: system temp/cache locations + per-user browser/app caches,
    with optional recycle-bin emptying and DISM component cleanup.

.DESCRIPTION
    Improvements over the original version:
      - Elevation is enforced via #Requires (fails fast with a clear error instead of
        silently doing nothing).
      - Update services (wuauserv/bits) are guaranteed to restart via try/finally,
        even if the script errors out midway.
      - Destructive/slow steps (Recycle Bin, DISM cleanup, deleting .dmp/.log/.tmp files)
        are opt-in switches, not silent defaults.
      - -WhatIf / -Confirm supported so you can preview deletions first.
      - Big cache folders are cleared with robocopy /MIR instead of Remove-Item -Recurse,
        which is much faster on folders with tens of thousands of small files.
      - Per-profile size reporting runs in parallel jobs instead of sequentially.
      - Full run is logged to a transcript file.

.PARAMETER IncludeRecycleBin
    Also empties the Recycle Bin for all users.

.PARAMETER IncludeComponentCleanup
    Also runs DISM /StartComponentCleanup (can take several minutes; frees WinSxS space
    but removes the ability to uninstall currently installed updates).

.PARAMETER IncludeLooseFiles
    Also deletes stray *.tmp/*.log files in Downloads and *.dmp files in Documents.
    Off by default because dump/log files are sometimes needed for troubleshooting.

.EXAMPLE
    .\janitor.ps1 -WhatIf
    Preview what would be deleted without deleting anything.

.EXAMPLE
    .\janitor.ps1 -IncludeRecycleBin -IncludeComponentCleanup
#>
```
