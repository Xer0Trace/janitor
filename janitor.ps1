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
 
