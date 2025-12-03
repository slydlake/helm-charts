#!/bin/bash
set -e

# Set GH_TOKEN for gh CLI if GITHUB_TOKEN is available
if [ -n "$GITHUB_TOKEN" ]; then
  export GH_TOKEN=$GITHUB_TOKEN
fi

# Script to update Chart.yaml metadata after Renovate updates
# Updates:
#   - version (major/minor/patch based on dependency update type)
#   - artifacthub.io/changes
#
# Version bump logic:
#   - Direct dependencies (images, etc.):
#     - major update -> chart gets major bump
#     - minor update -> chart gets minor bump
#     - patch/digest update -> chart gets patch bump
#   - WordPress special case:
#     - minor update (e.g., 6.8 -> 6.9) -> chart gets major bump
#       (WordPress treats minor versions as major releases)
#   - Helm subchart dependencies:
#     - major update -> chart gets minor bump
#     - minor/patch update -> chart gets patch bump
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

# Function to determine version bump type from old and new versions
# Returns: major, minor, or patch
get_version_bump_type() {
  local old_version="$1"
  local new_version="$2"

  # Extract major.minor.patch - handle versions with prefixes like v1.2.3
  local old_major=$(echo "$old_version" | sed 's/^v//' | cut -d. -f1)
  local old_minor=$(echo "$old_version" | sed 's/^v//' | cut -d. -f2)
  local new_major=$(echo "$new_version" | sed 's/^v//' | cut -d. -f1)
  local new_minor=$(echo "$new_version" | sed 's/^v//' | cut -d. -f2)

  # Handle non-numeric versions gracefully
  if ! [[ "$old_major" =~ ^[0-9]+$ ]] || ! [[ "$new_major" =~ ^[0-9]+$ ]]; then
    echo "patch"
    return
  fi

  if [ "$new_major" -gt "$old_major" ] 2>/dev/null; then
    echo "major"
  elif [ "$new_minor" -gt "$old_minor" ] 2>/dev/null; then
    echo "minor"
  else
    echo "patch"
  fi
}

