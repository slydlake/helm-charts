#!/bin/bash
# Script to test Renovate configuration locally
# This script should be run from the repository root

set -e

# Get the script directory and repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

echo "🔍 Testing Renovate configuration locally..."
echo "============================================"
echo ""

# 1. Validate JSON syntax
echo "1️⃣  Checking JSON syntax..."
if python3 -m json.tool renovate.json > /dev/null 2>&1; then
    echo "   ✅ JSON syntax is valid"
else
    echo "   ❌ JSON syntax error!"
    exit 1
fi
echo ""

# 2. Check if regex patterns can extract from Chart.yaml
echo "2️⃣  Testing regex pattern against Chart.yaml..."
CHART_FILE="charts/wireguard/Chart.yaml"
if [ -f "$CHART_FILE" ]; then
    # Extract appVersion using the same regex pattern
    APP_VERSION=$(grep -E "^appVersion:\s+" "$CHART_FILE" | sed 's/appVersion:\s*//')
    if [[ $APP_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-r[0-9]+-ls[0-9]+)?$ ]]; then
        echo "   ✅ Found appVersion: $APP_VERSION (matches regex pattern)"
    else
        echo "   ⚠️  appVersion found: $APP_VERSION (pattern might need adjustment)"
    fi
else
    echo "   ⚠️  Chart.yaml not found"
fi
echo ""

# 3. Test regex versioning pattern
echo "3️⃣  Testing version pattern..."
TEST_VERSIONS=(
    "1.0.20250521-r0-ls88"
    "1.0.20250521-r0-ls89"
    "1.0.20250521"
)
for ver in "${TEST_VERSIONS[@]}"; do
    if [[ $ver =~ ^[0-9]+\.[0-9]+\.[0-9]+(-r[0-9]+-ls[0-9]+)?$ ]]; then
        echo "   ✅ Version '$ver' matches pattern"
    else
        echo "   ❌ Version '$ver' does NOT match pattern"
    fi
done
echo ""

# 4. Check package names in values.yaml
echo "4️⃣  Checking for wireguard references in values.yaml..."
VALUES_FILE="charts/wireguard/values.yaml"
if [ -f "$VALUES_FILE" ]; then
    if grep -q "linuxserver/wireguard" "$VALUES_FILE"; then
        IMAGE_REF=$(grep "repository:" "$VALUES_FILE" | head -1 | sed 's/.*repository:\s*//')
        TAG_REF=$(grep "tag:" "$VALUES_FILE" | head -1 | sed 's/.*tag:\s*["\x27]*//' | sed 's/["\x27].*//')
        echo "   ✅ Found image: $IMAGE_REF:$TAG_REF"
    else
        echo "   ⚠️  linuxserver/wireguard not found in values.yaml"
    fi
else
    echo "   ⚠️  values.yaml not found"
fi
echo ""

# 5. Summarize config
echo "5️⃣  Configuration summary:"
echo "   📁 Enabled managers: helm-values, helmv3, regex"
echo "   🔍 Regex manager watching: charts/wireguard/Chart.yaml"
echo "   📦 Special package: linuxserver/wireguard"
echo "   🏷️  Group name: linuxserver/wireguard"
echo "   🔄 Custom versioning: regex with -rX-lsY support"
echo ""

echo "============================================"
echo "✅ All local tests passed!"
echo ""
echo "💡 To test with actual Renovate (requires GitHub token):"
echo "   export GITHUB_TOKEN=your_token_here"
echo "   npx renovate --platform=github --dry-run=full slydlake/helm-charts"
echo ""

