#!/usr/bin/env bash

# based on: https://github.com/cameronbraid/jx3-kind/blob/master/jx3-kind.sh

{
set -euo pipefail

COMMAND=${1:-'help'}

DIR="$(pwd)/downloads"
mkdir -p $DIR
#DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

reg_name='kind-registry'
reg_port='5000'

# NOTE we need IP / SUBNET/ GATEWAY
SUBNET=${SUBNET:-"172.21.0.0/16"}
GATEWAY=${GATEWAY:-"172.21.0.1"}

PLATFORM=${PLATFORM:-"linux"} # use darwin for macOs

NAME=${NAME:-"kind"}
TOKEN=${TOKEN:-}

BOT_USER="${BOT_USER:-jenkins-x-test-bot}"
BOT_PASS="${BOT_PASS:-jenkins-x-test-bot}"

export DEVELOPER_USER="developer"
export DEVELOPER_PASS="developer"

ORG="${ORG:-coders}"
TEST_NAME="${TEST_NAME:-test-create-spring}"

DEV_CLUSTER_REPOSITORY="${DEV_CLUSTER_REPOSITORY:-https://github.com/jx3-gitops-repositories/jx3-kind}"

DOCKER_NETWORK_NAME=${DOCKER_NETWORK_NAME:-"${reg_name}"}
KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-"${NAME}"}

# versions
KIND_VERSION=${KIND_VERSION:-"0.10.0"}
JX_VERSION=${JX_VERSION:-"3.1.302"}
KUBECTL_VERSION=${KUBECTL_VERSION:-"1.20.0"}
YQ_VERSION=${YQ_VERSION:-"4.2.0"}

LOG_TIMESTAMPS=${LOG_TIMESTAMPS:-"true"}
LOG_FILE=${LOG_FILE:-"log"}
LOG=${LOG:-"console"} #or file


GITEA_ADMIN_PASSWORD=${GITEA_ADMIN_PASSWORD:-"abcdEFGH"}


# thanks https://stackoverflow.com/questions/33056385/increment-ip-address-in-a-shell-script#43196141
nextip(){
  IP=$1
  IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo $IP | sed -e 's/\./ /g'`)
  NEXT_IP_HEX=$(printf %.8X `echo $(( 0x$IP_HEX + 1 ))`)
  NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo $NEXT_IP_HEX | sed -r 's/(..)/0x\1 /g'`)
  echo "$NEXT_IP"
}


IP="${IP:-}"
if [[ "$IP" == "" ]]; then
    echo "Creating IP"
    IP=`nextip $GATEWAY`
fi

echo "using IP: $IP"

export GIT_SCHEME="http"
#export GIT_HOST=${GIT_HOST:-"gitea.${IP}.nip.io"}
#export GIT_URL="${GIT_SCHEME}://${GIT_HOST}"
#export GIT_HOST=${GIT_HOST:-"127.0.0.1:3000"}
export GIT_HOST=${GIT_HOST:-"localhost:3000"}
export GIT_URL="${GIT_SCHEME}://${GIT_HOST}"
export GIT_KIND="gitea"

export INTERNAL_GIT_URL="http://gitea-http.gitea:3000"



# write message to console and log
info() {
  prefix=""
  if [[ "${LOG_TIMESTAMPS}" == "true" ]]; then
    prefix="$(date '+%Y-%m-%d %H:%M:%S') "
  fi
  if [[ "${LOG}" == "file" ]]; then
    echo -e "${prefix}$@" >&3
    echo -e "${prefix}$@"
  else
    echo -e "${prefix}$@"
  fi
}

# write to console and store some information for error reporting
STEP=""
SUB_STEP=""
step() {
  STEP="$@"
  SUB_STEP=""
  info
  info "[$STEP]"
}

# store some additional information for error reporting
substep() {
  SUB_STEP="$@"
  info " - $SUB_STEP"
}

err() {
  if [[ "$STEP" == "" ]]; then
      echo "Failed running: ${BASH_COMMAND}"
      exit 1
  else
    if [[ "$SUB_STEP" != "" ]]; then
      echo "Failed at [$STEP / $SUB_STEP] running : ${BASH_COMMAND}"
      exit 1
    else
      echo "Failed at [$STEP] running : ${BASH_COMMAND}"
      exit 1
    fi
  fi
}


