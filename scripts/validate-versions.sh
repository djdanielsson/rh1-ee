#!/bin/bash
# Validate version pinning in EE dependency files
# Ensures all versions are explicitly pinned (no ranges, no "latest")

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo "🔍 Validating version pinning..."

# Check requirements.yml
if [ -f "requirements.yml" ]; then
    echo ""
    echo "Checking requirements.yml..."

    # Check for version ranges
    if grep -E "version:\s*[><=~]" requirements.yml; then
        echo -e "${RED}❌ ERROR: Version ranges found in requirements.yml${NC}"
        echo "   Use exact versions only (e.g., version: '1.0.0')"
        ERRORS=$((ERRORS + 1))
    fi

    # Check for missing versions
    COLLECTIONS_WITHOUT_VERSION=$(grep -E "^\s*-\s*name:" requirements.yml | while read -r line; do
        COLLECTION_NAME=$(echo "$line" | awk '{print $2}' | tr -d '"')
        # Check if next line has version
        LINE_NUM=$(grep -n "^\s*-\s*name:\s*$COLLECTION_NAME" requirements.yml | cut -d: -f1)
        if ! sed -n "$((LINE_NUM + 1))p" requirements.yml | grep -q "version:"; then
            echo "$COLLECTION_NAME"
        fi
    done)

    if [ -n "$COLLECTIONS_WITHOUT_VERSION" ]; then
        echo -e "${RED}❌ ERROR: Collections without version specified:${NC}"
        echo "$COLLECTIONS_WITHOUT_VERSION"
        ERRORS=$((ERRORS + 1))
    fi

    # Check for "main" or "master" branches (warn only)
    if grep -E "version:\s*(main|master)" requirements.yml; then
        echo -e "${YELLOW}⚠️  WARNING: Using branch names instead of tags${NC}"
        echo "   Consider pinning to specific Git tags for production"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# Check requirements.txt
if [ -f "requirements.txt" ]; then
    echo ""
    echo "Checking requirements.txt..."

    # Check for version ranges (warn, not error for Python packages)
    if grep -E "^[^#].*[><=~]" requirements.txt; then
        echo -e "${YELLOW}⚠️  WARNING: Version ranges found in requirements.txt${NC}"
        echo "   Consider pinning to exact versions for reproducibility"
        WARNINGS=$((WARNINGS + 1))
    fi

    # Check for unpinned packages
    UNPINNED=$(grep -E "^[^#][^=]*$" requirements.txt | grep -v "^$" || true)
    if [ -n "$UNPINNED" ]; then
        echo -e "${YELLOW}⚠️  WARNING: Unpinned packages found:${NC}"
        echo "$UNPINNED"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# Check execution-environment.yml base image
if [ -f "execution-environment.yml" ]; then
    echo ""
    echo "Checking execution-environment.yml..."

    BASE_IMAGE=$(grep -A 2 "base_image:" execution-environment.yml | grep "name:" | awk '{print $2}' | tr -d '"' || echo "")

    if [ -z "$BASE_IMAGE" ]; then
        echo -e "${RED}❌ ERROR: Base image not specified${NC}"
        ERRORS=$((ERRORS + 1))
    elif [[ "$BASE_IMAGE" == *":latest"* ]]; then
        echo -e "${RED}❌ ERROR: Base image uses :latest tag${NC}"
        echo "   Current: $BASE_IMAGE"
        echo "   Use a specific tag or digest (e.g., @sha256:abc123...)"
        ERRORS=$((ERRORS + 1))
    elif [[ "$BASE_IMAGE" != *"@"* ]] && [[ "$BASE_IMAGE" != *":"* ]]; then
        echo -e "${YELLOW}⚠️  WARNING: Base image may not be pinned${NC}"
        echo "   Current: $BASE_IMAGE"
        echo "   Consider using a digest for maximum reproducibility"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${GREEN}✅ Base image is pinned: $BASE_IMAGE${NC}"
    fi
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ All version pinning checks passed!${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Validation completed with $WARNINGS warning(s)${NC}"
    exit 0
else
    echo -e "${RED}❌ Validation failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    exit 1
fi
