#!/bin/bash
# Scan Execution Environment for vulnerabilities
# Constitutional Article V: Zero-Trust Security - Continuous vulnerability scanning

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SCAN_DIR="${PROJECT_ROOT}/scan-results"
IMAGE_NAME="${1:-localhost/ansible-ee:latest}"
SCANNER="${2:-grype}"  # grype or trivy
FAIL_ON_SEVERITY="${3:-high}"  # critical, high, medium, low, or none

echo -e "${BLUE}${BOLD}🔍 Scanning Execution Environment for Vulnerabilities${NC}"
echo -e "Image:    ${IMAGE_NAME}"
echo -e "Scanner:  ${SCANNER}"
echo -e "Fail on:  ${FAIL_ON_SEVERITY}"
echo ""

# Create scan results directory
mkdir -p "${SCAN_DIR}"

# Check scanner availability
if [ "${SCANNER}" == "grype" ]; then
    if ! command -v grype &> /dev/null; then
        echo -e "${RED}❌ Error: grype is not installed${NC}"
        echo ""
        echo "Install grype:"
        echo "  curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin"
        echo ""
        echo "Or with Homebrew:"
        echo "  brew install grype"
        exit 1
    fi
elif [ "${SCANNER}" == "trivy" ]; then
    if ! command -v trivy &> /dev/null; then
        echo -e "${RED}❌ Error: trivy is not installed${NC}"
        echo ""
        echo "Install trivy:"
        echo "  brew install aquasecurity/trivy/trivy"
        echo ""
        echo "Or see: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
        exit 1
    fi
else
    echo -e "${RED}❌ Error: Unknown scanner '${SCANNER}'${NC}"
    echo "Supported scanners: grype, trivy"
    exit 1
fi

# Check if image exists
if ! docker image inspect "${IMAGE_NAME}" &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: Image ${IMAGE_NAME} not found locally${NC}"
    echo "Available images:"
    docker images | grep -E "(REPOSITORY|ansible-ee|automation-ee)" || echo "No relevant images found"
    echo ""
    read -p "Do you want to continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Extract image name for filename
IMAGE_FILENAME=$(echo "${IMAGE_NAME}" | sed 's/[^a-zA-Z0-9._-]/_/g')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Run vulnerability scan
echo -e "${BLUE}Running vulnerability scan...${NC}"
echo ""

SCAN_EXIT_CODE=0

if [ "${SCANNER}" == "grype" ]; then
    # Run grype scan
    echo -e "${BLUE}→ Scanning with Grype...${NC}"

    # JSON output for processing
    grype "${IMAGE_NAME}" -o json > "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_grype.json" || SCAN_EXIT_CODE=$?

    # Table output for human readability
    grype "${IMAGE_NAME}" -o table > "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_grype.txt" || true

    # SARIF output for GitHub Advanced Security
    grype "${IMAGE_NAME}" -o sarif > "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_grype.sarif" || true

    echo -e "${GREEN}✅ Scan results saved${NC}"

    # Parse results
    CRITICAL=$(jq '[.matches[] | select(.vulnerability.severity == "Critical")] | length' "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_grype.json")
    HIGH=$(jq '[.matches[] | select(.vulnerability.severity == "High")] | length' "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_grype.json")
    MEDIUM=$(jq '[.matches[] | select(.vulnerability.severity == "Medium")] | length' "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_grype.json")
    LOW=$(jq '[.matches[] | select(.vulnerability.severity == "Low")] | length' "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_grype.json")
    TOTAL=$(jq '.matches | length' "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_grype.json")

