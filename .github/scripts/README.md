# GitHub Scripts

This directory contains utility and validation scripts for the repository.

## 🤖 Used by GitHub Actions

### `update-chart-metadata.sh`

**Used by:** `.github/workflows/renovate-chart-update.yml`

**What it does:**
- ✅ Bumps Chart version (patch +1)
- ✅ Updates `artifacthub.io/changes` annotation with PR link
- ❌ Does NOT update appVersion (handled by Renovate directly)

**Workflow:** Renovate PR → renovate-chart-update.yml → update-chart-metadata.sh → Chart version bump + changelog
