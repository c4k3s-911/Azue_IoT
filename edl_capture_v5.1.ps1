param(
    [int]    $PollTimeoutSeconds = 60,
    [int]    $DumpWaitSeconds    = 90,
    [string] $LogPath            = ""
)

$script:Version     = "5.1"
$script:StartTime   = (Get-Date)
$script:ExitCode    = 0
$script:ka          = $null

# ---- Default log path ($PSScriptRoot from LOCAL) ----
if (-not $LogPath) {
    $LogPath = Join-Path $PSScriptRoot "edl_v5_timing.csv"
}

# ---- Ensure log dir exists ----
$logDir = Split-Path $LogPath -Parent
if ($logDir -and -not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# ---- Init log file (REPO-style CSV header) ----
"event,timestamp,duration_ms,level" | Set-Content $LogPath

function Log-Event {
    param(
        [string] $Event,
        [string] $Level = "INFO"
    )
    $ts = Get-Date -Format "HH:mm:ss.fff"
    $dur = [math]::Round(((Get-Date) - $script:StartTime).TotalMilliseconds)
    $line = "$Event,$ts,$dur,$Level"
    $line | Add-Content $LogPath
    Write-Host "[$ts] [$Level] $Event"
}

function Cleanup-Keepalive {
    if ($script:ka -and -not $script:ka.HasExited) {
        Stop-Process -Id $script:ka.Id -Force -ErrorAction SilentlyContinue
        $script:ka = $null
        Log-Event "Keepalive cleaned up" "INFO"
    }
}

# ---- Trap handlers (from LOCAL, with BreakException for Ctrl+C) ----
trap {
    Log-Event "UNHANDLED ERROR: $_" "ERROR"
    Cleanup-Keepalive
    Log-Event "Script terminated with errors" "ERROR"
    exit 1
}

trap [System.Management.Automation.BreakException] {
    Cleanup-Keepalive
    Log-Event "Script interrupted by user" "WARN"
    exit 1
}

# ---- Configuration hash (LOCAL style) ----
$cfg = @{
    WslDistro      = "Debian"
    WslUser        = "cakes"
    LogDir         = $PSScriptRoot
    DumpScript     = "edl_dump_wsl.sh"
    PollMs         = 500
    PollTimeoutSec = $PollTimeoutSeconds
    DumpWaitSec    = $DumpWaitSeconds
    Keepalive      = $true
}

# ---- Helper functions ----
function Get-WslOutput {
    param($cmd)
    $r = wsl -d $cfg.WslDistro -u $cfg.WslUser bash -l -c $cmd 2>&1
    return ($r | Out-String).Trim()
}

function Test-DevicePresent {
    param($vid, $pid)
    $pattern = "*VID_$vid*PID_$pid*"
    $d = Get-PnpDevice | Where-Object { $_.InstanceId -like $pattern -and $_.Status -eq "OK" }
    return [bool]$d
}

function Get-UsbipBusId {
    param($vid, $pid)
    $line = usbipd list | Select-String "${vid}:${pid}"
    if (-not $line) { return $null }
    $line = $line.Line.Trim()
    $busId = ($line -split '\s+', 2)[0]
    if ($busId -match '^\d+(-\d+)+$') { return $busId }
    return $null
}

function Wait-ForDevice {
    param($vid, $pid)
    $end = (Get-Date).AddSeconds($cfg.PollTimeoutSec)
    $attempt = 0
    while ((Get-Date) -lt $end) {
        $attempt++
        if (Test-DevicePresent $vid $pid) {
            Log-Event "Device $vid:$pid detected (attempt $attempt)" "INFO"
            return $true
        }
        Start-Sleep -Milliseconds $cfg.PollMs
    }
    Log-Event "Device $vid:$pid not found after $attempt attempts" "WARN"
    return $false
}

function Invoke-WslDump {
    $dumpScript = $cfg.DumpScript
    $dumpPath = "/home/$($cfg.WslUser)/$dumpScript"
    $src = Join-Path $cfg.LogDir $dumpScript

    if (Test-Path $src) {
        Log-Event "Copying EDL dump script to WSL..." "INFO"
        wsl -d $cfg.WslDistro -u $cfg.WslUser bash -l -c "cp '/mnt/d/$($src.Replace('D:\','').Replace('\','/'))' $dumpPath && chmod +x $dumpPath" 2>$null
        Log-Event "Script copied and made executable" "SUCCESS"
    }

    Log-Event "Starting WSL keepalive..." "INFO"
    if ($cfg.Keepalive) {
        $script:ka = Start-Process -WindowStyle Hidden -FilePath "wsl.exe" -ArgumentList "-d $($cfg.WslDistro)", "sleep", "9999" -PassThru
        Start-Sleep -Seconds 2
        Log-Event "Keepalive started (PID: $($script:ka.Id))" "INFO"
    }

    $resultFile = "/home/$($cfg.WslUser)/edl_result.txt"
    wsl -d $cfg.WslDistro -u $cfg.WslUser bash -l -c "nohup $dumpPath > $resultFile 2>&1 &"
    Log-Event "Dump launched, waiting up to ${DumpWaitSeconds}s..." "INFO"

    # Active completion poll (LOCAL style)
    $waited = 0
    while ($waited -lt $cfg.DumpWaitSec) {
        Start-Sleep -Seconds 5
        $waited += 5
        $running = Get-WslOutput "ps aux | grep '$dumpScript' | grep -v grep | wc -l"
        if ($running -eq "0") { break }
        Log-Event "Dump still running... ($waited/$($cfg.DumpWaitSec)s)" "INFO"
    }

    Log-Event "=== Dump Results ===" "INFO"
    $r = Get-WslOutput "cat $resultFile 2>/dev/null"
    $r -split "`n" | ForEach-Object { if ($_) { Log-Event "  $_" "INFO" } }

    Log-Event "=== WSL dump dir ===" "INFO"
    $wslOut = Get-WslOutput "ls -la /home/$($cfg.WslUser)/n950_dump/ 2>/dev/null"
    if ($wslOut) {
        $wslOut -split "`n" | ForEach-Object { if ($_) { Log-Event "  $_" "INFO" } }
    }

    Log-Event "=== Windows copy ===" "INFO"
    $winOut = Get-WslOutput "ls -la /mnt/d/$($cfg.LogDir.Replace('D:\','').Replace('\','/'))/n950_dump/ 2>/dev/null"
    if ($winOut) {
        $winOut -split "`n" | ForEach-Object { if ($_) { Log-Event "  $_" "INFO" } }
        Log-Event "Dump copied to Windows" "SUCCESS"
    }

    Cleanup-Keepalive
}

# ---- Main ----
Log-Event "=== EDL Dump v$($script:Version) Started ===" "INFO"
Log-Event "PollTimeout: ${PollTimeoutSeconds}s, DumpWait: ${DumpWaitSeconds}s" "INFO"

# Pre-copy dump script
$srcScript = Join-Path $cfg.LogDir $cfg.DumpScript
if (Test-Path $srcScript) {
    Log-Event "Copying $($cfg.DumpScript) to WSL..." "INFO"
    wsl -d $cfg.WslDistro -u $cfg.WslUser bash -l -c "cp '/mnt/d/$($srcScript.Replace('D:\','').Replace('\','/'))' ~/$($cfg.DumpScript) && chmod +x ~/$($cfg.DumpScript)" 2>$null
    Log-Event "Script copied and made executable" "SUCCESS"
} else {
    Log-Event "Dump script not found at $srcScript" "WARN"
}

# Start keepalive
if ($cfg.Keepalive) {
    Log-Event "Starting WSL keepalive..." "INFO"
    $script:ka = Start-Process -WindowStyle Hidden -FilePath "wsl.exe" -ArgumentList "-d $($cfg.WslDistro)", "sleep", "9999" -PassThru
    Start-Sleep -Seconds 2
    if ($script:ka -and -not $script:ka.HasExited) {
        Log-Event "Keepalive started (PID: $($script:ka.Id))" "INFO"
    }
}

# Send fastboot continue
Log-Event "Sending fastboot continue..." "INFO"
$continueResult = fastboot continue 2>&1
Log-Event "Fastboot continue sent" "INFO"

# ---- Multi-state POLL LOOP (LOCAL) ----
Log-Event "=== Polling for 1e0e:902b (max ${PollTimeoutSeconds}s) ===" "INFO"
$seenStates = @{}
$pollStartTime = Get-Date
$pollAttempt = 0
$attached = $false

while (-not $attached -and ((Get-Date) -lt $pollStartTime.AddSeconds($cfg.PollTimeoutSec))) {
    $pollAttempt++
    $elapsed = [math]::Round(((Get-Date) - $pollStartTime).TotalSeconds, 1)

    $states = @{
        "DIAG"      = Test-DevicePresent "1E0E" "902B"
        "FASTBOOT"  = Test-DevicePresent "18D1" "D00D"
        "QDLOADER"  = Test-DevicePresent "05C6" "9008"
    }

    $activeModes = ($states.GetEnumerator() | Where-Object { $_.Value }) | ForEach-Object { $_.Key }
    if ($activeModes.Count -gt 0) {
        $modeStr = $activeModes -join "+"
        if (-not $seenStates.ContainsKey($modeStr)) {
            $seenStates[$modeStr] = $true
            Log-Event "T+${elapsed}s: Device in $modeStr mode" "INFO"
        }

        if ($states["QDLOADER"]) {
            Log-Event "TRUE EDL MODE (05c6:9008) detected!" "SUCCESS"
            $busId = Get-UsbipBusId "05C6" "9008"
            if ($busId) {
                Log-Event "Attaching bus $busId to WSL..." "INFO"
                usbipd attach --wsl --busid $busId 2>&1 | ForEach-Object { Log-Event "  $_" "INFO" }
                $attached = $true
                Invoke-WslDump
            }
            break
        }

        if ($states["DIAG"]) {
            Log-Event "DIAG device detected via PnP (attempt $pollAttempt)" "INFO"
            Start-Sleep -Seconds 2

            $busId = Get-UsbipBusId "1E0E" "902B"
            if ($busId) {
                Log-Event "Attaching bus $busId to WSL..." "INFO"
                usbipd attach --wsl --busid $busId 2>&1 | ForEach-Object { Log-Event "  $_" "INFO" }
                Start-Sleep -Seconds 2

                $wslCheck = Get-WslOutput "lsusb | grep -i '1e0e\|902b'"
                if ($wslCheck) {
                    Log-Event "WSL confirms device: $wslCheck" "SUCCESS"
                    $attached = $true
                    Invoke-WslDump
                } else {
                    Log-Event "Device not in WSL after attach, retrying..." "WARN"
                    usbipd attach --wsl --busid $busId 2>&1 | ForEach-Object { Log-Event "  $_" "INFO" }
                    Start-Sleep -Seconds 2
                    $wslCheck = Get-WslOutput "lsusb | grep -i '1e0e\|902b'"
                    if ($wslCheck) {
                        Log-Event "WSL confirms device on retry: $wslCheck" "SUCCESS"
                        $attached = $true
                        Invoke-WslDump
                    } else {
                        Log-Event "Second attach also failed" "ERROR"
                    }
                }
            } else {
                Log-Event "DIAG found but no usbipd bus ID" "ERROR"
            }
        }
    }

    Start-Sleep -Milliseconds $cfg.PollMs
}

# ---- Finalize ----
if (-not $attached) {
    $elapsedFinal = [math]::Round(((Get-Date) - $pollStartTime).TotalSeconds, 1)
    Log-Event "TIMEOUT after ${elapsedFinal}s" "WARN"

    if ($seenStates.Keys.Count -gt 0) {
        Log-Event "States observed: $($seenStates.Keys -join ', ')" "WARN"
    } else {
        Log-Event "NO device states detected at all" "ERROR"
        Log-Event "Diagnostic: usbipd list" "INFO"
        usbipd list 2>&1 | ForEach-Object { Log-Event "  $_" "INFO" }
        Log-Event "Diagnostic: fastboot devices" "INFO"
        fastboot devices 2>&1 | ForEach-Object { Log-Event "  $_" "INFO" }
    }

    $script:ExitCode = 1
}

Cleanup-Keepalive
Log-Event "=== EDL Dump v$($script:Version) Complete ===" "INFO"
exit $script:ExitCode
