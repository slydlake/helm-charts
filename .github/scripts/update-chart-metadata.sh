#!/usr/bin/env bash
set -euo pipefail

# Update Chart.yaml metadata after Renovate updates
#
# Updates:
#   - version (major/minor/patch based on Renovate PR labels)
#   - artifacthub.io/changes annotation
#
# Version bump logic (from PR labels set by Renovate):
#   - major label -> x+1.0.0
#   - minor label -> x.y+1.0
#   - patch/digest label (or no label) -> x.y.z+1
#
# Note: appVersion is managed by Renovate directly via regex manager
#
# Usage: update-chart-metadata.sh <pr-title> <pr-url>
# Env:   PR_LABELS (comma-separated), CHART_DIR (from workflow scope step)

PR_TITLE="${1:?Usage: update-chart-metadata.sh <pr-title> <pr-url>}"
PR_URL="${2:?Usage: update-chart-metadata.sh <pr-title> <pr-url>}"
CHART_DIR="${CHART_DIR:?CHART_DIR env var required}"
PR_LABELS="${PR_LABELS:-}"

CHART_YAML="$CHART_DIR/Chart.yaml"

if [[ ! -f "$CHART_YAML" ]]; then
  echo "Error: $CHART_YAML not found"
  exit 1
fi

# Determine bump type from Renovate PR labels
determine_bump_type() {
  local labels=",$PR_LABELS,"
  if [[ "$labels" == *",major,"* ]]; then
    echo "major"
  elif [[ "$labels" == *",minor,"* ]]; then
    echo "minor"
  else
    echo "patch"
  fi
}

# Bump semver
bump_version() {
  local current="$1" bump_type="$2"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$current"
  case "$bump_type" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    *)     echo "$major.$minor.$((patch + 1))" ;;
  esac
}

# Idempotency guard: skip if no new dependency changes since last metadata commit
last_meta_commit=$(git log --grep='^chore: update chart metadata$' \
  --format=%H -n 1 -- "$CHART_YAML" 2>/dev/null || true)

if [[ -n "$last_meta_commit" ]]; then
  if git diff --quiet "$last_meta_commit"..HEAD -- \
    "$CHART_DIR/values.yaml" "$CHART_YAML" "$CHART_DIR/Chart.lock" 2>/dev/null; then
    echo "No new changes since last metadata update; skipping"
    exit 0
  fi
fi

# Execute
CURRENT_VERSION=$(grep '^version:' "$CHART_YAML" | awk '{print $2}')
BUMP_TYPE=$(determine_bump_type)
NEW_VERSION=$(bump_version "$CURRENT_VERSION" "$BUMP_TYPE")

echo "Chart: $CHART_DIR"
echo "Version: $CURRENT_VERSION -> $NEW_VERSION ($BUMP_TYPE)"
echo "Labels: $PR_LABELS"

# Update version in Chart.yaml (portable sed)
if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s/^version: .*/version: $NEW_VERSION/" "$CHART_YAML"
else
  sed -i "s/^version: .*/version: $NEW_VERSION/" "$CHART_YAML"
fi

# Update artifacthub.io/changes annotation (one entry per dependency update)
python3 -c "
import re, sys, os

chart_file = sys.argv[1]
pr_title = sys.argv[2]
pr_url = sys.argv[3]

raw = os.environ.get('CHANGE_DESCRIPTIONS', '').strip()
if not raw:
    raw = pr_title
desc_list = [d.strip() for d in raw.split('\n') if d.strip()]

with open(chart_file) as f:
    content = f.read()

entries = []
for desc in desc_list:
    entries.append(
        '    - kind: changed\n'
        '      description: \"{}\"\n'
        '      links:\n'
        '        - name: Pull Request\n'
        '          url: {}'.format(desc.replace('\"', '\\\\\"'), pr_url)
    )

new_changes = '  artifacthub.io/changes: |\n' + '\n'.join(entries)

pattern = r'  artifacthub\.io/changes: \|(?:\n    .*)*'
content = re.sub(pattern, new_changes, content)

with open(chart_file, 'w') as f:
    f.write(content)
" "$CHART_YAML" "$PR_TITLE" "$PR_URL"