FILE_GITEA_VALUES_YAML=`cat <<EOF
service:
  http:
    clusterIP: ""
gitea:
  admin:
    password: ${GITEA_ADMIN_PASSWORD}
  config:
    database:
      DB_TYPE: sqlite3
      ## Note that the intit script checks to see if the IP & port of the database service is accessible, so make sure you set those to something that resolves as successful (since sqlite uses files on disk setting the port & ip won't affect the running of gitea).
      HOST: ${IP}:80 # point to the nginx ingress
    service:
      DISABLE_REGISTRATION: true
  database:
    builtIn:
      postgresql:
        enabled: false
image:
  version: 1.13.0
EOF
`


FILE_USER_JSON=`cat << 'EOF'
{
  "admin": true,
  "email": "developer@example.com",
  "full_name": "full_name",
  "login_name": "login_name",
  "must_change_password": false,
  "password": "password",
  "send_notify": false,
  "source_id": 0,
  "username": "username"
}
EOF
`

CURL_AUTH_HEADER=""
declare -a CURL_AUTH=()
curlBasicAuth() {
  username=$1
  password=$2
  basic=`echo -n "${username}:${password}" | base64`
  CURL_AUTH=("-H" "Authorization: Basic $basic")

  CURL_AUTH_HEADER="Authorization: Basic $basic"
}
curlTokenAuth() {
  token=$1
  CURL_AUTH=("-H" "Authorization: token ${token}")
}

curlBasicAuth "gitea_admin" "${GITEA_ADMIN_PASSWORD}"
CURL_GIT_ADMIN_AUTH=("${CURL_AUTH[@]}")
declare -a CURL_TYPE_JSON=("-H" "Accept: application/json" "-H" "Content-Type: application/json")
# "${GIT_SCHEME}://gitea_admin:${GITEA_ADMIN_PASSWORD}@${GIT_HOST}"

giteaCreateUserAndToken() {
  username=$1
  password=$2

  request=`echo "${FILE_USER_JSON}" \
    | yq e '.email="'${username}@example.com'"' - \
    | yq e '.full_name="'${username}'"' - \
    | yq e '.login_name="'${username}'"' - \
    | yq e '.username="'${username}'"' - \
    | yq e '.password="'${password}'"' -`

  substep "creating ${username} user"
  response=`echo "${request}" | curl -s -X POST "${GIT_URL}/api/v1/admin/users" "${CURL_GIT_ADMIN_AUTH[@]}" "${CURL_TYPE_JSON[@]}" --data @-`
  # info $request
  # info $response

  substep "updating ${username} user"
  response=`echo "${request}" | curl -s -X PATCH "${GIT_URL}/api/v1/admin/users/${username}" "${CURL_GIT_ADMIN_AUTH[@]}" "${CURL_TYPE_JSON[@]}" --data @-`
  # info $response

  substep "creating ${username} token"
  curlBasicAuth "${username}" "${password}"
  response=`curl -s -X POST "${GIT_URL}/api/v1/users/${username}/tokens" "${CURL_AUTH[@]}" "${CURL_TYPE_JSON[@]}" --data '{"name":"jx3"}'`
  # info $response
  token=`echo "${response}" | yq eval '.sha1' -`
  if [[ "$token" == "null" ]]; then
    info "Failed to create token for ${username}, json response: \n${response}"
    return 1
  fi
  TOKEN="${token}"
}

kind_bin="${DIR}/kind-${KIND_VERSION}"
installKind() {
  step "Installing kind ${KIND_VERSION}"
  if [ -x "${kind_bin}" ] ; then
    substep "kind already downloaded"
  else
    substep "downloading"
    curl -L -s "https://github.com/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/kind-${PLATFORM}-amd64" > ${kind_bin}
    chmod +x ${kind_bin}
  fi
  kind version
}

kind() {
  "${kind_bin}" "$@"
}

