#!/bin/bash
# Generate Software Bill of Materials (SBOM) for Execution Environment
# Constitutional Article V: Zero-Trust Security - Track all components

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
SBOM_DIR="${PROJECT_ROOT}/sbom"
IMAGE_NAME="${1:-localhost/ansible-ee:latest}"
FORMATS="${2:-all}"  # all, spdx, cyclonedx, syft

echo -e "${BLUE}${BOLD}📦 Generating SBOM for Execution Environment${NC}"
echo -e "Image: ${IMAGE_NAME}"
echo -e "Format: ${FORMATS}"
echo ""

# Create SBOM directory
mkdir -p "${SBOM_DIR}"

# Check if syft is installed
if ! command -v syft &> /dev/null; then
    echo -e "${RED}❌ Error: syft is not installed${NC}"
    echo ""
    echo "Install syft:"
    echo "  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin"
    echo ""
    echo "Or with Homebrew:"
    echo "  brew install syft"
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

# Generate SBOM in different formats
echo -e "${BLUE}Generating SBOM...${NC}"

# Extract image name for filename
IMAGE_FILENAME=$(echo "${IMAGE_NAME}" | sed 's/[^a-zA-Z0-9._-]/_/g')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ "${FORMATS}" == "all" ] || [ "${FORMATS}" == "spdx" ]; then
    echo -e "${BLUE}→ Generating SPDX format...${NC}"
    syft "${IMAGE_NAME}" -o spdx-json > "${SBOM_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}.spdx.json"
    echo -e "${GREEN}✅ SPDX SBOM: ${SBOM_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}.spdx.json${NC}"
fi

if [ "${FORMATS}" == "all" ] || [ "${FORMATS}" == "cyclonedx" ]; then
    echo -e "${BLUE}→ Generating CycloneDX format...${NC}"
    syft "${IMAGE_NAME}" -o cyclonedx-json > "${SBOM_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}.cyclonedx.json"
    echo -e "${GREEN}✅ CycloneDX SBOM: ${SBOM_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}.cyclonedx.json${NC}"
fi

if [ "${FORMATS}" == "all" ] || [ "${FORMATS}" == "syft" ]; then
    echo -e "${BLUE}→ Generating Syft JSON format...${NC}"
    syft "${IMAGE_NAME}" -o syft-json > "${SBOM_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}.syft.json"
    echo -e "${GREEN}✅ Syft SBOM: ${SBOM_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}.syft.json${NC}"
fi

# Generate human-readable table
echo ""
echo -e "${BLUE}→ Generating human-readable summary...${NC}"
syft "${IMAGE_NAME}" -o table > "${SBOM_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}.txt"
echo -e "${GREEN}✅ Summary: ${SBOM_DIR}/${IMAGE_FILENAME}_${TIMESTAMP}.txt${NC}"

# Generate statistics
echo ""
echo -e "${BLUE}${BOLD}📊 SBOM Statistics${NC}"
echo ""

# Count packages by type
echo "Package counts by type:"
syft "${IMAGE_NAME}" -o json | jq -r '
  .artifacts |
  group_by(.type) |
  map({type: .[0].type, count: length}) |
  .[] |
  "  \(.type): \(.count)"
' 2>/dev/null || echo "  (statistics unavailable)"

echo ""
echo "Top packages by size:"
syft "${IMAGE_NAME}" -o json | jq -r '
  .artifacts |
  sort_by(.metadata.size) |
  reverse |
  limit(10; .[]) |
  "  \(.name) (\(.version)): \(.metadata.size // 0) bytes"
' 2>/dev/null || echo "  (size information unavailable)"

# List licenses
echo ""
echo "Licenses found:"
syft "${IMAGE_NAME}" -o json | jq -r '
  [.artifacts[].licenses[]?.value] |
  unique |
  .[] |
  "  \(.)"
' 2>/dev/null || echo "  (license information unavailable)"

echo ""
echo -e "${GREEN}${BOLD}✅ SBOM generation complete!${NC}"
echo ""
echo "Files generated in: ${SBOM_DIR}"
echo ""
echo "Next steps:"
echo "  1. Review SBOM for unexpected packages"
echo "  2. Run vulnerability scan: ./scripts/scan-vulnerabilities.sh ${IMAGE_NAME}"
echo "  3. Store SBOM in artifact repository or security platform"
echo ""
echo "Constitutional compliance:"
echo "  ✅ Article V: Zero-Trust Security - Complete component inventory"
echo "  ✅ Article IV: Production-Grade Quality - Traceable dependencies"
