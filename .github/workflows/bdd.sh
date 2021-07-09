#!/usr/bin/env bash

set -euo pipefail


if [ -z "$GITHUB_ACTIONS" ]
then
  echo "not setting up git as not in a GitHub Action"
else
  echo "lets setup git"
  git config user.name github-actions
  git config user.email github-actions@github.com
fi

export BDD_NAME="kind"
export BRANCH_NAME="${BRANCH_NAME:-pr-${GITHUB_RUN_ID}-${GITHUB_RUN_NUMBER}}"
export BUILD_NUMBER="${GITHUB_RUN_NUMBER}"

export CLUSTER_NAME="${BRANCH_NAME,,}-$BUILD_NUMBER-$BDD_NAME"

echo "using cluster name: $CLUSTER_NAME with owner $GIT_OWNER"

jx scm version

jx scm repo create https://github.com/${GIT_OWNER}/cluster-$CLUSTER_NAME --template https://github.com/jx3-gitops-repositories/jx3-kind --private --confirm --kind github
sleep 15
jx scm repo clone https://github.com/${GIT_OWNER}/cluster-$CLUSTER_NAME cluster-dev

pushd `pwd`/cluster-dev
    echo "creating the kind cluster"
    ./kind.sh create

    echo "running the BDD tests"
    ./run_bdd.sh
popd


