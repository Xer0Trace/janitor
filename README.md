# Janitor

## Download and run on Windows

1. On [GitHub](https://github.com/Xer0Trace/janitor), select **Code → Download ZIP**.
2. Extract the ZIP to a folder outside **Downloads**. Keep `Run-Janitor.cmd` and `janitor.ps1` together.
3. Right-click **Run-Janitor.cmd**, choose **Run as administrator**, and approve the Windows prompt.

To preview from PowerShell opened in the extracted folder, run:

```powershell
.\Run-Janitor.cmd -Preview
```

Preview requires no elevation and exits before making changes. `-WhatIf` also works. The launcher reads the adjacent PowerShell file and runs it as a console command, so it works under Windows PowerShell's `AllSigned` policy without changing that policy. Run it only from a copy you trust.

You can also paste the entire contents of `janitor.ps1` into an elevated 64-bit PowerShell window, or run `.\janitor.ps1` directly when your execution policy permits it.

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
