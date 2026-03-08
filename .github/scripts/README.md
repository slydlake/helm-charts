# GitHub Scripts

This directory contains utility and validation scripts for the repository.

## 🤖 Used by GitHub Actions

### `update-chart-metadata.sh`

**Used by:** `.github/workflows/renovate-chart-update.yml`

**What it does:**
- ✅ Bumps Chart version based on PR labels: `major` → x.0.0, `minor` → 0.x.0, `patch`/`digest`/default → 0.0.x
- ✅ Updates `artifacthub.io/changes` annotation with PR link
- ❌ Does NOT update appVersion (handled by Renovate directly)

**Environment variables:**
- `CHART_DIR` — path to the chart directory (e.g. `charts/wordpress`)
- `PR_LABELS` — comma-separated list of PR labels (e.g. `major,automerge`)

**Arguments:** `<pr-title>` `<pr-url>`

**Workflow:** Renovate PR → renovate-chart-update.yml → update-chart-metadata.sh → Chart version bump + changelog
