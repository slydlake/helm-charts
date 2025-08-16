# WireGuard - Server and Client K8s

## Introduction
[WireGuard®](https://github.com/linuxserver/docker-wireguard) is an extremely simple yet fast and modern VPN that utilizes state-of-the-art cryptography.

## TL;DR

Add Repo
```bash
helm repo add slydlake https://slydlake.github.io/helm-charts
```

## Prerequistes
You have to set a namespace with privileged security:
```yaml
#namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name:  wireguard-test
  labels:
    pod-security.kubernetes.io/enforce: privileged
```
Or you can create this with:
```bash
kubectl create namespace wireguard-test && kubectl label namespace wireguard-test pod-security.kubernetes.io/enforce=privileged --overwrite
```
You can set the wg0.conf as a secret. This will use instead the wireguard.server.config or wireguard.client.config settings.

```yaml
#wireguard-test-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name:  wg-config
  namespace: wireguard-test
type: opaque
stringData:
  wg0.conf: |-
    [Interface]
    .....
```
Apply it it the cluster:
```bash
kubectl apply -f ./wireguard-test-secret.yaml
```

## Server mode
The server mode could be used with default values. You just have to enable it
```bash
helm install client slydlake/wireguard -n wireguard --set wireguard.server.enabled=true
```

## Client mode
In the client mode, you have to set a few settings. The important one is to use the secret, to set the PrivateKey, PublicKey and PresharedKey. You get these information from the WireGuard server peer conf.
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: client-secret
  namespace: wireguard-test
type: Opaque
stringData:
  PrivateKey: ...
  PublicKey: ...
  PresharedKey: ...
```
After you set the secret to your cluster you can install it like this:
```bash
helm install client slydlake/wireguard -n wireguard --set wireguard.client.enabled=true,wireguard.client.config.existingSecret=client-secret,wireguard.client.config.address="10.13.13.2/24",wireguard.client.config.endpoint="vpn.example.com:51820"
```
