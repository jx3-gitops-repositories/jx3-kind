#!/usr/bin/env bash

set -euo pipefail

git config --global user.name $GIT_USERNAME
git config --global user.email jenkins-x@googlegroups.com

export BDD_NAME="kind"
export BRANCH_NAME="${BRANCH_NAME:-pr-${GITHUB_RUN_ID}-${GITHUB_RUN_NUMBER}}"
export BUILD_NUMBER="${GITHUB_RUN_NUMBER}"

export CLUSTER_NAME="${BRANCH_NAME,,}-$BUILD_NUMBER-$BDD_NAME"

echo "using cluster name: $CLUSTER_NAME with owner $GIT_OWNER with user $GIT_USERNAME"


# lets check we have a git credentials file...
if test  -f "~/.git-credentials"; then
  echo "~/.git-credentials exists"
else
  echo "creating file ~/.git-credentials"
  echo "https://$GIT_USERNAME:$GIT_TOKEN@github.com" >  ~/.git-credentials
fi
git config credential.helper store

jx scm version

jx scm repo create https://github.com/${GIT_OWNER}/cluster-$CLUSTER_NAME --template https://github.com/jx3-gitops-repositories/jx3-kind --private --confirm --kind github

echo "sleeping for a little while"
sleep 15

echo "now cloning the repository: https://github.com/${GIT_OWNER}/cluster-$CLUSTER_NAME"

jx scm repo clone https://$GIT_USERNAME:$GIT_TOKEN@github.com/${GIT_OWNER}/cluster-$CLUSTER_NAME

pushd `pwd`/cluster-$CLUSTER_NAME
    echo "creating the kind cluster"
    ./kind.sh create

    echo "running the BDD tests"
    ./run_bdd.sh
popd


