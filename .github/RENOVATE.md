
# Renovate — quick guide

Renovate is configured in `renovate.json` at the repo root.

- Managers: 
  - `helm-values` (scans `charts/*/values.yaml` and `charts/*/samples/values.yaml`)
  - `helm` (scans `charts/*/Chart.yaml` for dependencies)
  - `regex` (scans `charts/wireguard/Chart.yaml` for appVersion)
- Digests: `pinDigests: true` — PRs include SHA256 digests alongside tags when available.
- Special rules: 
  - `linuxserver/wireguard` updates must preserve full version tags including `-rX-lsY` suffix (e.g. `1.0.20250521-r0-ls88`).
  - `lusotycoon/apache-exporter` updates must use `vMAJOR.MINOR.PATCH` tags (e.g. `v1.0.10`).

What to expect:
- Renovate opens PRs that update `tag:`, `digest:` in values files, `appVersion:` in Chart.yaml, and chart dependency versions.
- Review PRs to ensure tag+digest are correct before merging.
- `linuxserver/wireguard` updates will include both the image tag in `values.yaml` and the `appVersion` in `Chart.yaml` in a single grouped PR.

## Testing Locally

You can validate the Renovate configuration locally before pushing:

```bash
# Quick validation (no GitHub token needed)
.github/scripts/test-renovate.sh

# Test appVersion regex extraction
.github/scripts/test-appversion-regex.sh

# Full dry-run (requires GitHub token)
export GITHUB_TOKEN=your_token
.github/scripts/test-renovate-full.sh
```

See `.github/scripts/README.md` for more details.

---

If a values file uses an unusual layout, open a PR to adjust `renovate.json`'s `regexManagers` so Renovate can parse it.

Generated to document the current Renovate setup.
