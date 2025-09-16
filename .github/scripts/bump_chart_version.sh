#!/bin/bash
# Bump Helm Chart version in Chart.yaml if the tag already exists on GitHub
# Usage: ./bump_chart_version.sh <chart_dir> <github_token>

set -e
CHART_DIR="$1"
GITHUB_TOKEN="$2"
REPO="slydlake/helm-charts"
CHART_YAML="$CHART_DIR/Chart.yaml"

# Get chart name and version
CHART_NAME=$(yq '.name' "$CHART_YAML")
CHART_VERSION=$(yq '.version' "$CHART_YAML")
TAG="$CHART_NAME-$CHART_VERSION"

# Check if tag exists on GitHub
TAG_EXISTS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$REPO/releases/tags/$TAG" | grep 'tag_name')

if [ -n "$TAG_EXISTS" ]; then
  echo "Tag $TAG already exists. Bumping patch version..."
  # Bump patch version
  NEW_VERSION=$(echo $CHART_VERSION | awk -F. '{OFS="."; $NF+=1; print $0}')
  yq -i ".version = \"$NEW_VERSION\"" "$CHART_YAML"
  echo "Bumped version to $NEW_VERSION"
else
  echo "Tag $TAG does not exist. No bump needed."
fi
