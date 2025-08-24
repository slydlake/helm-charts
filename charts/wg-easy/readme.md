# wg-easy - A WireGuard server with a Web-UI for K8s

## Introduction
[wg-easy](https://github.com/wg-easy/wg-easy) is the easiest way to run WireGuard VPN + Web-based Admin UI.

## TL;DR

Add Repo
```bash
helm repo add slycharts https://slydlake.github.io/helm-charts
```

## Prerequisites
You have to set a namespace with privileged security:
```yaml
#namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name:  wg-easy
  labels:
    pod-security.kubernetes.io/enforce: privileged
```
Or you can create this with:
```bash
kubectl create namespace wg-easy && kubectl label namespace wg-easy pod-security.kubernetes.io/enforce=privileged --overwrite
```
I recommend using the Init mode to set everything once. 
Also, it's recommended to use a secret for the username and password.
You can find a sample of the secret file (for username/password and the prometheus metrics) in the repo.

```yaml
#secret.test.yaml
apiVersion: v1
kind: Secret
metadata:
  name:  wg-secret
  namespace: wg-easy
data:
  password: <password in Base64>
  username: <username in Base64>
type: Opaque
```
Apply it to the cluster:
```bash
kubectl apply -f ./wg-easy-secret.yaml
```

## Install with helm
The server mode could be used with default values and some custom settings.
```bash
helm install server slycharts/wireguard -n  wg-easy --set wg-easy.init.existingSecret="wg-secret",wg-easy.init.host="vpn.example.com",storage.storageClass="..."
```
