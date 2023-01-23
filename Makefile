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

default: build

HUB ?= quay.io/redhat-developer
TAG ?= latest

lint:
	@if command -v shellcheck >/dev/null; then \
		find . -name '*.sh' -print0 | xargs -0 -r shellcheck; \
	else \
		echo "shellcheck not found, installing it now..."; \
		if command -v apt-get >/dev/null; then \
			sudo apt-get install -y shellcheck; \
		elif command -v yum >/dev/null; then \
			sudo yum install -y shellcheck; \
		elif command -v dnf >/dev/null; then \
			sudo dnf install -y shellcheck; \
		elif command -v pacman >/dev/null; then \
			sudo pacman -S --noconfirm shellcheck; \
		else \
			echo "shellcheck not found and unable to install it automatically"; \
			echo "Please install shellcheck manually and run the lint target again"; \
			exit 1; \
		fi; \
		find . -name '*.sh' -print0 | xargs -0 -r shellcheck; \
	fi

image:
	@if command -v podman >/dev/null; then \
		podman build -t ${HUB}/gitops-must-gather:${TAG}; \
	else \
		docker build -t ${HUB}/gitops-must-gather:${TAG}; \
	fi

push: image
	@if command -v podman >/dev/null; then \
		podman push ${HUB}/gitops-must-gather:${TAG}; \
	else \
		docker push ${HUB}/gitops-must-gather:${TAG}; \
	fi