# Function to bump version based on type
# Args: current_version bump_type
bump_version() {
  local current="$1"
  local bump_type="$2"

  local major=$(echo "$current" | cut -d. -f1)
  local minor=$(echo "$current" | cut -d. -f2)
  local patch=$(echo "$current" | cut -d. -f3)

  case "$bump_type" in
    major)
      echo "$((major + 1)).0.0"
      ;;
    minor)
      echo "$major.$((minor + 1)).0"
      ;;
    patch|*)
      echo "$major.$minor.$((patch + 1))"
      ;;
  esac
}

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

  # Extract all dependency changes from commit messages
  # Renovate commits have format: "chore(deps): update <name> to <version>"
  DEPENDENCY_CHANGES=$(git log --oneline origin/main..HEAD | grep "chore(deps): update" | grep " to " | sed 's/.*chore(deps): update //' | sed 's/ to / /')

  # Initialize variables for version detection
  VERSION_INFO=""
  UPDATE_TYPE_INFO=""

  if [ -z "$DEPENDENCY_CHANGES" ]; then
    # Try to get from PR commits using gh CLI
    PR_NUMBER=$(echo "$PR_URL" | sed 's|.*/pull/||')
    echo "PR_NUMBER: $PR_NUMBER"
    if command -v gh >/dev/null 2>&1; then
      echo "Trying to fetch PR commits with gh..."
      PR_COMMITS=$(gh pr view "$PR_NUMBER" --json commits --jq '.commits[].message' || echo "")
      echo "PR_COMMITS: $PR_COMMITS"
      if [ -n "$PR_COMMITS" ]; then
        DEPENDENCY_CHANGES=$(echo "$PR_COMMITS" | grep "chore(deps): update" | grep " to " | sed 's/.*chore(deps): update //' | sed 's/ to / /')
      fi

      # If still no changes, try parsing PR body for the update table
      if [ -z "$DEPENDENCY_CHANGES" ]; then
        echo "Trying to parse PR body for updates..."
        PR_BODY=$(gh pr view "$PR_NUMBER" --json body --jq '.body' || echo "")
        echo "PR_BODY: $PR_BODY"
        if [ -n "$PR_BODY" ]; then
          # Extract lines starting with | and containing package info
          TABLE_LINES=$(echo "$PR_BODY" | grep '^|' | grep -v 'Package.*Update.*Change' | grep -v '^---$' | tail -n +2)  # Skip header and separator
          echo "TABLE_LINES from body: $TABLE_LINES"
          if [ -n "$TABLE_LINES" ]; then
            # Extract: package_name old_version new_version update_type
            VERSION_INFO=$(echo "$TABLE_LINES" | awk -F'|' '{
              gsub(/^[ \t]+|[ \t]+$/, "", $2);  # Package name
              gsub(/^[ \t]+|[ \t]+$/, "", $3);  # Update type (major/minor/patch)
              gsub(/^[ \t]+|[ \t]+$/, "", $4);  # Change (old -> new)
              split($4, versions, " -> ");
              old_version = versions[1];
              new_version = versions[2];
              gsub(/`/, "", old_version);
              gsub(/`/, "", new_version);
              update_type = tolower($3);
              print $2 "|" old_version "|" new_version "|" update_type
            }')
            DEPENDENCY_CHANGES=$(echo "$TABLE_LINES" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/^[ \t]+|[ \t]+$/, "", $4); split($4, versions, " -> "); new_version = versions[2]; gsub(/`/, "", new_version); print $2 " " new_version}')
          fi
        fi

        # If still no changes, try the first comment
        if [ -z "$DEPENDENCY_CHANGES" ]; then
          echo "Trying to parse first PR comment for updates..."
          FIRST_COMMENT=$(gh pr view "$PR_NUMBER" --json comments --jq '.comments[0].body' || echo "")
          echo "FIRST_COMMENT: $FIRST_COMMENT"
          if [ -n "$FIRST_COMMENT" ]; then
            TABLE_LINES=$(echo "$FIRST_COMMENT" | grep '^|' | grep -v 'Package.*Update.*Change' | grep -v '^---$' | tail -n +2)
            echo "TABLE_LINES from comment: $TABLE_LINES"
            if [ -n "$TABLE_LINES" ]; then
              VERSION_INFO=$(echo "$TABLE_LINES" | awk -F'|' '{
                gsub(/^[ \t]+|[ \t]+$/, "", $2);
                gsub(/^[ \t]+|[ \t]+$/, "", $3);
                gsub(/^[ \t]+|[ \t]+$/, "", $4);
                split($4, versions, " -> ");
                old_version = versions[1];
                new_version = versions[2];
                gsub(/`/, "", old_version);
                gsub(/`/, "", new_version);
                update_type = tolower($3);
                print $2 "|" old_version "|" new_version "|" update_type
              }')
              DEPENDENCY_CHANGES=$(echo "$TABLE_LINES" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/^[ \t]+|[ \t]+$/, "", $4); split($4, versions, " -> "); new_version = versions[2]; gsub(/`/, "", new_version); print $2 " " new_version}')
            fi
          fi
        fi
      fi
    else
      echo "gh CLI not available"
    fi
  fi

  if [ -z "$DEPENDENCY_CHANGES" ]; then
    # Fallback
    DEPENDENCY_CHANGES="Update dependencies"
  fi

  echo "Dependency changes for $CHART_DIR:"
  echo "$DEPENDENCY_CHANGES"

  # Determine the highest bump type needed
  # Priority: major > minor > patch
  HIGHEST_BUMP="patch"

  if [ -n "$VERSION_INFO" ]; then
    echo "Analyzing version changes..."
    echo "$VERSION_INFO"

    while IFS='|' read -r pkg_name old_ver new_ver update_type; do
      [ -z "$pkg_name" ] && continue

      echo "  Package: $pkg_name, Old: $old_ver, New: $new_ver, Type: $update_type"

      # Check if this is a Helm subchart dependency (listed in Chart.yaml dependencies)
      IS_SUBCHART=false
      if grep -q "name: $pkg_name" "$CHART_YAML" 2>/dev/null; then
        # Check if it's in the dependencies section
        if awk '/^dependencies:/,/^[^ ]/' "$CHART_YAML" | grep -q "name: $pkg_name"; then
          IS_SUBCHART=true
        fi
      fi

      # Determine bump type based on update type from Renovate
      if [ -n "$update_type" ]; then
        DEP_BUMP_TYPE="$update_type"
      else
        # Fallback: calculate from version numbers
        DEP_BUMP_TYPE=$(get_version_bump_type "$old_ver" "$new_ver")
      fi

      echo "  Detected bump type: $DEP_BUMP_TYPE, Is subchart: $IS_SUBCHART"

      # Special case: WordPress minor updates (e.g., 6.8 -> 6.9) should trigger a major chart bump
      # WordPress treats minor versions as major releases with potentially breaking changes
      IS_WORDPRESS_MINOR_UPDATE=false
      if echo "$pkg_name" | grep -qi "wordpress"; then
        if [ "$DEP_BUMP_TYPE" = "minor" ]; then
          IS_WORDPRESS_MINOR_UPDATE=true
          echo "  WordPress minor update detected - treating as major for chart bump"
        fi
      fi

      if [ "$IS_SUBCHART" = true ]; then
        # For Helm subcharts: major -> minor, minor/patch -> patch
        if [ "$DEP_BUMP_TYPE" = "major" ]; then
          if [ "$HIGHEST_BUMP" = "patch" ]; then
            HIGHEST_BUMP="minor"
          fi
        fi
        # For minor/patch subchart updates, keep patch (no change needed)
      else
        # For direct dependencies: major -> major, minor -> minor, patch -> patch
        # Exception: WordPress minor updates -> major chart bump
        if [ "$IS_WORDPRESS_MINOR_UPDATE" = true ]; then
          HIGHEST_BUMP="major"
        else
          case "$DEP_BUMP_TYPE" in
            major)
              HIGHEST_BUMP="major"
              ;;
            minor)
              if [ "$HIGHEST_BUMP" != "major" ]; then
                HIGHEST_BUMP="minor"
              fi
              ;;
            # patch stays as default
          esac
        fi
      fi
    done <<< "$VERSION_INFO"
  else
    # Try to extract update type from PR labels (passed via PR_LABELS env var)
    # or from PR title (Renovate format)
    if [ -n "$PR_LABELS" ]; then
      echo "Checking PR labels: $PR_LABELS"
      if echo "$PR_LABELS" | grep -qi "major"; then
        HIGHEST_BUMP="major"
      elif echo "$PR_LABELS" | grep -qi "minor"; then
        HIGHEST_BUMP="minor"
      fi
    fi

    # Fallback to PR title check
    if [ "$HIGHEST_BUMP" = "patch" ]; then
      if echo "$PR_TITLE" | grep -qi "major"; then
        HIGHEST_BUMP="major"
      elif echo "$PR_TITLE" | grep -qi "minor"; then
        HIGHEST_BUMP="minor"
      fi
    fi
  fi

  echo "Determined chart bump type: $HIGHEST_BUMP"

  # Calculate new version
  NEW_VERSION=$(bump_version "$CURRENT_VERSION" "$HIGHEST_BUMP")
  echo "New version: $NEW_VERSION"

  # Update version in Chart.yaml
  sed -i.bak "s/^version: .*/version: $NEW_VERSION/" "$CHART_YAML"

  # Note: appVersion is now managed by Renovate directly via regex manager
  # This ensures the full version tags (e.g., 1.0.20250521-r0-ls88) are preserved

  # Create new changelog entry - replace old entries with new one
  # We'll use a simple approach: find the changes section and replace everything until the next annotation
  TMP_FILE=$(mktemp)

  python3 - "$CHART_YAML" "$DEPENDENCY_CHANGES" "$PR_URL" "$TMP_FILE" <<'PYTHON_SCRIPT'
