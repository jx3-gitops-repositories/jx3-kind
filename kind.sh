#!/usr/bin/env bash

# based on: https://github.com/cameronbraid/jx3-kind/blob/master/jx3-kind.sh
set -euo pipefail

# lets setup the hermit binaries
source ./bin/activate-hermit || true

KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-"kind"}
IP=${IP:-""}

echo "Creating kind cluster named ${KIND_CLUSTER_NAME}"

# create a cluster with the local registry enabled in containerd
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF

# lets switch to the cluster
kubectl config use-context "kind-${KIND_CLUSTER_NAME}"

kubectl cluster-info


# lets default the IP if not passed in
if [ -z "$IP" ]
then
  IP=$(kubectl get node kind-control-plane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
fi

echo "using load balancer IP ${IP}"


jx gitops requirements edit --domain "${IP}.nip.io"
jx gitops yset --path "address.from" --value ${IP} helmfiles/metallb-system/metallb-values.yaml

# lets commit the values to git
git commit -a -m "chore: update domain" || true
git push

# lets run the operator
jx admin operator --username ${GIT_USERNAME} --token ${GIT_TOKEN}
