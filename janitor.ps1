# Paste the entire block into an elevated PowerShell, or run .\janitor.ps1.
# Preview a saved copy with .\janitor.ps1 -Preview (or -WhatIf).
& {
    if ($args.Count -gt 1 -or ($args.Count -eq 1 -and $args[0] -notin '-Preview', '-WhatIf')) {
        throw 'Usage: .\janitor.ps1 [-Preview | -WhatIf]'
    }
    $preview = $WhatIfPreference -or $args.Count -eq 1
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $false

    function Confirm-Deletion([string]$message) {
        $choices = [System.Management.Automation.Host.ChoiceDescription[]] @('&No', '&Yes')
        try {
            return ($Host.UI.PromptForChoice('Confirm permanent deletion', $message, $choices, 0) -eq 1)
        } catch {
            Write-Warning "Confirmation unavailable. Skipping deletion. $_"
            return $false
        }
    }

    function Get-DownloadsFolder {
        if (-not ('Janitor.NativeFolders' -as [type])) {
            Add-Type -Namespace Janitor -Name NativeFolders -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll", ExactSpelling = true)]
public static extern int SHGetKnownFolderPath(ref System.Guid folderId, uint flags,
    System.IntPtr token, out System.IntPtr path);
'@
        }
        $id = [guid]'374DE290-123F-4565-9164-39C4925E467B'
        $pointer = [IntPtr]::Zero
        try {
            # KF_FLAG_DONT_VERIFY also returns the configured path if the folder is missing.
            $result = [Janitor.NativeFolders]::SHGetKnownFolderPath(
                [ref]$id, 0x4000, [IntPtr]::Zero, [ref]$pointer)
            if ($result -ne 0) { throw ('Windows returned 0x{0:X8} for Downloads.' -f $result) }
            return [Runtime.InteropServices.Marshal]::PtrToStringUni($pointer)
        } finally {
            [Runtime.InteropServices.Marshal]::FreeCoTaskMem($pointer)
        }
    }

    function Get-SafeDownloadsPath {
        $configuredPath = Get-DownloadsFolder
        if ($configuredPath -notmatch '^[a-zA-Z]:\\') {
            throw "Downloads must be on a local drive. Configured path: $configuredPath"
        }
        $path = [IO.Path]::GetFullPath($configuredPath).TrimEnd('\')
        $root = [IO.Path]::GetPathRoot($configuredPath)
        $drive = [IO.DriveInfo]::new($root)
        if ($drive.DriveType -notin 'Fixed', 'Removable') {
            throw "Downloads is not on a fixed or removable local drive: $path"
        }

        $protectedPaths = @(
            $root, $env:USERPROFILE, $env:PUBLIC, $env:SystemRoot,
            $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)},
            [Environment]::GetFolderPath('DesktopDirectory'),
            [Environment]::GetFolderPath('MyDocuments'),
            [Environment]::GetFolderPath('MyPictures'),
            [Environment]::GetFolderPath('MyMusic'),
            [Environment]::GetFolderPath('MyVideos'),
            $env:LOCALAPPDATA, $env:APPDATA
        )
        foreach ($protectedPath in $protectedPaths) {
            if ([string]::IsNullOrWhiteSpace($protectedPath)) { continue }
            $protectedPath = [IO.Path]::GetFullPath($protectedPath).TrimEnd('\')
            if ($path -eq $protectedPath -or
                $protectedPath.StartsWith("$path\", [StringComparison]::OrdinalIgnoreCase)) {
                throw "Downloads overlaps a protected folder: $path"
            }
        }
        foreach ($systemPath in @($env:SystemRoot, $env:ProgramData, $env:ProgramFiles,
                ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA, $env:APPDATA)) {
            if ($systemPath -and $path.StartsWith("$systemPath\", [StringComparison]::OrdinalIgnoreCase)) {
                throw "Downloads points inside a system or application folder: $path"
            }
        }
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { return }
        for ($folder = [IO.DirectoryInfo]::new($path); $folder; $folder = $folder.Parent) {
            if ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Downloads uses a link or reparse point: $($folder.FullName)"
            }
        }
        return $path
    }

    function Clear-DownloadsContents([string]$path) {
        # Delete ordinary directories bottom-up. Never recurse through a reparse point.
        foreach ($item in Get-ChildItem -LiteralPath $path -Force) {
            try {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    if ($item.LinkType -notin 'Junction', 'SymbolicLink') {
                        Write-Warning "Skipped a special file or folder: $($item.FullName)"
                        continue
                    }
                    if ($item.PSIsContainer) {
                        [IO.Directory]::Delete($item.FullName, $false)
                    } else {
                        [IO.File]::Delete($item.FullName)
                    }
                } elseif ($item.PSIsContainer) {
                    Clear-DownloadsContents $item.FullName
                    # Non-recursive deletion fails if anything remains in the directory.
                    [IO.Directory]::Delete($item.FullName, $false)
                } else {
                    Remove-Item -LiteralPath $item.FullName -Force -Confirm:$false
                }
            } catch {
                Write-Warning "Could not delete '$($item.FullName)'. $_"
            }
        }
    }

    function Invoke-MaintenanceCommand([string]$name, [string[]]$arguments) {
        Write-Host "`nRunning $name $($arguments -join ' ')"
        & (Join-Path $systemTools $name) @arguments | Out-Host
        $code = $LASTEXITCODE
        Write-Host "$name exit code: $code"
        if ($code -in 1641, 3010) {
            Write-Warning "$name reported that Windows requires a restart."
        } elseif ($code -ne 0) {
            Write-Warning "$name returned a nonzero exit code. See the command output above."
        }
        return $code
    }

    function Invoke-DiskCleanup([string[]]$requestedHandlers) {
        $registryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
        $handlers = @(Get-ChildItem -LiteralPath $registryPath)
        $selected = @($handlers | Where-Object { $_.PSChildName -in $requestedHandlers })
        foreach ($name in $requestedHandlers) {
            if ($name -notin $selected.PSChildName) {
                Write-Warning "This Windows installation has no Disk Cleanup handler named '$name'."
            }
        }
        if ($selected.Count -eq 0) { return }
        $cleanmgr = Join-Path $systemTools 'cleanmgr.exe'
        if (-not (Test-Path -LiteralPath $cleanmgr -PathType Leaf)) {
            throw 'Disk Cleanup (cleanmgr.exe) is unavailable.'
        }

        $usedFlags = @($handlers | ForEach-Object { $_.GetValueNames() })
        $profile = 9999
        while ($profile -ge 0 -and ('StateFlags{0:D4}' -f $profile) -in $usedFlags) { $profile-- }
        if ($profile -lt 0) { throw 'No unused Disk Cleanup profile number was found.' }
        $flag = 'StateFlags{0:D4}' -f $profile
        $createdFlags = @()
        try {
            # Enable only the selected categories in an unused profile.
            foreach ($handler in $selected) {
                New-ItemProperty -LiteralPath $handler.PSPath -Name $flag -Value 2 -PropertyType DWord |
                    Out-Null
                $createdFlags += $handler.PSPath
            }
            Write-Host "`nRunning Windows Disk Cleanup for:"
            $selected.PSChildName | ForEach-Object { Write-Host "  $_" }
            $process = Start-Process -FilePath $cleanmgr -ArgumentList "/sagerun:$profile" -Wait -PassThru
            if ($process.ExitCode -ne 0) {
                Write-Warning "Disk Cleanup returned exit code $($process.ExitCode)."
            }
        } finally {
            foreach ($path in $createdFlags) {
                try {
                    Remove-ItemProperty -LiteralPath $path -Name $flag -Confirm:$false
                } catch {
                    Write-Warning "Could not remove temporary profile flag $flag at '$path'. $_"
                }
            }
        }
    }

    $handlers = @(
        'Update Cleanup',
        'Delivery Optimization Files',
        'Thumbnail Cache',
        'Device Driver Packages',
        'Windows Defender',
        'Windows Error Reporting Files',
        'Feedback Hub Archive log files',
        'Temporary Files',
        'Internet Cache Files',
        'D3D Shader Cache',
        'Temporary Setup Files'
    )
    if ($preview) {
        Write-Host 'Preview only. The active Windows account would get separate confirmations for Downloads and Recycle Bin.'
        try { Write-Host "Downloads: $(Get-DownloadsFolder)" } catch { Write-Warning $_ }
        Write-Host 'Maintenance order: DISM CheckHealth, ScanHealth, RestoreHealth, SFC /scannow, DISM StartComponentCleanup.'
        Write-Host 'Disk Cleanup handlers:'
        $handlers | ForEach-Object { Write-Host "  $_" }
        return
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning 'Open PowerShell using Run as administrator, then paste or run this script again.'
        return
    }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Write-Warning 'Use an elevated 64-bit PowerShell session on this 64-bit installation of Windows.'
        return
    }

    $systemTools = Join-Path $env:SystemRoot 'System32'
    $mutex = [Threading.Mutex]::new($false, 'Global\Janitor.WindowsCleanup')
    $lockHeld = $false
    $transcribing = $false
    try {
        try { $lockHeld = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $lockHeld = $true }
        if (-not $lockHeld) {
            Write-Warning 'Janitor is already running in another session.'
            return
        }
        $logDirectory = Join-Path $env:LOCALAPPDATA 'Janitor\Logs'
        try {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
            $logPath = Join-Path $logDirectory "Cleanup-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff').log"
            Start-Transcript -Path $logPath | Out-Null
            $transcribing = $true
            Write-Host "Logging to $logPath"
        } catch {
            Write-Warning "Could not start the transcript. $_"
        }
        $systemDrive = [IO.DriveInfo]::new($env:SystemDrive)
        $before = $systemDrive.AvailableFreeSpace
        Write-Host "Personal cleanup account: $($identity.Name)"

        try {
            $downloads = Get-SafeDownloadsPath
            if (-not $downloads) {
                Write-Host 'The configured Downloads folder is missing.'
            } elseif (Confirm-Deletion "Permanently delete all contents of '$downloads'?") {
                if ((Get-SafeDownloadsPath) -ne $downloads) { throw 'The Downloads path changed.' }
                Clear-DownloadsContents $downloads
                if (Get-ChildItem -LiteralPath $downloads -Force | Select-Object -First 1) {
                    Write-Warning 'Some items remain in Downloads. See the warnings above.'
                } else {
                    Write-Host 'Downloads is empty.'
                }
            }
        } catch {
            Write-Warning "Could not finish Downloads cleanup. $_"
        }
        if (Confirm-Deletion "Permanently empty the Recycle Bin for $($identity.Name) on all drives?") {
            try {
                Clear-RecycleBin -Force
            } catch {
                Write-Warning "Could not confirm that the Recycle Bin was emptied. $_"
            }
        }

        $restoreCode = $null
        $sfcCode = $null
        $dismArguments = @('/Online', '/Cleanup-Image')
        try {
            $null = Invoke-MaintenanceCommand 'dism.exe' ($dismArguments + '/CheckHealth')
            $null = Invoke-MaintenanceCommand 'dism.exe' ($dismArguments + '/ScanHealth')
            $restoreCode = Invoke-MaintenanceCommand 'dism.exe' ($dismArguments + '/RestoreHealth')
            if ($restoreCode -eq 0) {
                $sfcCode = Invoke-MaintenanceCommand 'sfc.exe' '/scannow'
                Write-Host 'See the Windows Resource Protection message above for the SFC result.'
            } else {
                Write-Warning 'SFC is pending a successful DISM RestoreHealth run.'
            }
        } catch {
            Write-Warning "Could not finish the repair sequence. $_"
        }
        if ($restoreCode -eq 0 -and $sfcCode -eq 0) {
            try {
                $componentCode = Invoke-MaintenanceCommand 'dism.exe' ($dismArguments + '/StartComponentCleanup')
                if ($componentCode -in 1641, 3010) {
                    $handlers = $handlers | Where-Object { $_ -ne 'Update Cleanup' }
                    Write-Warning 'Windows Update Cleanup is pending a restart.'
                }
            } catch {
                Write-Warning "Could not run DISM component cleanup. $_"
            }
        } else {
            $handlers = $handlers | Where-Object { $_ -ne 'Update Cleanup' }
            Write-Warning 'Component and Windows Update cleanup are pending a successful repair sequence.'
        }
        try {
            Invoke-DiskCleanup $handlers
        } catch {
            Write-Warning "Disk Cleanup could not finish. $_"
        }

        $after = $systemDrive.AvailableFreeSpace
        Write-Host ("`n{0} free space: {1:N2} GiB before, {2:N2} GiB after ({3:+0.00;-0.00;0.00} GiB change)." -f
            $env:SystemDrive, ($before / 1GB), ($after / 1GB), (($after - $before) / 1GB))
    } finally {
        if ($lockHeld) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
        if ($transcribing) {
            Stop-Transcript | Out-Null
            Write-Host "Log saved to $logPath"
        }
    }
} @args
