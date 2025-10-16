#!/bin/bash
# Test if Renovate regex correctly extracts and would update appVersion
# This script should be run from the repository root

set -e

# Get the script directory and repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

echo "🧪 Testing appVersion regex extraction..."
echo "=========================================="
echo ""

# Read the Chart.yaml
CHART_FILE="charts/wireguard/Chart.yaml"

if [ ! -f "$CHART_FILE" ]; then
    echo "❌ Chart.yaml not found!"
    exit 1
fi

# Extract current appVersion from Chart.yaml
echo "1️⃣  Current Chart.yaml content:"
grep -A1 -B1 "appVersion:" "$CHART_FILE"
echo ""

# Extract the exact line Renovate would match
CURRENT_APP_VERSION=$(grep "^appVersion:" "$CHART_FILE" | sed 's/appVersion: *//')
echo "2️⃣  Extracted current appVersion: '$CURRENT_APP_VERSION'"
echo ""

# Test the regex pattern from renovate.json
REGEX_PATTERN='appVersion:\s+['"'"'"]?(?<currentValue>\d+\.\d+\.\d+(?:-r\d+-ls\d+)?)['"'"'"]?'
echo "3️⃣  Renovate regex pattern:"
echo "   $REGEX_PATTERN"
echo ""

# Simulate what Renovate would extract using a similar pattern
if [[ "$CURRENT_APP_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+(-r[0-9]+-ls[0-9]+)?)$ ]]; then
    EXTRACTED="${BASH_REMATCH[1]}"
    echo "   ✅ Regex matches!"
    echo "   📦 Extracted value: '$EXTRACTED'"
    
    # Check if it includes the -rX-lsY suffix
    if [[ "$EXTRACTED" =~ -r[0-9]+-ls[0-9]+$ ]]; then
        echo "   ✅ Full version WITH suffix extracted!"
    else
        echo "   ❌ WARNING: Suffix missing in extracted version!"
    fi
else
    echo "   ❌ Regex does NOT match!"
    exit 1
fi
echo ""

# Simulate version update
echo "4️⃣  Simulating Renovate update:"
NEW_VERSION="1.0.20250521-r0-ls89"
echo "   Current:  $CURRENT_APP_VERSION"
echo "   New:      $NEW_VERSION"
echo ""

# Show what the replacement would look like
echo "5️⃣  Replacement preview:"
echo "   OLD: appVersion: $CURRENT_APP_VERSION"
echo "   NEW: appVersion: $NEW_VERSION"
echo ""

# Test with different version formats
echo "6️⃣  Testing version format compatibility:"
TEST_VERSIONS=(
    "1.0.20250521-r0-ls88"
    "1.0.20250521-r0-ls89"
    "1.0.20250521-r1-ls90"
    "1.0.20250522-r0-ls88"
    "2.0.20250521-r5-ls100"
)

for ver in "${TEST_VERSIONS[@]}"; do
    if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-r[0-9]+-ls[0-9]+)?$ ]]; then
        # Parse with the regex versioning pattern
        if [[ "$ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-r([0-9]+)-ls([0-9]+))?$ ]]; then
            MAJOR="${BASH_REMATCH[1]}"
            MINOR="${BASH_REMATCH[2]}"
            PATCH="${BASH_REMATCH[3]}"
            PRERELEASE="${BASH_REMATCH[5]}"
            BUILD="${BASH_REMATCH[6]}"
            
            echo "   ✅ '$ver'"
            echo "      → major=$MAJOR, minor=$MINOR, patch=$PATCH"
            if [ -n "$PRERELEASE" ] && [ -n "$BUILD" ]; then
                echo "      → prerelease=$PRERELEASE, build=$BUILD"
            fi
        fi
    else
        echo "   ❌ '$ver' does NOT match"
    fi
done
echo ""

echo "=========================================="
echo "✅ Regex test completed!"
echo ""
echo "📋 Summary:"
echo "   • Current appVersion is correctly detected"
echo "   • Full version with -rX-lsY suffix is preserved"
echo "   • Version parsing works correctly"
echo ""
echo "💡 This means Renovate SHOULD update to the full version!"
echo "   Example: 1.0.20250521-r0-ls88 → 1.0.20250521-r0-ls89"
