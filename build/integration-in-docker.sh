#!/usr/bin/env bash

# Copyright 2020 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -ex

ROOT="$(cd "$(dirname "${BASH_SOURCE}")/.." && pwd -P)"
TMPDIR=$(mktemp -d)
function delete() {
  echo "Deleting ${TMPDIR}..."
  if [[ $EUID -ne 0 ]]; then
    sudo rm -rf "${TMPDIR}"
  else
    rm -rf "${TMPDIR}"
  fi
}
trap delete EXIT INT TERM

function run_tests() {

  # Add safe.directory as workaround for https://github.com/actions/runner/issues/2033
  BUILD_CMD="git config --global safe.directory /go/src/github.com/google/cadvisor && env GOOS=linux GOARCH=amd64 GO_FLAGS='$GO_FLAGS' ./build/build.sh && \
    env GOOS=linux GOFLAGS='$GO_FLAGS' go test -c github.com/google/cadvisor/integration/tests/api && \
    env GOOS=linux GOFLAGS='$GO_FLAGS' go test -c github.com/google/cadvisor/integration/tests/healthz"

  if [ "$BUILD_PACKAGES" != "" ]; then
    BUILD_CMD="apt update && apt install -y $BUILD_PACKAGES && \
    $BUILD_CMD"
  fi
  docker run --rm \
    -w /go/src/github.com/google/cadvisor \
    -v ${PWD}:/go/src/github.com/google/cadvisor \
    golang:"$GOLANG_VERSION-bookworm" \
    bash -c "$BUILD_CMD"

  EXTRA_DOCKER_OPTS="-e DOCKER_IN_DOCKER_ENABLED=true"
  if [[ "${OSTYPE}" == "linux"* ]]; then
    EXTRA_DOCKER_OPTS+=" -v ${TMPDIR}/docker-graph:/docker-graph"
  fi

  mkdir ${TMPDIR}/docker-graph
  docker run --rm \
    -w /go/src/github.com/google/cadvisor \
    -v ${ROOT}:/go/src/github.com/google/cadvisor \
    ${EXTRA_DOCKER_OPTS} \
    --privileged \
    --cap-add="sys_admin" \
    --entrypoint="" \
    gcr.io/k8s-staging-test-infra/bootstrap \
    bash -c "export DEBIAN_FRONTEND=noninteractive && \
    apt update && \
    apt install -y $PACKAGES && \
    CADVISOR_ARGS=$CADVISOR_ARGS /usr/local/bin/runner.sh build/integration.sh"
}

GO_FLAGS=${GO_FLAGS:-"-tags=netgo -race"}
PACKAGES=${PACKAGES:-"sudo"}
BUILD_PACKAGES=${BUILD_PACKAGES:-}
CADVISOR_ARGS=${CADVISOR_ARGS:-}
GOLANG_VERSION=${GOLANG_VERSION:-"1.24"}
run_tests