kubectl_bin="${DIR}/kubectl-${KUBECTL_VERSION}"
installKubectl() {
  step "Installing kubectl ${KUBECTL_VERSION}"
  if [ -x "${kubectl_bin}" ] ; then
    substep "kubectl already downloaded"

  else
    substep "downloading"
    curl -L -s https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/${PLATFORM}/amd64/kubectl > "${kubectl_bin}"
    chmod +x "${kubectl_bin}"
  fi
  kubectl version --client
}

kubectl() {
  "${kubectl_bin}" "$@"
}

helm_bin=`which helm || true`
installHelm() {
  step "Installing helm"
  if [ -x "${helm_bin}" ] ; then
    substep "helm in path"
  else
    substep "downloading"
    curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | "${helm_bin}"
    helm_bin=`which helm`
  fi
  helm version
}

helm() {
  "${helm_bin}" "$@"
}

yq_bin="${DIR}/yq-${YQ_VERSION}"
installYq() {
  step "Installing yq ${YQ_VERSION}"
  if [ -x "${yq_bin}" ] ; then
    substep "yq already downloaded"

  else
    substep "downloading"
    curl -L -s https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_${PLATFORM}_amd64 > "${yq_bin}"
    chmod +x "${yq_bin}"
  fi
  yq --version
}

yq() {
  "${yq_bin}" "$@"
}

jx_bin="${DIR}/jx-${JX_VERSION}"
installJx() {
  step "Installing jx ${JX_VERSION}"
  if [ -x "${jx_bin}" ] ; then
    substep "jx already downloaded"
  else
    substep "downloading"
    curl -L -s "https://github.com/jenkins-x/jx-cli/releases/download/v${JX_VERSION}/jx-cli-${PLATFORM}-amd64.tar.gz" | tar -xzf - jx
    mv jx ${jx_bin}
    chmod +x ${jx_bin}
  fi
  jx version
}
jx() {
  "${jx_bin}" "$@"
}

help() {
  # TODO
  info "run 'kind.sh create' or 'kind.sh destroy'"
}

createBootRepo() {
  step "creating the dev cluster git repo: ${GIT_URL}/${ORG}/cluster-$NAME-dev from template: ${DEV_CLUSTER_REPOSITORY}"

  rm -rf "cluster-$NAME-dev"

  export GIT_USERNAME="${BOT_USER}"
  export GIT_TOKEN="${TOKEN}"

  echo "user $GIT_USERNAME"
  echo "token $GIT_TOKEN"

  # lets make it public for now since its on a laptop
  # --private
  jx scm repo create ${GIT_URL}/${ORG}/cluster-$NAME-dev --template ${DEV_CLUSTER_REPOSITORY}  --confirm
  sleep 2

  git clone ${GIT_SCHEME}://${DEVELOPER_USER}:${DEVELOPER_PASS}@${GIT_HOST}/${ORG}/cluster-$NAME-dev

  cd cluster-$NAME-dev
  jx gitops requirements edit --domain "${IP}.nip.io"
  git commit -a -m "fix: upgrade domain"
  git push
  cd ..
}

installGitOperator() {
  step "installing the git operator at url: ${INTERNAL_GIT_URL}/${ORG}/cluster-$NAME-dev with user: ${BOT_USER} token: ${BOT_PASS}"

  jx admin operator --url "${INTERNAL_GIT_URL}/${ORG}/cluster-$NAME-dev" --username ${BOT_USER} --token ${TOKEN}
}

runBDD() {
    step "running the BDD tests $TEST_NAME on git server $INTERNAL_GIT_URL"

    echo "user: ${BOT_USER} token: ${TOKEN}"

    helm upgrade --install bdd jx3/jx-bdd  --namespace jx --create-namespace --set bdd.approverSecret="bdd-git-approver",bdd.kind="$GIT_KIND",bdd.owner="$ORG",bdd.gitServerHost="gitea-http.gitea",bdd.gitServerURL="$INTERNAL_GIT_URL",command.test="make $TEST_NAME",jxgoTag="$JX_VERSION",bdd.user="${BOT_USER}",bdd.token="${TOKEN}",env.JX_GIT_PUSH_HOST="gitea-http.gitea:3000"

    echo "about to wait for the BDD test to run"
    sleep 20
    jx verify job --name jx-bdd -n jx --log-fail
}


