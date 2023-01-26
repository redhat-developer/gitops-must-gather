## Copyright 2023 Red Hat, Inc.
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

# Check if Docker or Podman is installed and set the variable DOCKER_OR_PODMAN to the executable.
DOCKER_OR_PODMAN := $(shell command -v podman || command -v docker)

# Add all the targets that are not associated with a file for a PHONY.
# This will prevent any errors if a file with the same name as a target is present in the directory.
.PHONY: help lint image push clean

# Set the default target to help
default: help

# Set the helpful variables for the Makefile
DOCKERFILE_ROOT=$(shell pwd)

# Set the variables for the container image
CONTAINER_REGISTRY ?= quay.io
REGISTRY_USERNAME ?= redhat-developer
CONTAINER_IMAGE_NAME ?= gitops-must-gather
CONTAINER_IMAGE_TAG ?= latest
CONTAINER_IMAGE_LINK ?= ${CONTAINER_REGISTRY}/${REGISTRY_USERNAME}/${CONTAINER_IMAGE_NAME}:${CONTAINER_IMAGE_TAG}

help: ## Display this help menu
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# Check if Docker or Podman is installed and if shellcheck is installed. If not, exit with an error.
# This is done to prevent the user from running the commands that require Docker or Podman if they are not present.
check-docker-podman:
	@if ! command -v docker >/dev/null && ! command -v podman >/dev/null; then \
		echo "Neither Docker nor Podman were found. Please install one of them and run the command again."; \
		exit 1; \
	fi

check-shellcheck:
	@if ! command -v shellcheck >/dev/null; then \
		echo "shellcheck was not found. Please install it and run the command again."; \
		exit 1; \
	fi

lint: check-shellcheck ## Lint the shell scripts
	find . -name '*.sh' -print0 | xargs -0 -r $ shellcheck

image: check-docker-podman ## Build the image
	${DOCKER_OR_PODMAN} build -t ${CONTAINER_IMAGE_LINK} ${DOCKERFILE_ROOT}

push: image ## Push the image to the container registry
	${DOCKER_OR_PODMAN} push ${CONTAINER_IMAGE_LINK}

clean: check-docker-podman ## Clean up the built image
	${DOCKER_OR_PODMAN} rmi ${CONTAINER_IMAGE_LINK}