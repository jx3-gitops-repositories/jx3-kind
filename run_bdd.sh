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

export XDG_CONFIG_HOME="$HOME"


# default to batch mode so jx commands don't ask for input
export JX_BATCH_MODE="true"

# increase the timeout for complete PipelineActivity
export BDD_TIMEOUT_PIPELINE_ACTIVITY_COMPLETE="60"

# we don't yet update the PipelineActivity.spec.pullTitle on previews....
export BDD_DISABLE_PIPELINEACTIVITY_CHECK="true"

# lets skip manual promotion
export JX_BDD_SKIP_MANUAL_PROMOTION="true"

# disable checking for PipelineActivity status == Succeeded for now while we fix up a timing issue
export BDD_ASSERT_ACTIVITY_SUCCEEDED="false"

# view the PR pipeline logs
export JX_VIEW_PROMOTE_PR_LOG="true"

# lets remove promoted apps after promotion
export JX_DISABLE_DELETE_APP="false"

# don't delete the source repo though
export JX_DISABLE_DELETE_REPO="true"

# setup the namespace and git
jx ns jx
jx gitops git setup


kubectl get event -n jx -w &


echo "JX_DISABLE_DELETE_APP = $JX_DISABLE_DELETE_APP"
jx version

make test-quickstart-node-http


#helm upgrade --install bdd jx3/jx-bdd  --namespace jx --create-namespace --set command.test="make $TEST_NAME",jxgoTag="$JX_VERSION",bdd.user="${GIT_USERNAME}",bdd.owner="$GIT_OWNER",bdd.token="${GIT_TOKEN}"

#echo "about to wait for the BDD test to run"

#sleep 20

#kubectl describe nodes

# lets avoid the jx commands thinking we are outside of kubernetes due to $GITHUB-ACTIONS maybe being set..
#export JX_KUBERNETES="true"
#jx verify job --name jx-bdd -n jx
