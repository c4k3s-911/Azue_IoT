#!/usr/bin/env bash
# =====================================================
# 0xSec.za Main Reconnaissance Pipeline
# Stealth network scanning with report generation
# =====================================================

set -euo pipefail

SCRIPT_NAME="0xsec_recon.sh"
VERSION="1.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[${SCRIPT_NAME}]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options] TARGET

Options:
  -q, --quick         Quick scan (top-100 ports)
  -s, --stealth       Stealth mode (IDS evasion)
  -f, --full          Full scan (all ports)
  -h, --help          Show this help

Examples:
  $SCRIPT_NAME target.com
  $SCRIPT_NAME -s 192.168.1.1
  $SCRIPT_NAME -f scanme.nmap.org
EOF
    exit 0
}

MODE="default"
TARGET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        -q|--quick) MODE="quick"; shift ;;
        -s|--stealth) MODE="stealth"; shift ;;
        -f|--full) MODE="full"; shift ;;
        *) TARGET="$1"; shift ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    error "No target specified"
fi

log "Starting reconnaissance: $TARGET (mode: $MODE)"

# Define scan parameters
case "$MODE" in
    quick)
        NMAP_ARGS="--top-ports 100 -sV -sC -T4"
        ;;
    stealth)
        NMAP_ARGS="-sS -T2 -n -Pn -f --data-length 200"
        ;;
    full)
        NMAP_ARGS="-sV -sC -sS -O -p- -T4"
        ;;
    *)
        NMAP_ARGS="-sV -sC -T4"
        ;;
esac

log "Nmap args: $NMAP_ARGS"

# Create output filename
OUT_FILE="${TARGET}_scan.xml"
log "Output: $OUT_FILE"

# Run nmap
if command -v nmap &>/dev/null; then
    nmap $NMAP_ARGS -oX "$OUT_FILE" "$TARGET" || error "Nmap scan failed"
else
    error "nmap not found"
fi

log "Scan complete. Generating report..."

# Generate report
if [[ -f "./report_gen.sh" ]]; then
    ./report_gen.sh -v "$OUT_FILE"
else
    log "Warning: report_gen.sh not found"
fi

log "Pipeline complete!"
exit 0
