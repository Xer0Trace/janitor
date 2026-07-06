[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$IncludeRecycleBin,
    [switch]$IncludeComponentCleanup,
    [switch]$IncludeLooseFiles
)

$ErrorActionPreference = 'Continue'
$logPath = Join-Path $env:TEMP "Cleanup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $logPath -Append | Out-Null
Write-Host "Logging to $logPath`n"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Clear-Path {
    <#
        Removes the contents of a folder (supports wildcards). Uses robocopy /MIR
        against an empty scratch folder for speed on large/cache-heavy directories,
        falling back to Remove-Item if robocopy isn't usable for some reason.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    $targets = @()
    if ($Path -match '\*') {
        $targets = Get-Item -Path $Path -Force -ErrorAction SilentlyContinue
    } elseif (Test-Path -Path $Path) {
        $targets = @(Get-Item -Path $Path -Force)
    }

    foreach ($target in $targets) {
        if (-not (Test-Path $target.FullName)) { continue }
        if (-not $PSCmdlet.ShouldProcess($target.FullName, "Clear contents")) { continue }

        $empty = Join-Path $env:TEMP ("empty_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        try {
            & robocopy.exe $empty $target.FullName /MIR /NFL /NDL /NJH /NJS /NC /NS /R:0 /W:0 | Out-Null
        } catch {
            Get-ChildItem -Path $target.FullName -Force -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        } finally {
            Remove-Item -Path $empty -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

function Show-SummaryBox {
    param(
        [double]$StartGB,
        [double]$GainedGB,
        [double]$EndGB,
        [string]$Profiles
    )

    $sentence   = "You started with $StartGB GB, gained $GainedGB GB, for a total of $EndGB GB."
    $title      = "Cleanup Summary"
    $maxWidth   = [Math]::Max(40, [Math]::Min(120, $Host.UI.RawUI.WindowSize.Width - 2))
    $innerWidth = [Math]::Min($maxWidth - 4, [Math]::Max($sentence.Length, $title.Length))
    $width      = $innerWidth + 4
    $bar        = "-" * ($width - 2)

    function CenterLine([string]$text, [int]$width) {
        if ($text.Length -gt ($width - 2)) { $text = $text.Substring(0, $width - 5) + "..." }
        $pad   = $width - 2 - $text.Length
        $left  = [Math]::Floor($pad / 2)
        $right = $pad - $left
        "|" + (" " * $left) + $text + (" " * $right) + "|"
    }

    Write-Host ""
    Write-Host ("+" + $bar + "+")
    Write-Host (CenterLine $title $width)
    Write-Host ("|" + (" " * ($width - 2)) + "|")
    Write-Host (CenterLine $sentence $width)
    Write-Host ("+" + $bar + "+")
    Write-Host ""
    Write-Host $Profiles
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

$driveLetter = ($env:SystemDrive -replace ':$', '')
$before      = (Get-PSDrive $driveLetter).Free
$services    = @('wuauserv', 'bits')
$servicesStopped = @()

try {
    # Stop update services only long enough to clear SoftwareDistribution\Download
    foreach ($svc in $services) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq 'Running') {
            if ($PSCmdlet.ShouldProcess($svc, "Stop service")) {
                try { Stop-Service $svc -Force -ErrorAction Stop; $servicesStopped += $svc }
                catch { Write-Warning "Could not stop $svc`: $_" }
            }
        }
    }

    # -----------------------------------------------------------------------
    # System-wide cleanup
    # -----------------------------------------------------------------------
    Write-Host "Clearing system temp locations..."
    Clear-Path "C:\Windows\Temp"
    Clear-Path "C:\Windows\Prefetch"
    Clear-Path "C:\Windows\SoftwareDistribution\Download"
    Clear-Path "C:\Windows\Logs\CBS"

    if ($IncludeRecycleBin) {
        if ($PSCmdlet.ShouldProcess("Recycle Bin", "Empty")) {
            try { Clear-RecycleBin -Force -ErrorAction Stop }
            catch { Write-Warning "Could not empty Recycle Bin: $_" }
        }
    }

    # -----------------------------------------------------------------------
    # Per-user cleanup
    # -----------------------------------------------------------------------
    $profiles = Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '^(Default|All Users|Default User|Public)$' }

    Write-Host "Clearing per-user caches for $($profiles.Count) profile(s)..."

    # Data-driven list of cache targets so adding/removing one is a single line
    $cacheTemplates = @(
        '{0}\AppData\Local\Temp',
        '{0}\AppData\Local\Google\Chrome\User Data\*\Cache',
        '{0}\AppData\Local\Google\Chrome\User Data\*\Code Cache',
        '{0}\AppData\Local\Google\Chrome\User Data\*\GPUCache',
        '{0}\AppData\Local\Microsoft\Edge\User Data\*\Cache',
        '{0}\AppData\Local\Microsoft\Edge\User Data\*\Code Cache',
        '{0}\AppData\Local\Microsoft\Edge\User Data\*\GPUCache',
        '{0}\AppData\Local\Mozilla\Firefox\Profiles\*\cache2',
        '{0}\AppData\Roaming\Microsoft\Teams\Cache',
        '{0}\AppData\Roaming\Microsoft\Teams\Code Cache',
        '{0}\AppData\Roaming\Microsoft\Teams\GPUCache',
        '{0}\AppData\Roaming\Zoom\data',
        '{0}\AppData\Roaming\Zoom\bin\cef\Cache',
        '{0}\AppData\Roaming\Zoom\logs'
    )

    foreach ($p in $profiles) {
        foreach ($template in $cacheTemplates) {
            Clear-Path ($template -f $p.FullName)
        }

        if ($IncludeLooseFiles) {
            Clear-Path "$($p.FullName)\Downloads\*.tmp"
            Clear-Path "$($p.FullName)\Downloads\*.log"
            Clear-Path "$($p.FullName)\Documents\*.dmp"
        }
    }

    # -----------------------------------------------------------------------
    # Component store cleanup (optional, slow)
    # -----------------------------------------------------------------------
    if ($IncludeComponentCleanup) {
        if ($PSCmdlet.ShouldProcess("WinSxS component store", "DISM StartComponentCleanup")) {
            Write-Host "`nRunning DISM component cleanup, this can take several minutes..."
            try {
                & "$env:SystemRoot\System32\dism.exe" /Online /Cleanup-Image /StartComponentCleanup
            } catch {
                Write-Warning "DISM cleanup failed: $_"
            }
        }
    }
}
finally {
    # Always restart anything we stopped, even if the script errored above
    foreach ($svc in $servicesStopped) {
        try { Start-Service $svc -ErrorAction Stop }
        catch { Write-Warning "Could not restart $svc`: $_" }
    }
}

# ---------------------------------------------------------------------------
# Measure results
# ---------------------------------------------------------------------------

$after    = (Get-PSDrive $driveLetter).Free
$startGB  = [math]::Round($before / 1GB, 2)
$endGB    = [math]::Round($after  / 1GB, 2)
$gainedGB = [math]::Round($endGB - $startGB, 2)

Write-Host "`nMeasuring per-profile sizes in parallel..."

$jobs = foreach ($p in $profiles) {
    Start-Job -ScriptBlock {
        param($path, $name)
        try {
            # Exclude reparse points (junctions/symlinks) - old profiles can contain
            # self-referencing junctions (e.g. legacy "Application Data") that cause
            # Get-ChildItem to throw Win32Exception mid-recursion even with
            # -ErrorAction SilentlyContinue. -Ignore truly discards rather than just
            # suppressing display, which matters when running inside a job.
            $bytes = (Get-ChildItem -LiteralPath $path -Force -File -Recurse `
                        -Attributes !ReparsePoint -ErrorAction Ignore |
                      Measure-Object -Sum Length).Sum
        } catch {
            $bytes = 0
        }
        [pscustomobject]@{
            Profile = $name
            SizeGB  = [math]::Round((([double]$bytes) / 1GB), 2)
            Path    = $path
        }
    } -ArgumentList $p.FullName, $p.Name
}

$profileSizes = $jobs | Wait-Job | Receive-Job -ErrorAction SilentlyContinue
$jobs | Remove-Job -Force

$ProfileTable = $profileSizes |
    Sort-Object SizeGB -Descending |
    Format-Table -AutoSize Profile, SizeGB, Path |
    Out-String -Width 4096

Show-SummaryBox -StartGB $startGB -GainedGB $gainedGB -EndGB $endGB -Profiles $ProfileTable

Stop-Transcript | Out-Null
Write-Host "Full log saved to: $logPath"