destroy() {

  if [[ -f "${LOG_FILE}" ]]; then
    rm "${LOG_FILE}"
  fi
  if [[ -d node-http ]]; then
    rm -rf ./node-http
  fi
  rm -f .*.token || true

  kind delete cluster --name="${KIND_CLUSTER_NAME}"
  docker network rm "${DOCKER_NETWORK_NAME}"

}

configureHelm() {
  step "Configuring helm chart repositories"

  substep "ingress-nginx"
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

  substep "gitea-charts"
  helm repo add gitea-charts https://dl.gitea.io/charts/

  substep "jx3"
  helm repo add jx3 https://storage.googleapis.com/jenkinsxio/charts

  substep "helm repo update"
  helm  repo update
}

installNginxIngress() {

  step "Installing nginx ingress"


  substep "Waiting for kind to start"

  kubectl wait --namespace kube-system \
    --for=condition=ready pod \
    --selector=tier=control-plane \
    --timeout=100m

  #kubectl create namespace nginx

  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml

  #echo "${FILE_NGINX_VALUES}" | helm  install nginx --namespace nginx --values - ingress-nginx/ingress-nginx

  substep "Waiting for nginx to start"

  sleep 60

  kubectl get pod --all-namespaces

  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=100m

#  kubectl wait --namespace nginx \
#    --for=condition=ready pod \
#    --selector=app.kubernetes.io/name=ingress-nginx \
#    --timeout=10m
}


installGitea() {
  step "Installing Gitea"

  kubectl create namespace gitea

  helm repo add gitea-charts https://dl.gitea.io/charts/

  echo "${FILE_GITEA_VALUES_YAML}" | helm install --namespace gitea -f - gitea gitea-charts/gitea

  substep "Waiting for Gitea to start"

  kubectl wait --namespace gitea \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=gitea \
    --timeout=100m

  echo "gitea is running at ${GIT_URL}"

  sleep 20

  echo "port forwarding gitea..."

  kubectl --namespace gitea port-forward svc/gitea-http 3000:3000 || true &

  echo "running curl -LI -o /dev/null  -s ${GIT_URL}/api/v1/admin/users -H '${CURL_AUTH_HEADER}'"

  # Verify that gitea is serving
  for i in {1..20}; do
    echo "curling..."

    http_output=`curl -v -LI -H "${CURL_AUTH_HEADER}" -s "${GIT_URL}/api/v1/admin/users" || true`
    echo "output of curl ${http_output}"

    echo curl -v -LI -s "${GIT_URL}/api/v1/admin/users" "${CURL_GIT_ADMIN_AUTH[@]}"
    http_code=`curl -LI -o /dev/null -w '%{http_code}' -H "${CURL_AUTH_HEADER}" -s "${GIT_URL}/api/v1/admin/users" || true`
    echo "got response code ${http_code}"

    if [[ "${http_code}" = "200" ]]; then
      break
    fi
    sleep 1
  done

  echo "stopped polling"

  if [[ "${http_code}" != "200" ]]; then
    info "Gitea didn't startup"
    return 1
  fi

  info "Gitea is up at ${GIT_URL}"
  info "Login with username: gitea_admin password: ${GITEA_ADMIN_PASSWORD}"
}

