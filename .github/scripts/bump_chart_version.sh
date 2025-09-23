#!/bin/bash
# Bump Helm Chart version in Chart.yaml if the tag already exists on GitHub
# Usage: ./bump_chart_version.sh <chart_dir> <github_token>

set -e
CHART_DIR="$1"
GITHUB_TOKEN="$2"
REPO="slydlake/helm-charts"
CHART_YAML="$CHART_DIR/Chart.yaml"
VALUES_YAML="$CHART_DIR/values.yaml"

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

  # Update artifacthub.io/images annotation
  IMAGE_REPO=$(yq '.image.repository' "$VALUES_YAML")
  IMAGE_TAG=$(yq '.image.tag' "$VALUES_YAML")
  IMAGE_DIGEST=$(yq '.image.digest' "$VALUES_YAML")
  IMAGE_NAME=$CHART_NAME

  # Construct the new images string
  NEW_IMAGES="- name: $IMAGE_NAME
  image: $IMAGE_REPO:$IMAGE_TAG@$IMAGE_DIGEST"

  yq -i ".annotations.\"artifacthub.io/images\" = \"$NEW_IMAGES\"" "$CHART_YAML"
  echo "Updated artifacthub.io/images annotation"
else
  echo "Tag $TAG does not exist. No bump needed."
fi
