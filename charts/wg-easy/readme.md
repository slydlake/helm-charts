# wg-easy - A WireGuard Server with a Web-UI for Kubernetes

## Introduction
[wg-easy](https://github.com/wg-easy/wg-easy) is the easiest way to run a WireGuard VPN with a Web-based Admin UI.

> **Note:** Soon only OCI registries will be supported. Please migrate to this OCI-based installation method shown below.


## TL;DR

You can find sample YAML files in the GitHub repo in the subfolder "samples".

> **Note:** By default, the init mode (config.init.enabled) is turned on. So you have to set up the values correctly or disable it.

```yaml
# ./samples/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: wg-easy
  labels:
    pod-security.kubernetes.io/enforce: privileged
```

```yaml
# ./samples/simple.values.yaml
config:
  init:
    enabled: false
service:
  ui:
    nodePort: 30201 # port for the UI (browser)
  wireguard:
    nodePort: 30200 # port for the wireguard server (to open in firewall)
```

Install with Helm:
```bash
kubectl apply -f ./samples/namespace.yaml
helm install wgeasy oci://ghcr.io/slybase/charts/wg-easy --values ./samples/simple.values.yaml -n wg-easy
```


## Prerequisites

You have to set a namespace with privileged security (see sample namespace.yaml) or you can create it with:
```bash
kubectl create namespace wg-easy && kubectl label namespace wg-easy pod-security.kubernetes.io/enforce=privileged pod-security.kubernetes.io/warn=privileged --overwrite
```

## Initialization Mode and Metrics

To provide the secrets and values to set up init mode correctly and optionally enable the Prometheus metrics.

```yaml
# ./samples/advanced.secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: wg-metrics
  namespace: wg-easy
data:
  token: <token in Base64> # this is the token for the metrics
---
apiVersion: v1
kind: Secret
metadata:
  name: wg-secret
  namespace: wg-easy
data:
  password: <password in Base64>
  username: <username in Base64>
type: Opaque
```
> **Note:** The initial username and password is not checked for complexity. Make sure to set a long enough username and password. Otherwise, the user won't be able to log in.

> **Note:** You have to enable the Prometheus metrics in the Web UI manually and copy this token as plain text (not Base64) in the UI. This can't be done automatically. The secret here is used for the serviceMonitor, for Prometheus autodetection.

```yaml
# ./samples/advanced.values.yaml
config:
  init:
    existingSecret: "wg-secret"
    host: "vpn.example.com"
serviceMonitor:
  create: true
  existingSecret: "wg-metrics"
  existingSecretKey: "token"
service:
  ui:
    nodePort: 30201
  wireguard:
    nodePort: 30200

```

Install with Helm:
```bash
kubectl apply -f ./samples/namespace.yaml
kubectl apply -f ./samples/advanced.secrets.yaml
helm install wgeasy oci://ghcr.io/slybase/charts/wg-easy --values ./samples/advanced.values.yaml -n wg-easy
```
