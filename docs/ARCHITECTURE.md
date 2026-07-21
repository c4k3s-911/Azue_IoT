# 0xSec.za N950 Field Recon Pipeline - Architecture

## Overview

```
┌─────────────────────┐    WireGuard     ┌─────────────────────────┐
│  N950 (Field)       │ ◄──────────────► │  Home Base VPS          │
│                     │   10.8.0.0/24    │                         │
│  Termux + PRoot     │                  │  WireGuard Server       │
│  Debian container   │                  │  SSH (port 2222)        │
│                     │                  │  Report hosting         │
│  nmap / rustscan    │                  │  Client config gen      │
│  report_gen.sh      │                  │  Prometheus metrics     │
│  0xsec_recon.sh     │                  │                         │
└─────────────────────┘                  └─────────────────────────┘
```

## Key Components

### Reconnaissance Scripts
- **report_gen.sh (v2.1)** - Converts Nmap XML → Markdown with robust error handling
- **0xsec_recon.sh** - Main pipeline: selects scan mode → runs nmap → generates report
- **verify_pipeline.sh** - Health checks (tunnel, tools, connectivity)

### EDL Capture (N950 Device Extraction)
- **edl_capture_v4.ps1** - PowerShell automation for EDL mode detection and extraction

## Scan Modes

| Mode | Flag | Nmap Args | Use Case |
|------|------|-----------|----------|
| Quick | `-q` | `--top-ports 100 -sV -sC -T4` | Fast inventory |
| Default | *(none)* | `-sV -sC -T4` | Standard recon |
| Stealth | `-s` | `-sS -T2 -n -Pn -f --data-length 200` | IDS evasion |
| Full | `-f` | `-sV -sC -sS -O -p- -T4` | Deep dive |

## Security Considerations

- **Source IP Anonymization**: All scans originate from VPS public IP via WireGuard tunnel
- **N950 Protection**: Cellular/WiFi IP never directly contacts targets
- **Tunnel Verification**: Health check (`check-tunnel`) must pass before scanning
- **Opsec Guidance**: Use stealth mode (-s) for sensitive targets
- **Non-Destructive**: Termux/PRoot environment can be reset without device damage

## Report Generation Pipeline

1. **Input**: Nmap XML file (`target_scan.xml`)
2. **Validation**: XML schema check, dependency verification
3. **Extraction**: Port state parsing with error recovery
4. **Output**: Professional Markdown report with statistics
5. **Error Handling**: Per-host failure tolerance, graceful degradation

## File Locations

### N950 (Termux)
```
~/0xsec-pipeline/
  ├── report_gen.sh
  ├── 0xsec_recon.sh
  ├── verify_pipeline.sh
  └── reports/
$HOME/.wireguard/wg0.conf
```

### VPS (Home Base)
```
/etc/wireguard/wg0.conf
Client configs (current directory)
/var/www/reports/
Prometheus: port 9100
```

## Error Recovery

The pipeline gracefully handles:
- Missing or corrupted XML files
- Missing nmap/xsltproc/xmllint dependencies
- Partial scan results (one host failure doesn't stop report)
- Disk space issues
- Permission denied errors
- Network timeouts

See `report_gen.sh --force` for stubborn edge cases.
