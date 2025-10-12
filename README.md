# 🚀 SlyCharts - The sly Helm Charts

> **⚠️ IMPORTANT ANNOUNCEMENT - GitHub Pages Helm Repository Deprecation**  
> 
> **The traditional GitHub Pages Helm repository (`https://slydlake.github.io/helm-charts`) is being phased out.**
> 
> **✅ Migration Required:** Please switch to our **OCI registry** for all future installations and updates:
> ```bash
> oci://ghcr.io/slybase/charts/<chart-name>
> ```
> 
> **📅 Timeline:**
> - ✅ **Now:** OCI registry fully operational (recommended)
> - ⚠️ ** 30th November 2025:** GitHub Pages repo will be removed
> 
> **📖 [Migration Guide](#migration-from-github-pages-repo-to-oci) below**

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

### OCI Registry (✅ Recommended)

```bash
# Install directly from OCI registry
helm install wg-easy oci://ghcr.io/slybase/charts/wg-easy

# With custom values
helm install wg-easy oci://ghcr.io/slybase/charts/wg-easy \
  --values my-values.yaml
```

### Traditional Helm Repository (⚠️ Deprecated)

> **⚠️ This method is deprecated. Please use OCI registry instead.**

```bash
# Add repository (not recommended)
helm repo add slydlake https://slydlake.github.io/helm-charts
helm repo update

# Install a chart
helm install wg-easy slydlake/wg-easy
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

## 🔄 Migration from GitHub Pages Repo to OCI

### Why Migrate?

✅ **Benefits of OCI Registry:**
- 🚀 Faster chart downloads
- 🔐 Better security integration
- 📦 Industry standard (Docker-like registry)
- 🎯 Simplified authentication
- 🔄 Native Cosign signature verification

### Migration Steps

#### 1. **Remove old Helm repository** (if configured)
```bash
helm repo remove slydlake
```

#### 2. **Update your installations to OCI**

**For existing deployments:**
```bash
# Upgrade using OCI registry (preserves all settings)
helm upgrade <release-name> oci://ghcr.io/slybase/charts/<chart-name> \
  --namespace <namespace> \
  --reuse-values
```

**For new deployments:**
```bash
# Install from OCI registry
helm install <release-name> oci://ghcr.io/slybase/charts/<chart-name> \
  --namespace <namespace> \
  --values values.yaml
```

#### 3. **For FluxCD Users**

Update your `HelmRelease` resources:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: slydlake-oci
spec:
  type: oci
  url: oci://ghcr.io/slybase/charts
  interval: 5m
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: wireguard
spec:
  chart:
    spec:
      chart: wireguard
      sourceRef:
        kind: HelmRepository
        name: slydlake-oci
      verify:
        provider: cosign  # ✅ Native signature verification!
```

#### 4. **Verify Migration**
```bash
helm list -A | grep <your-release>
# Should show OCI source
```

### What Stays the Same?

- ✅ All `values.yaml` configurations
- ✅ No pod restarts needed
- ✅ Same features and functionality
- ✅ Cosign signatures (even better integrated!)

### Need Help?

- 📖 [Full OCI Guide](#oci-registry-recommended)
- 🐛 [Open an Issue](https://github.com/slydlake/helm-charts/issues)
- 💬 [Discussions](https://github.com/slydlake/helm-charts/discussions)

---

## 🔄 Release Process

Charts are automatically released on every push to `main` branch:

1. **OCI Release** (✅ Primary): Signed OCI artifacts to `ghcr.io/slybase/charts`
2. **Traditional Release** (⚠️ Deprecated): GitHub Pages (being phased out)
3. **Signing**: All charts signed with Cosign keyless signing
4. **Verification**: Automatic signature verification in CI/CD

> **Note:** The GitHub Pages Helm repository (method #2) is deprecated and will be disabled soon. All new releases prioritize OCI distribution.

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