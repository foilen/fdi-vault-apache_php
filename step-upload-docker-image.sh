#!/bin/bash

set -e

RUN_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $RUN_PATH

echo ----[ Upload docker image ]----
DOCKER_IMAGE=fdi-vault-apache_php
DOCKER_IMAGE_VERSION=fdi-vault-apache_php:$VERSION
docker login
docker tag $DOCKER_IMAGE_VERSION foilen/$DOCKER_IMAGE_VERSION
docker tag $DOCKER_IMAGE_VERSION foilen/$DOCKER_IMAGE:latest
docker push foilen/$DOCKER_IMAGE_VERSION
docker push foilen/$DOCKER_IMAGE:latest
