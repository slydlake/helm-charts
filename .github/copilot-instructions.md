# Copilot instructions for this repo

## Big picture
- This repo is a collection of signed Helm charts for self-hosted apps; each chart is isolated under charts/<chart>/ with its own Chart.yaml, values.yaml, values.schema.json, templates/, and samples/.
- Release metadata is exposed via ArtifactHub annotations in Chart.yaml (notably artifacthub.io/changes), and chart signatures are documented in README-SIGNING.md.
- The WordPress chart is the most feature-rich and uses init containers plus ConfigMaps/Secrets for plugins, themes, MU-plugins, and custom init scripts (see charts/wordpress/README.md and samples/).

## Key workflows
- Renovate-driven dependency updates are post-processed by .github/scripts/update-chart-metadata.sh (bump chart version + update artifacthub.io/changes; appVersion is updated by Renovate regex directly).
- Local Renovate testing helpers live in .github/scripts/README.md (test-renovate.sh, test-appversion-regex.sh, test-renovate-full.sh).
- There are VS Code tasks for installing/upgrading/uninstalling test charts and running pre-commit (see workspace tasks list).

## Project-specific conventions
- Each chart has sample values in charts/<chart>/samples/ that are used for installs and doc examples; prefer updating samples alongside template/values changes.
- Chart annotations and changes log are stored in Chart.yaml, not in a separate CHANGELOG file.
- The repository distributes charts via OCI (ghcr.io/slybase/charts) and uses Cosign signatures; docs are in README.md and README-SIGNING.md.

## Integration points
- Charts integrate with Kubernetes resources defined in templates/ (Deployment/StatefulSet, Service, Ingress, HPA, PVC, ServiceMonitor), and optional monitoring/Grafana dashboards are templated when enabled.
- WordPress integrates with MariaDB (internal subchart or external DB), Memcached, and Prometheus exporters; configuration is driven from values.yaml and sample files.

## Pointers
- Repo overview and install examples: README.md
- WordPress chart patterns and samples: charts/wordpress/README.md and charts/wordpress/samples/
- Renovate metadata updater: .github/scripts/update-chart-metadata.sh
- Script usage docs: .github/scripts/README.md
