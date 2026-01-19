#!/bin/bash
# Post-create script for automation-ee-example development container
# This script runs after the container is created

set -e

echo "🚀 Setting up Execution Environment development environment..."

# Install/upgrade development tools
echo "📦 Installing development tools..."

# Ensure pip is up to date
pip install --upgrade pip

# Install Ansible and builder tools
pip install \
    ansible-core>=2.15 \
    ansible-builder \
    ansible-navigator \
    ansible-lint \
    yamllint \
    pre-commit \
    detect-secrets \
    podman \
    pytest

# Install yq (YAML processor)
VERSION=v4.40.5
BINARY=yq_linux_amd64
wget -q https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O /tmp/yq
mv /tmp/yq /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# Install syft for SBOM generation
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# Install grype for vulnerability scanning
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin

# Setup pre-commit
if [ -f .pre-commit-config.yaml ]; then
    echo "🔧 Installing pre-commit hooks..."
    pre-commit install
    pre-commit install --hook-type commit-msg
fi

# Git configuration
echo "⚙️  Configuring Git..."
git config --global --add safe.directory /workspace

# Create helpful aliases
echo "📝 Setting up shell aliases..."
cat >> ~/.bashrc <<'EOF'

# Ansible Builder Aliases
alias build-ee='ansible-builder build'
alias build-ee-verbose='ansible-builder build -v 3'
alias introspect-ee='ansible-builder introspect'

# Container Aliases
alias list-images='docker images | grep -E "(REPOSITORY|ansible-ee|automation-ee)"'
alias clean-images='docker image prune -f'
alias inspect-image='docker inspect'

# Testing Aliases
alias test-ee='ansible-navigator run --mode stdout --pull-policy missing --execution-environment-image'
alias validate-ee='yamllint execution-environment.yml && ansible-builder introspect'

# SBOM & Security
alias generate-sbom='syft'
alias scan-vulnerabilities='grype'
alias scan-ee='docker images -q | xargs -I {} grype {}'

# Git Aliases
alias gs='git status'
alias gp='git pull'
alias gc='git commit'
alias gco='git checkout'

# Development Helpers
alias build-and-test='ansible-builder build && test-ee-local'
alias clean-all='docker system prune -af --volumes'
EOF

source ~/.bashrc

# Create a helper script for testing the EE
cat > /usr/local/bin/test-ee-local <<'EOF'
#!/bin/bash
# Test the locally built execution environment

if [ -z "$1" ]; then
    echo "Usage: test-ee-local <image-name>"
    echo "Example: test-ee-local localhost/ansible-ee:latest"
    exit 1
fi

IMAGE=$1

echo "Testing Execution Environment: $IMAGE"
echo ""

echo "1. Checking if image exists..."
docker image inspect $IMAGE > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Image not found: $IMAGE"
    exit 1
fi
echo "✅ Image found"
echo ""

echo "2. Testing basic ansible command..."
docker run --rm $IMAGE ansible --version
echo ""

echo "3. Listing installed collections..."
docker run --rm $IMAGE ansible-galaxy collection list
echo ""

echo "4. Checking Python packages..."
docker run --rm $IMAGE pip list
echo ""

echo "✅ Execution Environment test complete!"
EOF

chmod +x /usr/local/bin/test-ee-local

echo "✅ Execution Environment development environment ready!"
echo ""
echo "Available commands:"
echo "  - ansible-builder: Build execution environments"
echo "  - ansible-navigator: Test execution environments"
echo "  - docker/podman: Container management"
echo "  - syft: Generate SBOM (Software Bill of Materials)"
echo "  - grype: Vulnerability scanning"
echo "  - yamllint, pre-commit"
echo ""
echo "Quick commands:"
echo "  - build-ee: Build execution environment"
echo "  - validate-ee: Validate EE definition"
echo "  - test-ee-local <image>: Test built image"
echo "  - generate-sbom <image>: Generate SBOM"
echo "  - scan-vulnerabilities <image>: Scan for CVEs"
echo ""
echo "Example workflow:"
echo "  1. Edit execution-environment.yml"
echo "  2. Run: build-ee"
echo "  3. Run: test-ee-local localhost/ansible-ee:latest"
echo "  4. Run: generate-sbom localhost/ansible-ee:latest"
echo "  5. Run: scan-vulnerabilities localhost/ansible-ee:latest"
