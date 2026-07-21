#!/usr/bin/env bash
# =====================================================
# 0xSec.za Report Generator - v2.1 (Robust Edition)
# Converts Nmap XML to clean Markdown with full error handling
# Author: Grok (refined for field use)
# =====================================================

set -euo pipefail

# --------------------------- Configuration -----------------------------
SCRIPT_NAME="report_gen.sh"
VERSION="2.1"
LOG_LEVEL="info"          # info, warn, error, debug
LOG_FILE="/tmp/${SCRIPT_NAME}.log"
VERBOSE=false
FORCE=false

# Colors for terminal (works in Termux too)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local level="$1"
    shift
    local msg="$*"
    local color="${NC}"
    case "$level" in
        error) color="${RED}";;
        warn)  color="${YELLOW}";;
        debug) color="${BLUE}";;
    esac
    echo -e "${color}[${level^^}] ${SCRIPT_NAME}: ${msg}${NC}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level^^}] ${msg}" >> "$LOG_FILE"
}

error_exit() {
    local code="$1"
    shift
    log "error" "$*"
    exit "$code"
}

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options] TARGET_XML_FILE

Options:
  -h, --help          Show this help
  -v, --verbose       Enable verbose output
  -f, --force         Force processing even if XML looks broken
  -l, --log-file FILE Set custom log file (default: $LOG_FILE)
  --version           Show version

Examples:
  $SCRIPT_NAME scanme.xml
  $SCRIPT_NAME -v /path/to/target_scan.xml
  $SCRIPT_NAME --force /path/to/partial.xml
EOF
    exit 0
}

# --------------------------- Argument Parsing -----------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -f|--force) FORCE=true; shift ;;
        -l|--log-file) LOG_FILE="$2"; shift 2 ;;
        --version) echo "$SCRIPT_NAME v$VERSION"; exit 0 ;;
        *) break ;;
    esac
done

TARGET_XML="${1:-}"
if [[ -z "$TARGET_XML" ]]; then
    log "error" "No XML file provided"
    usage
fi

# --------------------------- Validation -----------------------------
log "info" "Starting report generation for $TARGET_XML"

if [[ ! -f "$TARGET_XML" ]]; then
    error_exit 1 "XML file not found: $TARGET_XML"
fi

# Check if file is XML (mime-type check, fallback to extension)
if command -v file &>/dev/null; then
    if [[ $(file --mime-type -b "$TARGET_XML" 2>/dev/null || echo "unknown") != "application/xml" ]] && [[ "$TARGET_XML" != *.xml ]]; then
        if [[ "$FORCE" != true ]]; then
            error_exit 2 "File does not appear to be XML: $TARGET_XML (use --force to override)"
        else
            log "warn" "File MIME type not XML, forcing processing anyway"
        fi
    fi
fi

# Check dependencies
for cmd in xsltproc xmllint; do
    if ! command -v "$cmd" &>/dev/null; then
        log "error" "Missing dependency: $cmd"
        if command -v apt &>/dev/null; then
            log "info" "Install with: apt install xsltproc xmllint"
        elif command -v apk &>/dev/null; then
            log "info" "Install with: apk add xsltproc xmllint"
        fi
        error_exit 3 "Required tool $cmd not found"
    fi
done

log "debug" "All prerequisites satisfied"

# --------------------------- Main Processing -----------------------------
XML_FILE="$TARGET_XML"
MD_FILE="${XML_FILE%.xml}_report.md"

# Ensure report directory exists
REPORT_DIR=$(dirname "$MD_FILE")
if [[ ! -d "$REPORT_DIR" ]]; then
    mkdir -p "$REPORT_DIR" || error_exit 5 "Failed to create report directory: $REPORT_DIR"
    log "debug" "Created report directory: $REPORT_DIR"
fi

# Create header
{
    echo "# Recon Report: $(basename $TARGET_XML)"
    echo "## Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## Summary:"
} > "$MD_FILE" || error_exit 5 "Cannot write to $MD_FILE (permission denied or disk full?)"

