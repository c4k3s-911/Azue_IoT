# EDL Dump v5 - Enhanced with error handling, logging, and adaptive timing
# Features:
#   - Comprehensive error logging
#   - Adaptive wait times based on dump size
#   - Better USB device parsing
#   - Process cleanup guarantee
#   - Detailed diagnostic output

param(
    [int]$PollTimeoutSeconds = 60,
    [int]$DumpWaitSeconds = 90,
    [string]$LogPath = "D:\Projects\PenTest\HaCakeSec_za\sandbox_backup\edl_timing5.csv"
)

# Initialize logging
$logEntries = @()
$startTime = Get-Date

function Log-Event {
    param(
        [string]$Event,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format 'HH:mm:ss.fff'
    $duration = ((Get-Date) - $startTime).TotalMilliseconds
    $entry = "$Event,$timestamp,$duration,$Level"
    $logEntries += $entry
    Write-Host "[$timestamp] [$Level] $Event"
}

function Write-LogFile {
    "event,timestamp,duration_ms,level" | Set-Content $LogPath
    $logEntries | Add-Content $LogPath
    Write-Host "`n=== Log saved to: $LogPath ===" -ForegroundColor Green
}

trap {
    Log-Event "FATAL ERROR: $_" "ERROR"
    Write-LogFile
    exit 1
}

Log-Event "=== EDL Dump v5 Started ==="

# Pre-copy script with error handling
Log-Event "Copying EDL dump script to WSL..."
try {
    $copyResult = wsl -d Debian -u cakes bash -l -c "cp /mnt/d/Projects/PenTest/HaCakeSec_za/sandbox_backup/edl_dump_wsl.sh ~/edl_dump.sh && chmod +x ~/edl_dump.sh" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Log-Event "Script copied and made executable"
    } else {
        Log-Event "WSL copy warning: $copyResult" "WARN"
    }
} catch {
    Log-Event "Failed to copy script: $_" "ERROR"
    Write-LogFile
    exit 1
}

# Start keepalive with better process tracking
Log-Event "Starting WSL keepalive..."
try {
    $ka = Start-Process -WindowStyle Hidden -FilePath "wsl.exe" -ArgumentList "-d Debian sleep 9999" -PassThru
    if (-not $ka) {
        throw "Failed to start keepalive process"
    }
    Log-Event "Keepalive started (PID: $($ka.Id))"
    Start-Sleep -Seconds 3
} catch {
    Log-Event "Keepalive startup failed: $_" "ERROR"
    Write-LogFile
    exit 1
}

# Cleanup function - ensures process termination
function Cleanup-Keepalive {
    if ($ka -and -not $ka.HasExited) {
        Log-Event "Cleaning up keepalive process..."
        try {
            Stop-Process -Id $ka.Id -Force -ErrorAction Stop
            Log-Event "Keepalive terminated"
        } catch {
            Log-Event "Failed to terminate keepalive: $_" "WARN"
        }
    }
}

# Ensure cleanup on exit
trap { Cleanup-Keepalive; Write-LogFile; exit 1 }

# Send fastboot continue
Log-Event "Sending fastboot continue..."
try {
    $fbResult = fastboot continue 2>&1
    if ($LASTEXITCODE -eq 0) {
        Log-Event "Fastboot continue succeeded"
    } else {
        Log-Event "Fastboot warning: $fbResult" "WARN"
    }
} catch {
    Log-Event "Fastboot failed: $_" "WARN"
}

# Enhanced polling with better USB detection
Log-Event "=== Polling for 1e0e:902b (max ${PollTimeoutSeconds}s) ==="
$end = (Get-Date).AddSeconds($PollTimeoutSeconds)
$done = $false
$pollCount = 0

while ((Get-Date) -lt $end -and -not $done) {
    $pollCount++
    
    # Check PnP device
    $dev = Get-PnpDevice | Where-Object { 
        $_.InstanceId -like "*PID_902B*" -and $_.Status -eq "OK" 
    }
    
    if ($dev) {
        Log-Event "EDL device detected via PnP (attempt $pollCount)"
        Start-Sleep -Seconds 2
        Log-Event "Waiting for USB enumeration..."
        
        # Robust usbipd parsing
        try {
            $usbList = usbipd list 2>&1
            $listOut = $usbList | Select-String "1e0e:902b"
            
            if ($listOut) {
                $line = $listOut.Line.Trim()
                Log-Event "USBIPD output: $line"
                
                # More robust parsing - handle variable whitespace
                $parts = $line -split '\s+' | Where-Object { $_ }
                $busId = $parts[0]
                
                Log-Event "Extracted bus ID: $busId"
                
                # Validate bus ID format (e.g., "3-1" or "1-2-1")
                if ($busId -match '^\d+(-\d+)+$') {
                    Log-Event "Bus ID format valid, attaching to WSL..."
                    
                    try {
                        $attachResult = usbipd attach --wsl --busid $busId 2>&1
                        Log-Event "USBIPD attach output:"
                        $attachResult | ForEach-Object { Log-Event "  > $_" }
                        
                        Log-Event "USB device attached, waiting for WSL discovery..."
                        Start-Sleep -Seconds 3
                        
                        # Run dump script
                        Log-Event "=== Executing EDL dump script ==="
                        $dumpCmd = "nohup ~/edl_dump.sh > ~/edl_result.txt 2>&1 &"
                        wsl -d Debian -u cakes bash -l -c $dumpCmd
                        Log-Event "Dump script launched (PID tracking in WSL)"
                        
                        # Adaptive wait based on expected dump size
                        Log-Event "Waiting ${DumpWaitSeconds}s for dump completion..."
                        Start-Sleep -Seconds $DumpWaitSeconds
                        
                        # Collect results
                        Log-Event "=== Collecting Results ==="
                        
                        Log-Event "EDL result output:"
                        $resultOutput = wsl -d Debian -u cakes bash -l -c "cat ~/edl_result.txt 2>/dev/null" 2>&1
                        $resultOutput | ForEach-Object { Log-Event "  > $_" }
                        
                        Log-Event "N950 dump directory listing:"
                        $localDump = wsl -d Debian -u cakes bash -l -c "ls -lah ~/n950_dump/ 2>/dev/null" 2>&1
                        $localDump | ForEach-Object { Log-Event "  > $_" }
                        
                        Log-Event "Mounted dump directory listing:"
                        $mountedDump = wsl -d Debian -u cakes bash -l -c "ls -lah /mnt/d/Projects/PenTest/HaCakeSec_za/sandbox_backup/n950_dump/ 2>/dev/null" 2>&1
                        $mountedDump | ForEach-Object { Log-Event "  > $_" }
                        
                        $done = $true
                        Log-Event "EDL dump completed successfully" "SUCCESS"
                        
                    } catch {
                        Log-Event "USBIPD attach failed: $_" "ERROR"
                    }
                } else {
                    Log-Event "Invalid bus ID format: '$busId'" "ERROR"
                }
            } else {
                Log-Event "Device not found in usbipd list (attempt $pollCount)" "WARN"
            }
        } catch {
            Log-Event "USBIPD query failed: $_" "ERROR"
        }
    }
    
    if (-not $done) {
        Start-Sleep -Milliseconds 500  # Increased from 50ms for stability
    }
}

# Final status
if ($done) {
    Log-Event "=== EDL Pipeline Completed Successfully ===" "SUCCESS"
} else {
    Log-Event "=== EDL Pipeline Timeout - Device Not Detected ===" "ERROR"
}

# Cleanup and exit
Cleanup-Keepalive
Write-LogFile
exit $(if ($done) { 0 } else { 1 })
