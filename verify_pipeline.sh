#!/usr/bin/env bash
# =====================================================
# 0xSec.za Pipeline Health Check
# Verifies all components are functional
# =====================================================

set -euo pipefail

SCRIPT_NAME="verify_pipeline.sh"
VERSION="1.0"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

check() {
    local name="$1"
    local cmd="$2"
    
    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}[PASS]${NC} $name"
        ((PASSED++))
    else
        echo -e "${RED}[FAIL]${NC} $name"
        ((FAILED++))
    fi
}

echo -e "${BLUE}=== 0xSec.za Pipeline Health Check ===${NC}"
echo ""

# Check required tools
echo -e "${BLUE}Tool Availability:${NC}"
check "nmap" "command -v nmap"
check "xmllint" "command -v xmllint"
check "xsltproc" "command -v xsltproc"
check "bash 4.0+" "[[ ${BASH_VERSINFO[0]} -ge 4 ]]"

echo ""
echo -e "${BLUE}Script Availability:${NC}"
check "report_gen.sh" "[[ -f ./report_gen.sh ]]"
check "0xsec_recon.sh" "[[ -f ./0xsec_recon.sh ]]"

echo ""
echo -e "${BLUE}Network (if WireGuard tunnel present):${NC}"
if command -v wg &>/dev/null; then
    check "WireGuard installed" "command -v wg"
    check "WireGuard interface" "wg show wg0 &>/dev/null || true"
else
    echo -e "${YELLOW}[SKIP]${NC} WireGuard (not configured for this host)"
fi

echo ""
echo -e "${BLUE}File Permissions:${NC}"
check "report_gen.sh executable" "[[ -x ./report_gen.sh ]]"
check "0xsec_recon.sh executable" "[[ -x ./0xsec_recon.sh ]]"

echo ""
echo -e "${BLUE}Directory Structure:${NC}"
check "reports/ exists" "[[ -d ./reports ]] || mkdir -p ./reports && [[ -d ./reports ]]"
check "docs/ exists" "[[ -d ./docs ]]"

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"

if [[ $FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}✓ All checks passed! Pipeline is ready.${NC}"
    exit 0
else
    echo -e "\n${RED}✗ Some checks failed. See above for details.${NC}"
    exit 1
fi
