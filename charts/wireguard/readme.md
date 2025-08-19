# WireGuard - Server and Client for K8s

## Introduction
[WireGuard®](https://github.com/linuxserver/docker-wireguard) is an extremely simple yet fast and modern VPN that utilizes state-of-the-art cryptography.

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
  name:  wireguard
  labels:
    pod-security.kubernetes.io/enforce: privileged
```
Or you can create this with:
```bash
kubectl create namespace wireguard && kubectl label namespace wireguard pod-security.kubernetes.io/enforce=privileged --overwrite
```
You can set your own wg0.conf file as a secret. If you do this, this will ignore the wireguard.server.config or wireguard.client.config in the default values.

```yaml
#wireguard-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name:  wg-config
  namespace: wireguard
type: opaque
stringData:
  wg0.conf: |-
    [Interface]
    .....
```
Apply it it the cluster:
```bash
kubectl apply -f ./wireguard-secret.yaml
```

## Server mode
The server mode could be used with default values. You just have to enable it.
```bash
helm install server slydlake/wireguard -n wireguard --set wireguard.server.enabled=true
```

## Client mode
In the client mode, you have to set a few settings. The important one is to create a secret that includes privatekey, publickey and presharedkey as a key. You get this information from the WireGuard server peer conf.
You can find a sample of the secret file (in both variants) in the repo.
```yaml
# secret.client.test.yaml
apiVersion: v1
kind: Secret
metadata:
  name: client-secret
  namespace: wireguard
type: Opaque
stringData:
  privatekey: ...
  publickey: ...
  presharedkey: ...
```
After you apply the secret to your cluster, you can install the client like this (replace the values with yours):
```bash
helm install client slydlake/wireguard -n wireguard --set wireguard.client.enabled=true,wireguard.client.config.existingSecret=client-secret,wireguard.client.config.address="10.13.13.2/24",wireguard.client.config.endpoint="vpn.example.com:51820"
```


## Bonus
Output the created peer configurations. Just replace the "namespace" and "releasename" with your values.
```bash
export namespace=wireguard
export releasename=server

export POD=$(kubectl -n $namespace get pods -l "app.kubernetes.io/name=wireguard,app.kubernetes.io/instance=$releasename" -o jsonpath='{.items[0].metadata.name}')

kubectl -n $namespace exec "$POD" -- sh -c 'for peer in "$@"; do echo -e "\n\n--- Peer ${peer} ---"; cat "/config/peer_${peer}/peer_${peer}.conf"; done' sh $(kubectl -n $namespace get pod "$POD" -o jsonpath="{.spec.containers[0].env[?(@.name=='PEERS')].value}" | jq -r -R 'split(",")[]')
```