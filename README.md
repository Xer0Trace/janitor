# Janitor

Open **64-bit Windows PowerShell 5.1 or PowerShell 7 as Administrator**. Open `janitor.ps1` in a text editor, copy the entire file, and paste it into the console as one block. Press Enter if the console is still waiting at the final line. You can also run the saved script from its folder.

```powershell
.\janitor.ps1
```

If your session uses the `AllSigned` execution policy, use the paste instructions above. Running the unsigned `.ps1` file directly requires signing it under that policy.

To preview the operations without running cleanup or repairs, run:

```powershell
.\janitor.ps1 -Preview
```

`-WhatIf` is an alias for `-Preview`.

## Downloads and Recycle Bin

Janitor asks separately before permanently deleting the contents of your configured Downloads folder and before emptying your Recycle Bin across drives. Both prompts default to **No**. Check the displayed account and Downloads path, especially if you elevated PowerShell using a different account. Janitor leaves the Downloads folder itself in place and reports any items it could not remove. For redirected Downloads, it accepts ordinary folders on local drives and checks the path before deletion.

## Windows maintenance

1. Run DISM `/CheckHealth`, `/ScanHealth`, and `/RestoreHealth`.
2. After a successful `/RestoreHealth`, run `sfc.exe /scannow`.
3. After the repair commands return success, run DISM `/StartComponentCleanup`.
4. Run the Windows Disk Cleanup handlers for the screenshot categories.

Disk Cleanup covers Windows Update Cleanup, Delivery Optimization Files, thumbnails, old device driver packages, Microsoft Defender Antivirus cleanup, Windows error reports and feedback diagnostics, temporary files, Temporary Internet Files, DirectX Shader Cache, and temporary Windows installation files. The last category is included because it appears in the screenshot, where its checkbox was clear. Windows determines which files in each category are eligible. Janitor reports missing handlers and defers Windows Update Cleanup if the repair sequence fails or DISM component cleanup requires a restart.

Janitor reports the change in free space on the Windows drive and saves a transcript under `%LOCALAPPDATA%\Janitor\Logs`. Review the Windows Resource Protection message in the console or transcript for the SFC result.

[Microsoft's DISM and SFC instructions](https://support.microsoft.com/en-us/windows/experience/backup-recovery/using-the-system-file-checker-in-windows) · [Disk Cleanup command reference](https://learn.microsoft.com/windows-server/administration/windows-commands/cleanmgr) · [DISM component cleanup](https://learn.microsoft.com/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder)