elif [ "${SCANNER}" == "trivy" ]; then
    # Run trivy scan
    echo -e "${BLUE}→ Scanning with Trivy...${NC}"

    # JSON output for processing
    trivy image --format json --output "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_trivy.json" "${IMAGE_NAME}" || SCAN_EXIT_CODE=$?

    # Table output for human readability
    trivy image --format table --output "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_trivy.txt" "${IMAGE_NAME}" || true

    # SARIF output for GitHub Advanced Security
    trivy image --format sarif --output "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_trivy.sarif" "${IMAGE_NAME}" || true

    echo -e "${GREEN}✅ Scan results saved${NC}"

    # Parse results
    CRITICAL=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_trivy.json" 2>/dev/null || echo 0)
    HIGH=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_trivy.json" 2>/dev/null || echo 0)
    MEDIUM=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity == "MEDIUM")] | length' "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_trivy.json" 2>/dev/null || echo 0)
    LOW=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity == "LOW")] | length' "${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_trivy.json" 2>/dev/null || echo 0)
    TOTAL=$((CRITICAL + HIGH + MEDIUM + LOW))
fi

# Display results
echo ""
echo -e "${BLUE}${BOLD}🔒 Vulnerability Scan Results${NC}"
echo ""
echo "┌─────────────┬───────┐"
echo "│ Severity    │ Count │"
echo "├─────────────┼───────┤"
printf "│ ${RED}Critical${NC}    │ %5d │\n" ${CRITICAL}
printf "│ ${RED}High${NC}        │ %5d │\n" ${HIGH}
printf "│ ${YELLOW}Medium${NC}      │ %5d │\n" ${MEDIUM}
printf "│ ${BLUE}Low${NC}         │ %5d │\n" ${LOW}
echo "├─────────────┼───────┤"
printf "│ ${BOLD}Total${NC}       │ %5d │\n" ${TOTAL}
echo "└─────────────┴───────┘"
echo ""

# Detailed report location
echo "Detailed reports:"
if [ "${SCANNER}" == "grype" ]; then
    echo "  JSON:  ${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_grype.json"
    echo "  Table: ${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_grype.txt"
    echo "  SARIF: ${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_grype.sarif"
else
    echo "  JSON:  ${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_trivy.json"
    echo "  Table: ${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_trivy.txt"
    echo "  SARIF: ${SCAN_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}_trivy.sarif"
fi

echo ""

# Determine if we should fail based on severity threshold
SHOULD_FAIL=false

case "${FAIL_ON_SEVERITY}" in
    critical)
        if [ ${CRITICAL} -gt 0 ]; then
            SHOULD_FAIL=true
        fi
        ;;
    high)
        if [ ${CRITICAL} -gt 0 ] || [ ${HIGH} -gt 0 ]; then
            SHOULD_FAIL=true
        fi
        ;;
    medium)
        if [ ${CRITICAL} -gt 0 ] || [ ${HIGH} -gt 0 ] || [ ${MEDIUM} -gt 0 ]; then
            SHOULD_FAIL=true
        fi
        ;;
    low)
        if [ ${TOTAL} -gt 0 ]; then
            SHOULD_FAIL=true
        fi
        ;;
    none)
        SHOULD_FAIL=false
        ;;
esac

# Final status
if [ "${SHOULD_FAIL}" == "true" ]; then
    echo -e "${RED}${BOLD}❌ Vulnerability scan failed${NC}"
    echo -e "Found vulnerabilities at or above '${FAIL_ON_SEVERITY}' severity threshold"
    echo ""
    echo "Recommended actions:"
    echo "  1. Review vulnerability details in scan reports"
    echo "  2. Update base image or dependencies"
    echo "  3. Apply security patches"
    echo "  4. Consider using a different base image"
    echo ""
    exit 1
else
    if [ ${TOTAL} -gt 0 ]; then
        echo -e "${YELLOW}${BOLD}⚠️  Vulnerabilities found but below fail threshold${NC}"
        echo ""
        echo "Consider addressing these vulnerabilities:"
        echo "  1. Review scan reports for details"
        echo "  2. Plan updates for next release"
        echo "  3. Document accepted risks"
        echo ""
    else
        echo -e "${GREEN}${BOLD}✅ No vulnerabilities found!${NC}"
        echo ""
    fi

    echo "Constitutional compliance:"
    echo "  ✅ Article V: Zero-Trust Security - Vulnerability scanning complete"
    echo "  ✅ Article IV: Production-Grade Quality - Security validated"
    echo ""

    exit 0
fi
