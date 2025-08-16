
# Installation
## Install with helm from local directory
Create a namespace e.g. wireguard-test. We have to set the label for a security override, because this is needed for server/client
```bash
kubectl create namespace wireguard-test && kubectl label namespace wireguard-test pod-security.kubernetes.io/enforce=privileged --overwrite
```

Now install with helm from the local directory. Optionally with another value file
```bash
helm install server ./wireguard -n wireguard-test -f ./wireguard/values.server.test.yaml --atomic --debug
```
Now show the information from the wireguard NOTES you see, to get the peer conf files. E.g.:
```bash
export POD=$(kubectl -n wireguard-test get pods -l "app.kubernetes.io/name=wireguard,app.kubernetes.io/instance=server" -o jsonpath='{.items[0].metadata.name}')
kubectl -n wireguard-test exec "$POD" -- sh -c 'for peer in "$@"; do echo -e "\n\n--- Peer ${peer} ---"; cat "/config/peer_${peer}/peer_${peer}.conf"; done' sh $(kubectl -n wireguard-test get pod "$POD" -o jsonpath="{.spec.containers[0].env[?(@.name=='PEERS')].value}" | jq -r -R 'split(",")[]')
```
Copy the PrivateKey,PublicKey and PresharedKey to the secret keys and apply it to the cluster e.g. (don't forget the namespace) e.g. with:
```bash
kubectl apply -f ./wireguard-test-secret.yaml
```

Now install the client:
```bash
helm install client ./wireguard -n wireguard-test -f ./wireguard/values.client.test.yaml --atomic --debug
```