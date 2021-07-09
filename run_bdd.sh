#!/usr/bin/env bash

# based on: https://github.com/cameronbraid/jx3-kind/blob/master/jx3-kind.sh
set -euo pipefail

# lets setup the hermit binaries
source ./bin/activate-hermit || true

export JX_VERSION=$(grep 'version: ' versionStream/packages/jx.yml | awk '{ print $2}')

#TEST_NAME="${TEST_NAME:-test-create-spring}"
TEST_NAME="${TEST_NAME:-test-quickstart-node-http}"

GIT_OWNER="${GIT_OWNER:-$GIT_USERNAME}"

echo "running the BDD tests $TEST_NAME with user: $GIT_USERNAME with owner:$GIT_OWNER jx version: $JX_VERSION"


git clone https://github.com/jenkins-x/bdd-jx3

cd bdd-jx3

export GIT_ORGANISATION=$GIT_OWNER

# lets enable kubectl access in jx
export JX_KUBERNETES=true

jx ns jx
make test-quickstart-golang-http


#helm upgrade --install bdd jx3/jx-bdd  --namespace jx --create-namespace --set command.test="make $TEST_NAME",jxgoTag="$JX_VERSION",bdd.user="${GIT_USERNAME}",bdd.owner="$GIT_OWNER",bdd.token="${GIT_TOKEN}"

#echo "about to wait for the BDD test to run"

#sleep 20

#kubectl describe nodes
#kubectl get event -n jx -w &

# lets avoid the jx commands thinking we are outside of kubernetes due to $GITHUB-ACTIONS maybe being set..
#export JX_KUBERNETES="true"
#jx verify job --name jx-bdd -n jx
