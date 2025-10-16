#!/bin/bash
# Full Renovate dry-run test (requires GitHub token)
# This script should be run from the repository root

set -e

# Get the script directory and repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

# Check if GITHUB_TOKEN is set
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN environment variable not set"
    echo ""
    echo "Please set your GitHub token:"
    echo "  export GITHUB_TOKEN=your_token_here"
    echo ""
    echo "You can create a token at: https://github.com/settings/tokens"
    echo "Required scopes: repo (full control)"
    exit 1
fi

echo "🚀 Running full Renovate dry-run..."
echo "===================================="
echo ""

# Run Renovate in dry-run mode
npx --yes renovate \
  --platform=github \
  --token="$GITHUB_TOKEN" \
  --dry-run=full \
  --log-level=debug \
  --print-config \
  slydlake/helm-charts

echo ""
echo "✅ Dry-run completed!"
echo ""
echo "Check the output above to see:"
echo "  - What dependencies were detected"
echo "  - What updates are available"
echo "  - What PRs would be created"
echo "  - Any configuration warnings/errors"
