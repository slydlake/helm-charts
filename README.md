# 🚀 SlyLake Helm Charts

A collection of production-ready Helm charts for self-hosted applications, featuring **signed charts** for enhanced security.

## 🔐 Security Features

All charts in this repository are **signed with Cosign** using keyless signing for maximum security and trust:

- ✅ **Cryptographically Signed** - Every chart release is signed
- ✅ **Keyless Verification** - No private key management required  
- ✅ **FluxCD Compatible** - Native signature verification support
- ✅ **Multiple Distribution** - Available via traditional Helm repos and OCI registry

📖 **[Complete Signing & Verification Guide →](./README-SIGNING.md)**

## 📦 Available Charts

| Chart | Description | Version | Status |
|-------|-------------|---------|--------|
| [wg-easy](./charts/wg-easy/) | WireGuard VPN with web interface | ![Version](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/slydlake/helm-charts/main/charts/wg-easy/Chart.yaml&label=&query=version&prefix=v) | ✅ Signed |
| [wireguard](./charts/wireguard/) | WireGuard VPN server | ![Version](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/slydlake/helm-charts/main/charts/wireguard/Chart.yaml&label=&query=version&prefix=v) | ✅ Signed |
| [wordpress](./charts/wordpress/) | WordPress with MariaDB and Memcached | ![Version](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/slydlake/helm-charts/main/charts/wordpress/Chart.yaml&label=&query=version&prefix=v) | ✅ Signed |

## 🚀 Quick Start

### Traditional Helm Repository

```bash
# Add repository
helm repo add slydlake https://slydlake.github.io/helm-charts
helm repo update

# Install a chart
helm install wg-easy slydlake/wg-easy
```

### OCI Registry (Recommended)

```bash
# Install directly from OCI registry
helm install wg-easy oci://ghcr.io/slybase/charts/wg-easy
```

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

## 🏗️ Development

### Prerequisites

- [Helm 3.8+](https://helm.sh/docs/intro/install/)
- [Cosign](https://docs.sigstore.dev/cosign/installation/) (for verification)
- [FluxCD](https://fluxcd.io/flux/installation/) (for GitOps deployment)

### Local Testing

```bash
# Clone repository
git clone https://github.com/slydlake/helm-charts.git
cd helm-charts

# Test chart rendering
helm template charts/wg-easy

# Install locally
helm install test-release charts/wg-easy --dry-run
```

## 🔄 Release Process

Charts are automatically released on every push to `main` branch:

1. **Traditional Release**: GitHub Pages + signed bundles via Chart Releaser
2. **OCI Release**: Signed OCI artifacts to `ghcr.io/slybase/charts`
3. **Signing**: All charts signed with Cosign keyless signing
4. **Verification**: Automatic signature verification in CI/CD

## 🌟 ArtifactHub

Find these charts on [ArtifactHub](https://artifacthub.io/) with verified signatures for enhanced trust and discovery.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

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
- **Traditional Repo**: [slydlake.github.io/helm-charts](https://slydlake.github.io/helm-charts)