import sys
import re

chart_file = sys.argv[1]
dependency_changes = sys.argv[2]
pr_url = sys.argv[3]
tmp_file = sys.argv[4]

# Read the entire file
with open(chart_file, 'r') as f:
    content = f.read()

# Split dependency changes into list
changes_list = [change.strip() for change in dependency_changes.split('\n') if change.strip()]

# Create changelog entries
changelog_entries = []
for change in changes_list:
    if change:
        parts = change.split()
        if len(parts) >= 2:
            version = parts[-1]
            name_part = ' '.join(parts[:-1])
            # Entferne Markdown-Links und nimm den ersten Wort-Teil als Name
            name = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', name_part).split()[0]
            description = f"Update {name} to {version}"
        else:
            description = f"Update {change}"

        changelog_entries.append(f"""    - kind: changed
      description: "{description}"
      links:
        - name: Pull Request
          url: {pr_url}""")

new_changelog = f"""  artifacthub.io/changes: |
{chr(10).join(changelog_entries)}"""

# Replace the artifacthub.io/changes section
# Pattern: match from "artifacthub.io/changes:" until the next "artifacthub.io/" or end of annotations
pattern = r'(  artifacthub\.io/changes: \|(?:\n    .*)*)'

# Find and replace the changes section
updated_content = re.sub(pattern, new_changelog, content)

# Write to temporary file
with open(tmp_file, 'w') as f:
    f.write(updated_content)

print(f"✅ Updated changelog in {chart_file} with {len(changes_list)} changes")
PYTHON_SCRIPT

  # Replace original file with updated content
  mv "$TMP_FILE" "$CHART_YAML"

  echo "✅ Updated $CHART_YAML with version $NEW_VERSION"
done

echo "All charts processed successfully!"