configureGiteaOrgAndUsers() {
  step "Setting up gitea organisation and users"

  giteaCreateUserAndToken "${BOT_USER}" "${BOT_PASS}"
  botToken="${TOKEN}"
  echo "${botToken}" > "${DIR}/.${KIND_CLUSTER_NAME}-bot.token"

  giteaCreateUserAndToken "${DEVELOPER_USER}" "${DEVELOPER_PASS}"
  developerToken="${TOKEN}"
  echo "${developerToken}" > "${DIR}/.${KIND_CLUSTER_NAME}-developer.token"
  substep "creating ${ORG} organisation"

  curlTokenAuth "${developerToken}"
  json=`curl -s -X POST "${GIT_URL}/api/v1/orgs" "${CURL_AUTH[@]}" "${CURL_TYPE_JSON[@]}" --data '{"repo_admin_change_team_access": true, "username": "'${ORG}'", "visibility": "private"}'`
  # info "${json}"

  substep "add ${BOT_USER} an owner of ${ORG} organisation"

  substep "find owners team for ${ORG}"
  curlTokenAuth "${developerToken}"
  json=`curl -s "${GIT_URL}/api/v1/orgs/${ORG}/teams/search?q=owners" "${CURL_AUTH[@]}" "${CURL_TYPE_JSON[@]}"`
  id=`echo "${json}" | yq eval '.data[0].id' -`
  if [[ "${id}" == "null" ]]; then
    info "Unable to find owners team, json response :\n${json}"
    return 1
  fi

  substep "add ${BOT_USER} as member of owners team (#${id}) for ${ORG}"
  curlTokenAuth "${developerToken}"
  response=`curl -s -X PUT "${GIT_URL}/api/v1/teams/${id}/members/${BOT_USER}" "${CURL_AUTH[@]}" "${CURL_TYPE_JSON[@]}"`

}

loadGitUserTokens() {
  botToken=`cat ".${KIND_CLUSTER_NAME}-bot.token"`
  developerToken=`cat ".${KIND_CLUSTER_NAME}-developer.token"`
}




waitFor() {
  timeout="$1"; shift
  label="$1"; shift
  command="$1"; shift
  args=("$@")

  substep "Waiting for: ${label}"
  while :
  do
    "${command}" "${args[@]}" 2>&1 >/dev/null && RC=$? || RC=$?
    if [[ $RC -eq 0 ]]; then
      return 0
    fi
    sleep 5
  done
  info "Gave up waiting for: ${label}"
  return 1
}

getUrlBodyContains() {
  url=$1; shift
  expectedText=$1; shift
  curl -s "${url}" | grep "${expectedText}" > /dev/null
}


# resetGitea() {
#   #
#   #
#   # DANGER : THIS WILL REMOVE ALL GITEA DATA
#   #
#   #
#   step "Resetting Gitea"
#   substep "Clar gitea data folder which includes the sqlite database and repositories"
#   kubectl -n gitea exec gitea-0 -- rm -rf "/data/*"


#   substep "Restart gitea pod"
#   kubectl -n gitea delete pod gitea-0
#   sleep 5
#   expectPodsReadyByLabel gitea app.kubernetes.io/name=gitea

# }


createKindCluster() {
  step "Creating kind cluster named ${KIND_CLUSTER_NAME}"

    # create our own docker network so that we know the node's IP address ahead of time (easier than guessing the next avail IP on the kind network)
  networkId=`docker network create -d bridge --subnet "${SUBNET}" --gateway "${GATEWAY}" "${DOCKER_NETWORK_NAME}"`

  info "Node IP is ${IP}"

  # connect the registry to the cluster network
  # (the network may already be connected)
  docker network connect "kind" "${reg_name}" || true

# create registry container unless it already exists
running="$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)"
if [ "${running}" != 'true' ]; then
  docker run \
    -d --restart=always -p "127.0.0.1:${reg_port}:5000" --name "${reg_name}" \
    registry:2
fi

# create a cluster with the local registry enabled in containerd
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${reg_port}"]
    endpoint = ["http://${reg_name}:${reg_port}"]
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


# Document the local registry
# https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF


  # lets switch to the cluster
  kubectl config use-context "kind-${KIND_CLUSTER_NAME}"

  kubectl cluster-info
}





create() {
  installKind
  installYq
  installHelm
  installJx
  installKubectl
  configureHelm

  createKindCluster

  installNginxIngress
  installGitea
  configureGiteaOrgAndUsers
  createBootRepo
  installGitOperator

  runBDD
}


recreate() {
  destroy

  sleep 2

  create
}

function_exists() {
  declare -f -F $1 > /dev/null
  return $?
}

if [[ "${COMMAND}" == "ciLoop" ]]; then
  ciLoop
elif [[ "${COMMAND}" == "env" ]]; then
  :
else
  if `function_exists "${COMMAND}"`; then
    shift
    #initLog

    "${COMMAND}" "$@"
  else
    info "Unknown command : ${COMMAND}"
    exit 1
  fi
fi

exit 0
}