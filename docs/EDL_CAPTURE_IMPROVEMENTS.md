# EDL Capture Script Improvements (v4 → v5)

## Issues Fixed in v5

### 1. **Error Handling**
- **v4**: No trap handlers; script continues on errors
- **v5**: `trap` blocks ensure cleanup and exit on failures
- **Impact**: Failed operations now properly halt execution instead of silently continuing

### 2. **Process Cleanup**
- **v4**: Keepalive process only killed on timeout (line: `if (-not $done)`)
- **v5**: Dedicated `Cleanup-Keepalive` function with guaranteed termination
- **Impact**: No orphaned WSL sleep processes left running

### 3. **USB Device Parsing**
- **v4**: Regex `'^\d+-\d+$'` fails on multi-level hubs (e.g., "1-2-3")
- **v5**: Improved regex `'^\d+(-\d+)+$'` handles nested hubs
- **v5**: Strips whitespace before parsing: `$line = $listOut.Line.Trim()`
- **Impact**: Works with complex USB topologies

### 4. **Logging & Diagnostics**
- **v4**: Timestamp-only CSV; no duration tracking
- **v5**: Adds duration_ms and severity levels (INFO/WARN/ERROR/SUCCESS)
- **v5**: `Log-Event` function prefixes console output with `[$timestamp] [$Level]`
- **Impact**: Better troubleshooting when debugging timing issues

### 5. **Poll Stability**
- **v4**: 50ms sleep interval - aggressive polling
- **v5**: 500ms sleep interval - reduces CPU load
- **v5**: Poll counter tracks attempts
- **Impact**: Lower CPU usage, less likely to miss device detection

### 6. **Adaptive Parameters**
- **v5**: Accepts command-line parameters:
  ```powershell
  .\edl_capture_v5.ps1 -PollTimeoutSeconds 120 -DumpWaitSeconds 180 -LogPath "C:\logs\edl.csv"
  ```
- **Impact**: Reusable script for different scenarios

## Comparison Table

| Aspect | v4 | v5 |
|--------|----|----|
| **Error handling** | None | trap blocks |
| **Cleanup** | Timeout only | Guaranteed |
| **USB hub support** | Single level | Multi-level ✓ |
| **Logging** | Timestamp only | Timestamp + duration + level |
| **Poll interval** | 50ms | 500ms |
| **Parametrization** | None | Full ✓ |
| **Exit codes** | None | 0 = success, 1 = fail |

## Migration Guide

### Running v5

**Basic usage (same as v4):**
```powershell
.\edl_capture_v5.ps1
```

**Custom timeouts for slower connections:**
```powershell
.\edl_capture_v5.ps1 -PollTimeoutSeconds 120 -DumpWaitSeconds 180
```

**Different log location:**
```powershell
.\edl_capture_v5.ps1 -LogPath "D:\logs\edl_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
```

### Log Format (v5)

```csv
event,timestamp,duration_ms,level
=== EDL Dump v5 Started ===,14:23:45.123,0,INFO
Copying EDL dump script to WSL...,14:23:45.234,111,INFO
Script copied and made executable,14:23:45.456,333,INFO
Starting WSL keepalive...,14:23:45.567,444,INFO
Keepalive started (PID: 8192),14:23:48.890,3767,INFO
Sending fastboot continue...,14:23:48.901,3778,INFO
Fastboot continue succeeded,14:23:49.012,3889,INFO
=== Polling for 1e0e:902b (max 60s) ===,14:23:49.123,4000,INFO
EDL device detected via PnP (attempt 1),14:23:52.234,7111,INFO
```

## Recommended Next Steps

1. **Add YAML config file** for multi-device scenarios
2. **Integrate with PowerShell Desired State Configuration (DSC)** for N950 setup validation
3. **Add unit tests** for USB parsing logic
4. **Create GitHub Actions workflow** to syntax-check PowerShell on commits
