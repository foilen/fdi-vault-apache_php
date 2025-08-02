#!/bin/bash

set -e

# Set environment
export LANG="C.UTF-8"
export VERSION=$1

if [ -z "$VERSION" ]; then
	export VERSION=main-SNAPSHOT
fi

RUN_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $RUN_PATH

./step-create-docker-image.sh