# Use xmllint for reliable counts (very robust)
log "debug" "Extracting port statistics..."
open_ports_count=$(xmllint --xpath 'count(//port[state/@state="open"])' "$XML_FILE" 2>/dev/null || echo "0")
closed_ports_count=$(xmllint --xpath 'count(//port[state/@state!="open"])' "$XML_FILE" 2>/dev/null || echo "0")
total_ports=$(xmllint --xpath 'count(//port)' "$XML_FILE" 2>/dev/null || echo "0")

{
    echo "- **Open ports**: $open_ports_count"
    echo "- **Closed/Filtered ports**: $closed_ports_count"
    echo "- **Total ports scanned**: $total_ports"
    echo ""
    echo "## Port Details"
    echo ""
    echo "| Port | Protocol | State | Service | Version |"
    echo "|------|----------|-------|---------|----------|"
} >> "$MD_FILE"

# Process every host (skip broken ones gracefully)
hosts_processed=0
hosts_failed=0

log "debug" "Processing hosts from XML..."
while IFS= read -r host; do
    if [[ -z "$host" ]]; then continue; fi

    addr=$(echo "$host" | grep -oP 'addr="[^"]+"' | cut -d'"' -f2 || echo "")
    if [[ -z "$addr" ]]; then
        log "warn" "Skipping invalid host record (no address found)"
        ((hosts_failed++))
        continue
    fi

    ((hosts_processed++))
    log "debug" "Processing host: $addr"

    # Get all ports for this host
    ports_xml=$(xmllint --xpath "//host[address[@addr='$addr']]/ports/port" "$XML_FILE" 2>/dev/null || echo "")

    if [[ -z "$ports_xml" ]]; then
        if [[ "$FORCE" == true ]]; then
            log "warn" "No ports found for $addr (forcing processing)"
        else
            log "debug" "No ports found for $addr - skipping"
            continue
        fi
    fi

    # Extract each port
    echo "$ports_xml" | while IFS= read -r port_node; do
        port_id=$(echo "$port_node" | grep -oP 'portid="[^"]+"' | cut -d'"' -f2 || echo "?")
        proto=$(echo "$port_node" | grep -oP 'protocol="[^"]+"' | cut -d'"' -f2 || echo "tcp")
        state=$(echo "$port_node" | grep -oP 'state="[^"]+"' | cut -d'"' -f2 || echo "unknown")

        service_name=$(echo "$port_node" | grep -oP 'name="[^"]+"' | cut -d'"' -f2 || echo "-")
        product=$(echo "$port_node" | grep -oP 'product="[^"]*"' | cut -d'"' -f2 || echo "")
        version=$(echo "$port_node" | grep -oP 'version="[^"]*"' | cut -d'"' -f2 || echo "")

        # Combine product and version
        full_version="${product}${version:+ $version}" 
        full_version="${full_version:--}"

        if [[ "$state" == "open" ]]; then
            echo "| $port_id/$proto | tcp | **$state** | $service_name | $full_version |" >> "$MD_FILE"
        else
            echo "| $port_id/$proto | tcp | $state | $service_name | $full_version |" >> "$MD_FILE"
        fi
    done || true  # continue even if one port fails

done < <(xmllint --xpath '//host/address' "$XML_FILE" 2>/dev/null || echo "")

# Final summary
if [[ $hosts_processed -eq 0 ]]; then
    log "warn" "No hosts processed in the XML file"
    echo "" >> "$MD_FILE"
    echo "**⚠ Warning**: No valid hosts found in $TARGET_XML" >> "$MD_FILE"
    if [[ "$FORCE" != true ]]; then
        error_exit 4 "No valid hosts found (use --force to override)"
    fi
fi

# Add footer
{
    echo ""
    echo "---"
    echo ""
    echo "**Report Summary**:"
    echo "- Hosts processed: $hosts_processed"
    if [[ $hosts_failed -gt 0 ]]; then
        echo "- Hosts with errors/skipped: $hosts_failed"
    fi
    echo "- Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- Report file: $MD_FILE"
} >> "$MD_FILE"

log "info" "Report generation completed successfully"
echo -e "${GREEN}[+] Report generated: ${MD_FILE}${NC}"

if [[ $VERBOSE == true ]]; then
    echo "   Log file: $LOG_FILE"
    echo "   Hosts processed: $hosts_processed"
    echo "   Open ports: $open_ports_count"
    tail -20 "$LOG_FILE"
fi

exit 0
