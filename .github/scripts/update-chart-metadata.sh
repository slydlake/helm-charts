#!/bin/bash
set -e

# Script to update Chart.yaml metadata after Renovate updates
# Updates: version (patch +1) and artifacthub.io/changes
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
  
  # Update appVersion based on main image tag
  VALUES_YAML="$CHART_DIR/values.yaml"
  
  if [ -f "$VALUES_YAML" ]; then
    # Extract the first image tag from values.yaml (main application image)
    # This looks for the first occurrence of "tag:" under "image:" section
    MAIN_IMAGE_TAG=$(grep -A 20 '^image:' "$VALUES_YAML" | grep '^\s*tag:' | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    
    if [ -n "$MAIN_IMAGE_TAG" ]; then
      # Extract semantic version from tag (e.g., "6.8.3-php8.1-apache" -> "6.8.3")
      APP_VERSION=$(echo "$MAIN_IMAGE_TAG" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || echo "$MAIN_IMAGE_TAG")
      
      echo "Updating appVersion to: $APP_VERSION (from image tag: $MAIN_IMAGE_TAG)"
      sed -i.bak "s/^appVersion: .*/appVersion: \"$APP_VERSION\"/" "$CHART_YAML"
    else
      echo "⚠️  Could not extract main image tag from $VALUES_YAML"
    fi
  fi
  
  # Create new changelog entry
  # We need to insert it right after "artifacthub.io/changes: |"
  TMP_FILE=$(mktemp)
  
  awk -v dep="$DEPENDENCY_INFO" -v pr_url="$PR_URL" '
    /artifacthub\.io\/changes: \|/ {
      print
      print "    - kind: changed"
      print "      description: \"" dep "\""
      print "      links:"
      print "        - name: Pull Request"
      print "          url: " pr_url
      next
    }
    {print}
  ' "$CHART_YAML" > "$TMP_FILE"
  
  mv "$TMP_FILE" "$CHART_YAML"
  rm -f "${CHART_YAML}.bak"
  
  echo "✅ Updated $CHART_YAML with version $NEW_VERSION"
done

echo "All charts processed successfully!"
