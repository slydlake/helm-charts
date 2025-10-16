# GitHub Scripts

This directory contains utility and validation scripts for the repository.

## Renovate Testing Scripts

### `test-renovate.sh`

Quick local validation of Renovate configuration without requiring a GitHub token.

**Usage:**
```bash
.github/scripts/test-renovate.sh
```

**What it tests:**
- ✅ JSON syntax validation
- ✅ Regex patterns for appVersion extraction
- ✅ Version pattern matching
- ✅ Package references in values.yaml
- ✅ Configuration summary

---

### `test-appversion-regex.sh`

Detailed test of the regex pattern used to extract and update `appVersion` in `Chart.yaml`.

**Usage:**
```bash
.github/scripts/test-appversion-regex.sh
```

**What it tests:**
- ✅ Current appVersion extraction
- ✅ Regex pattern matching
- ✅ Full version with `-rX-lsY` suffix preservation
- ✅ Version component parsing (major, minor, patch, prerelease, build)
- ✅ Update simulation

---

### `test-renovate-full.sh`

Full Renovate dry-run test that simulates what Renovate would do. **Requires a GitHub token.**

**Usage:**
```bash
export GITHUB_TOKEN=ghp_your_token_here
.github/scripts/test-renovate-full.sh
```

**What it does:**
- 🔍 Scans the repository for dependencies
- 📦 Checks for available updates
- 📝 Shows what PRs would be created (dry-run only, no actual changes)
- ⚙️ Validates the complete Renovate configuration

**Getting a token:**
1. Go to https://github.com/settings/tokens
2. Generate a new token (classic)
3. Select scope: `repo` (full control of private repositories)

---

## Chart Management Scripts

### `bump_chart_version.sh`

Automatically bumps the chart version.

### `update-chart-metadata.sh`

Updates chart metadata files.

---

## Running Scripts

All scripts should be run from the **repository root**:

```bash
# From repository root
.github/scripts/test-renovate.sh

# Or make them executable and run directly
chmod +x .github/scripts/*.sh
.github/scripts/test-appversion-regex.sh
```

The scripts automatically detect the repository root and adjust paths accordingly.
