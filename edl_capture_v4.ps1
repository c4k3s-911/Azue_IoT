$log="D:\Projects\PenTest\HaCakeSec_za\sandbox_backup\edl_timing4.csv"
"event,timestamp" | Set-Content $log
function t{param($e) "$e,$(Get-Date -Format 'HH:mm:ss.fff')" | Add-Content $log}

t "start"
Write-Host "=== EDL Dump v4 ==="

# Pre-copy script
wsl -d Debian -u cakes bash -l -c "cp /mnt/d/Projects/PenTest/HaCakeSec_za/sandbox_backup/edl_dump_wsl.sh ~/edl_dump.sh && chmod +x ~/edl_dump.sh" 2>$null
t "prepped"

# Keepalive
$ka = Start-Process -WindowStyle Hidden -FilePath "wsl.exe" -ArgumentList "-d Debian sleep 9999" -PassThru
Start-Sleep -Seconds 3
t "alive"

# Send continue
Write-Host "=== fastboot continue ==="
fastboot continue 2>&1 | Out-Null
t "continue"

# Poll and attach with simpler parsing
Write-Host "=== Polling for 1e0e:902b ==="
$end = (Get-Date).AddSeconds(60)
$done = $false

while ((Get-Date) -lt $end -and -not $done) {
    $dev = Get-PnpDevice | Where-Object { $_.InstanceId -like "*PID_902B*" -and $_.Status -eq "OK" }
    if ($dev) {
        t "detected"
        Write-Host "EDL detected! Waiting 2s for USB enum..."
        Start-Sleep -Seconds 2
        
        # Use regex to find bus with 1e0e:902b
        $listOut = usbipd list | Select-String "1e0e:902b"
        if ($listOut) {
            $line = $listOut.Line
            Write-Host "Line: '$line'"
            $busId = ($line -split '\s+', 2)[0]
            Write-Host "Bus: '$busId'"
            
            if ($busId -match '^\d+-\d+$') {
                t "attach"
                Write-Host "Attaching $busId to WSL..."
                usbipd attach --wsl --busid $busId 2>&1 | ForEach-Object { Write-Host "  $_" }
                
                t "attached"
                Start-Sleep -Seconds 3
                
                Write-Host "=== Running dump ==="
                wsl -d Debian -u cakes bash -l -c "nohup ~/edl_dump.sh > ~/edl_result.txt 2>&1 &"
                Write-Host "Launched, waiting 90s..."
                Start-Sleep -Seconds 90
                
                Write-Host "=== Results ==="
                wsl -d Debian -u cakes bash -l -c "cat ~/edl_result.txt 2>/dev/null" 2>&1 | ForEach-Object { Write-Host "  $_" }
                Write-Host "---"
                wsl -d Debian -u cakes bash -l -c "ls -la ~/n950_dump/ 2>/dev/null" 2>&1 | ForEach-Object { Write-Host "  $_" }
                Write-Host "---"
                wsl -d Debian -u cakes bash -l -c "ls -la /mnt/d/Projects/PenTest/HaCakeSec_za/sandbox_backup/n950_dump/ 2>/dev/null" 2>&1 | ForEach-Object { Write-Host "  $_" }
                
                $done = $true
            } else {
                Write-Host "Invalid bus ID: '$busId'"
            }
        }
    }
    Start-Sleep -Milliseconds 50
}

if (-not $done) { t "timeout"; Write-Host "TIMEOUT" }
Stop-Process -Id $ka.Id -Force -ErrorAction SilentlyContinue 2>$null
t "end"
Get-Content $log
