
# Renovate — quick guide

Renovate is configured in `renovate.json` at the repo root.

- Managers: `helm-values` (scans `charts/*/values.yaml` and `charts/*/samples/values.yaml`) and `helm` (scans `charts/*/Chart.yaml`).
- Digests: `pinDigests: true` — PRs include SHA256 digests alongside tags when available.
- Special rule: `lusotycoon/apache-exporter` updates must use `vMAJOR.MINOR.PATCH` tags (e.g. `v1.0.10`).

What to expect:
- Renovate opens PRs that update `tag:` and `digest:` in values files and chart dependency versions in `Chart.yaml`.
- Review PRs to ensure tag+digest are correct before merging.

If a values file uses an unusual layout, open a PR to adjust `renovate.json`'s `regexManagers` so Renovate can parse it.

Generated to document the current Renovate setup.
