# Signed Helm Charts with FluxCD

This repository provides Helm charts that are signed with [Cosign](https://docs.sigstore.dev/cosign/overview/) for enhanced security. Charts are available through two distribution methods:

1. **Traditional Helm Repository** (GitHub Pages + Releases)
2. **OCI Registry** (GitHub Container Registry)

## 🔐 Chart Signing

All charts are signed using **keyless signing** with Sigstore/Cosign. This means:
- ✅ No private keys to manage
- ✅ Signatures are tied to GitHub identity
- ✅ Transparent and auditable signing process
- ✅ Works with FluxCD out of the box

## 📦 Available Charts

- **wg-easy** - WireGuard VPN with web interface
- **wireguard** - WireGuard VPN server
- **wordpress** - WordPress with MariaDB and Memcached

## 🚀 Usage with FluxCD

### Option 1: Traditional Helm Repository (with signature verification)

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: slydlake-charts
  namespace: flux-system
spec:
  interval: 10m
  url: https://slydlake.github.io/helm-charts
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
      version: ">=1.0.0"
      sourceRef:
        kind: HelmRepository
        name: slydlake-charts
        namespace: flux-system
      # Enable signature verification for traditional releases
      verify:
        provider: cosign
        # Uses keyless verification - no additional secrets needed
  values:
    # your values here
```

### Option 2: OCI Registry (recommended for new deployments)

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: slybase-oci-charts
  namespace: flux-system
spec:
  type: oci
  interval: 10m
  url: oci://ghcr.io/slybase/helm-charts
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
      version: ">=1.0.0"
      sourceRef:
        kind: HelmRepository
        name: slybase-oci-charts
        namespace: flux-system
      # Enable signature verification for OCI charts
      verify:
        provider: cosign
        # Keyless verification - signatures are stored in the OCI registry
  values:
    # your values here
```

## 🔍 Manual Signature Verification

### Verify Traditional Chart Signatures

```bash
# Download chart and signature bundle from GitHub release
gh release download v1.0.0 --repo slydlake/helm-charts --pattern "wg-easy-1.0.0.tgz*"

# Verify signature
cosign verify-blob wg-easy-1.0.0.tgz \
  --bundle wg-easy-1.0.0.tgz.cosign.bundle \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --certificate-identity "https://github.com/slydlake/helm-charts/.github/workflows/release.yaml@refs/heads/main"
```

### Verify OCI Chart Signatures

```bash
# Verify OCI chart signature
cosign verify ghcr.io/slybase/helm-charts/wg-easy:1.0.0 \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --certificate-identity "https://github.com/slydlake/helm-charts/.github/workflows/oci-release.yaml@refs/heads/main"
```

## 🛠️ Installation Methods

### Method 1: Traditional Helm CLI

```bash
# Add repository
helm repo add slydlake https://slydlake.github.io/helm-charts
helm repo update

# Install chart
helm install wg-easy slydlake/wg-easy --version 1.0.0
```

### Method 2: OCI with Helm CLI

```bash
# Install directly from OCI registry
helm install wg-easy oci://ghcr.io/slybase/helm-charts/wg-easy --version 1.0.0
```

### Method 3: FluxCD (Recommended)

Use the FluxCD examples above for GitOps deployment with automatic signature verification.

## 🔐 Security Features

### Keyless Signing Benefits

- **No Key Management**: No private keys to secure or rotate
- **GitHub Identity**: Signatures are tied to GitHub workflows and repository
- **Transparency**: All signatures are logged in Sigstore's transparency log
- **Immutable**: Signatures cannot be forged or modified

### FluxCD Security Integration

- **Automatic Verification**: Flux verifies signatures before deploying
- **Fail-Safe**: Deployment fails if signature verification fails
- **Zero Configuration**: No additional secrets or keys required for verification
- **Audit Trail**: All deployments are logged and traceable

## 📋 Prerequisites for FluxCD

Ensure your FluxCD installation supports Cosign verification:

```bash
# Check FluxCD version (requires v0.36.0+)
flux version

# Verify cosign support is available
kubectl get crd helmcharts.source.toolkit.fluxcd.io -o yaml | grep -A 5 verify
```

## 🚨 Troubleshooting

### Signature Verification Failed

If signature verification fails, check:

1. **FluxCD Version**: Ensure FluxCD v0.36.0 or later
2. **Network Access**: Ensure cluster can reach Sigstore services
3. **Identity String**: Verify the certificate identity matches the workflow
4. **Chart Version**: Ensure you're using a signed chart version

### Example Error Resolution

```bash
# Check HelmChart status
kubectl get helmcharts -n flux-system

# View detailed error
kubectl describe helmchart wg-easy -n flux-system

# Check FluxCD logs
kubectl logs -n flux-system deployment/source-controller
```

## 🔗 Useful Links

- [FluxCD Cosign Integration](https://fluxcd.io/flux/components/source/helmcharts/#cosign)
- [Sigstore Documentation](https://docs.sigstore.dev/)
- [Cosign Installation](https://docs.sigstore.dev/cosign/installation/)
- [Helm OCI Support](https://helm.sh/docs/topics/registries/)

## 📄 License

Charts in this repository are licensed under the MIT License. See individual chart directories for specific license information.