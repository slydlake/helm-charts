<p align="center">
  <a href="https://artifacthub.io/packages/search?org=slybase">
    <img src="https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/slybase" alt="Artifact Hub">
  </a>
</p>

# 🚀 SlyCharts - Helm charts, the sly way

A collection of production-ready Helm charts for self-hosted applications, featuring **signed charts** for enhanced security.

## 🔐 Security Features

All charts in this repository are **signed with Cosign** using keyless signing for maximum security and trust:

- ✅ **Cryptographically Signed** - Every chart release is signed
- ✅ **Keyless Verification** - No private key management required  
- ✅ **FluxCD Compatible** - Native signature verification support
- ✅ **Multiple Distribution** - Available via traditional Helm repos and OCI registry

📖 **[Complete Signing & Verification Guide →](./README-SIGNING.md)**

## 📦 Available Charts

| Chart | Description | Version | Artifact Hub |
|-------|-------------|---------|--------------|
| [wg-easy](./charts/wg-easy/) | WireGuard VPN with web interface | ![Version](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/slydlake/helm-charts/main/charts/wg-easy/Chart.yaml&label=&query=version&prefix=v) | [![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/slybase-wg-easy)](https://artifacthub.io/packages/search?repo=slybase-wg-easy) |
| [wireguard](./charts/wireguard/) | WireGuard VPN server | ![Version](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/slydlake/helm-charts/main/charts/wireguard/Chart.yaml&label=&query=version&prefix=v) | [![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/slybase-wireguard)](https://artifacthub.io/packages/search?repo=slybase-wireguard) |
| [wordpress](./charts/wordpress/) | WordPress with MariaDB and Memcached | ![Version](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/slydlake/helm-charts/main/charts/wordpress/Chart.yaml&label=&query=version&prefix=v) | [![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/slybase-wordpress)](https://artifacthub.io/packages/search?repo=slybase-wordpress) |

## 🚀 Quick Start

### Installation

> **📋 Note:** Each chart requires certain mandatory values to be installed properly. Check the chart's README for required configuration and sample values.

```bash
# Example: Install wg-easy with required values
kubectl apply -f ./samples/namespace.yaml

helm install wgeasy oci://ghcr.io/slybase/charts/wg-easy \
  --values ./samples/simple.values.yaml \
  -n wg-easy
```

📖 **Each chart includes a detailed README with:**
- Required and optional configuration values
- Sample values files for different use cases
- Step-by-step installation instructions

Check the `samples/` folder in each chart directory for ready-to-use example configurations.

### FluxCD with Signature Verification

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: slybase-oci-charts
  namespace: flux-system
spec:
  type: oci
  interval: 10m
  url: oci://ghcr.io/slybase/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: wg-easy
  namespace: default
spec:
  interval: 10m
  chart:
    spec:
      chart: wg-easy
      sourceRef:
        kind: HelmRepository
        name: slybase-oci-charts
        namespace: flux-system
      verify:
        provider: cosign # Enable signature verification
```

## 🔍 Chart Verification

Verify chart authenticity before installation:

```bash
# For OCI charts
cosign verify ghcr.io/slybase/charts/wg-easy:latest \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --certificate-identity "https://github.com/slydlake/helm-charts/.github/workflows/oci-release.yaml@refs/heads/main"

# For traditional charts (download signature bundle first)
cosign verify-blob chart.tgz \
  --bundle chart.tgz.cosign.bundle \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --certificate-identity "https://github.com/slydlake/helm-charts/.github/workflows/release.yaml@refs/heads/main"
```

## 🌟 ArtifactHub

Find these charts on [ArtifactHub](https://artifacthub.io/) with verified signatures for enhanced trust and discovery.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test your changes
5. Submit a pull request

## 🔗 Links

- **Documentation**: [Chart Signing Guide](./README-SIGNING.md)
- **Issues**: [GitHub Issues](https://github.com/slydlake/helm-charts/issues)
- **OCI Registry**: [ghcr.io/slybase/charts](https://github.com/orgs/SlyBase/packages)