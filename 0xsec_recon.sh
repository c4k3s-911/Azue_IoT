#!/usr/bin/env bash
# =====================================================
# 0xSec.za Main Reconnaissance Pipeline
# Stealth network scanning with report generation
# Refined: timestamps, SCRIPT_DIR, --host-timeout, --reason
# =====================================================

set -euo pipefail

SCRIPT_NAME="0xsec_recon.sh"
VERSION="1.1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Resolve script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Trap Ctrl+C / interrupt
trap 'echo -e "\n${RED}[${SCRIPT_NAME}] Interrupted${NC}"; exit 1' INT TERM

log()    { echo -e "${BLUE}[${SCRIPT_NAME}]${NC} $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }

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
        NMAP_ARGS="--top-ports 100 -sV -sC -T4 --reason"
        ;;
    stealth)
        NMAP_ARGS="-sS -T2 -n -Pn -f --data-length 200 --host-timeout 5m --reason"
        ;;
    full)
        NMAP_ARGS="-sV -sC -sS -O -p- -T4 --reason"
        ;;
    *)
        NMAP_ARGS="-sV -sC -T4 --reason"
        ;;
esac

log "Nmap args: $NMAP_ARGS"

# Create timestamped output filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_FILE="${TARGET}_scan_${TIMESTAMP}.xml"
log "Output: $OUT_FILE"

# Run nmap
if command -v nmap &>/dev/null; then
    nmap $NMAP_ARGS -oX "$OUT_FILE" "$TARGET" || error "Nmap scan failed"
else
    error "nmap not found"
fi

log "Scan complete. Generating report..."

# Use SCRIPT_DIR for relative path to report_gen.sh
if [[ -f "$SCRIPT_DIR/report_gen.sh" ]]; then
    "$SCRIPT_DIR/report_gen.sh" -v "$OUT_FILE"
else
    warn "report_gen.sh not found at $SCRIPT_DIR/report_gen.sh"
    warn "Skipping report generation"
fi

log "Pipeline complete! Output: $OUT_FILE"
exit 0
