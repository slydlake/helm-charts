#!/bin/bash
set -e

# Script to update Chart.yaml metadata after Renovate updates
# Updates: 
#   - version (patch +1)
#   - artifacthub.io/changes
#
# Note: appVersion is managed by Renovate directly via regex manager
#       to preserve full version tags (e.g., 1.0.20250521-r0-ls88)
#
# Usage:
#   Auto-detect mode: ./update-chart-metadata.sh "PR Title" "PR URL"
#   Manual mode: ./update-chart-metadata.sh "PR Title" "PR URL" "charts/wordpress"

PR_TITLE="$1"
PR_URL="$2"
MANUAL_CHART="$3"

# Find all changed Chart.yaml or values.yaml files
if [ -n "$MANUAL_CHART" ]; then
  # Manual mode - use provided chart path
  CHANGED_CHARTS="$MANUAL_CHART"
  echo "Manual mode: processing $MANUAL_CHART"
else
  # Auto mode - detect from git diff
  CHANGED_CHARTS=$(git diff --name-only origin/main...HEAD | grep 'charts/.*/values.yaml\|charts/.*/Chart.yaml' | sed 's|/values.yaml||' | sed 's|/Chart.yaml||' | sort -u)
fi

echo "Changed charts detected:"
echo "$CHANGED_CHARTS"

for CHART_DIR in $CHANGED_CHARTS; do
  CHART_YAML="$CHART_DIR/Chart.yaml"
  
  if [ ! -f "$CHART_YAML" ]; then
    echo "Skipping $CHART_DIR - no Chart.yaml found"
    continue
  fi
  
  echo "Processing $CHART_YAML..."
  
  # Get current version
  CURRENT_VERSION=$(grep '^version:' "$CHART_YAML" | awk '{print $2}')
  echo "Current version: $CURRENT_VERSION"
  
  # Increment patch version (x.x.X+1)
  NEW_VERSION=$(echo "$CURRENT_VERSION" | awk -F. '{$NF = $NF + 1;} 1' | sed 's/ /./g')
  echo "New version: $NEW_VERSION"
  
  # Extract dependency info from PR title
  # e.g., "Update dependency wordpress to v6.8.3" -> "wordpress to v6.8.3"
  DEPENDENCY_INFO=$(echo "$PR_TITLE" | sed 's/Update dependency //' | sed 's/Update //')
  
  # Update version in Chart.yaml
  sed -i.bak "s/^version: .*/version: $NEW_VERSION/" "$CHART_YAML"
  
  # Note: appVersion is now managed by Renovate directly via regex manager
  # This ensures the full version tags (e.g., 1.0.20250521-r0-ls88) are preserved
  
  # Create new changelog entry - replace old entries with new one
  # We'll use a simple approach: find the changes section and replace everything until the next annotation
  TMP_FILE=$(mktemp)
  
  python3 - "$CHART_YAML" "$DEPENDENCY_INFO" "$PR_URL" "$TMP_FILE" <<'PYTHON_SCRIPT'
import sys
import re

chart_file = sys.argv[1]
dependency_info = sys.argv[2]
pr_url = sys.argv[3]
tmp_file = sys.argv[4]

# Read the entire file
with open(chart_file, 'r') as f:
    content = f.read()

# Create the new changelog entry
new_changelog = f"""  artifacthub.io/changes: |
    - kind: changed
      description: "{dependency_info}"
      links:
        - name: Pull Request
          url: {pr_url}"""

# Replace the artifacthub.io/changes section
# Pattern: match from "artifacthub.io/changes:" until the next "artifacthub.io/" or end of annotations
pattern = r'(  artifacthub\.io/changes: \|(?:\n    .*)*)'

# Find and replace the changes section
updated_content = re.sub(pattern, new_changelog, content)

# Write to temporary file
with open(tmp_file, 'w') as f:
    f.write(updated_content)

print(f"✅ Updated changelog in {chart_file}")
PYTHON_SCRIPT

  # Replace original file with updated content
  mv "$TMP_FILE" "$CHART_YAML"
  
  echo "✅ Updated $CHART_YAML with version $NEW_VERSION"
done

echo "All charts processed successfully!"
