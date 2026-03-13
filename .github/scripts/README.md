# GitHub Scripts

This directory intentionally contains only the small helper that is still needed by GitHub Actions.

## Used by GitHub Actions

### update-chart-metadata.py

Used by [.github/workflows/chart-release-metadata.yml](.github/workflows/chart-release-metadata.yml).

What it does:
- Bumps the chart version from Renovate labels.
- Rewrites the current artifacthub.io/changes block.
- Adds or removes artifacthub.io/prerelease based on the chart version.
- Prepends the new entry to the chart CHANGELOG.md.

Arguments:
- --chart-dir
- --pr-url
- --pr-labels
- --change-descriptions

Changed-chart detection is shared through [.github/actions/detect-changed-charts/action.yml](.github/actions/detect-changed-charts/action.yml), so the workflow logic stays consistent across validation, metadata generation, and OCI release.
