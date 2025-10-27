# WireGuard - Server and Client for Kubernetes

## Introduction
[WireGuard®](https://github.com/linuxserver/docker-wireguard) is an extremely simple yet fast and modern VPN that utilizes state-of-the-art cryptography.

> **Note:** Soon only OCI registries will be supported. Please migrate to this OCI-based installation method shown below.

## TL;DR

You can find different sample YAML files (server, client, client with full wg0.conf configuration) in the GitHub repo in the subfolder "samples".

> **Note:** You have to enable the server or client mode in the values wireguard.server.enable = true or wireguard.client.enable = true. By default it is false.

```yaml
# ./samples/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: wireguard
  labels:
    pod-security.kubernetes.io/enforce: privileged
```

```yaml
# ./samples/server.values.yaml
wireguard:
  timezone: "Europe/Berlin"
  server:
    enabled: true
    config:
      address: vpn.example.com
      peers: "macbook1,iphone1"
```


Install with Helm:
```bash
kubectl apply -f ./samples/namespace.yaml
helm install wireguard oci://ghcr.io/slybase/charts/wireguard --values ./samples/server.values.yaml -n wireguard
```

## Prerequisites

You have to set a namespace with privileged security (see sample namespace.yaml) or you can create it with:
```bash
kubectl create namespace wireguard && kubectl label namespace wireguard pod-security.kubernetes.io/enforce=privileged --overwrite
```

## Server mode
Sample see in TL;DR.

### Bonus
Output the created peer configurations. Just replace the "namespace" and "releasename" with your values.
```bash
export namespace=wireguard
export releasename=server

export POD=$(kubectl -n $namespace get pods -l "app.kubernetes.io/name=wireguard,app.kubernetes.io/instance=$releasename" -o jsonpath='{.items[0].metadata.name}')

kubectl -n $namespace exec "$POD" -- sh -c 'for peer in "$@"; do echo -e "\n\n--- Peer ${peer} ---"; cat "/config/peer_${peer}/peer_${peer}.conf"; done' sh $(kubectl -n $namespace get pod "$POD" -o jsonpath="{.spec.containers[0].env[?(@.name=='PEERS')].value}" | jq -r -R 'split(",")[]')
```

## Client mode
In the client mode, you have to set a few settings. The important one is to create a secret that includes privatekey, publickey and presharedkey as a key. You get this information from the WireGuard server peer conf.
You can find a sample of the secret file (in both variants) in the repo.
```yaml
# ./samples/client.secret.yaml
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

```yaml
# ./samples/client.values.yaml
wireguard:
  timezone: "Europe/Berlin"
  client:
    enabled: true
    config:
      existingSecret: "client-secret"
      persistentKeepalive: 25
      endpoint: "vpn.example.com:51820"
```

Install with Helm:
```bash
kubectl apply -f ./samples/namespace.yaml
kubectl apply -f ./samples/client.secret.yaml
helm install wireguard-client oci://ghcr.io/slybase/charts/wireguard --values ./samples/client.values.yaml -n wireguard
```


## Start up with your wg0.conf
You can set your own wg0.conf file as a secret. If you do this, this will ignore the default values wireguard.server.config or wireguard.client.config.

In this example we set up a wg0.conf for a client, but of course this could also be done for a server.

```yaml
# ./samples/clientFullConfig.secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: wg-config
  namespace: wireguard
type: Opaque
stringData:
  wg0.conf: |-
    [Interface]
    .....
```
```yaml
# ./samples/clientFullConfig.values.yaml
wireguard:
  timezone: "Europe/Berlin"
  existingSecret: "wg-config"
  client:
    enabled: true
    config:
      persistentKeepalive: 25
      endpoint: "vpn.example.com:51820"
```


Install with Helm:
```bash
kubectl apply -f ./samples/namespace.yaml
kubectl apply -f ./samples/clientFullConfig.secret.yaml
helm install wireguard-client oci://ghcr.io/slybase/charts/wireguard --values ./samples/clientFullConfig.values.yaml -n wireguard
```
