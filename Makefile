SHELL := /bin/bash
.DEFAULT_GOAL := help

DOCKER ?= docker
IMAGE ?= pdparchitect/buzznode:local
CONTAINER ?= buzznode
PLATFORM ?= linux/amd64
BUZZ_VERSION ?= 0.4.26
BUZZ_DEB_SHA256 ?= 1b520756ecfc28ad81981a2cd5cc6688f785f447b3f5d8d553544906f59bf521
CODEX_VERSION ?= 0.145.0
CLAUDE_CODE_VERSION ?= 2.1.220
CODEX_ACP_VERSION ?= 1.1.7
CLAUDE_ACP_VERSION ?= 0.62.0
GOOSE_VERSION ?= 1.44.0
GOOSE_ARCHIVE_SHA256 ?= 07febc8b4f73bdfdc3ece3d34d0e21b005f3a4f43008f95b85d6538da8f6bac1
BIND_ADDRESS ?= 127.0.0.1
PORT ?= 6904
RELAY_URL ?=
BUZZ_NETWORK ?=
RESOLUTION ?= 1920x1080
VNC_STATS ?= false
VOLUME_PREFIX ?= buzznode

# Pass render nodes only. `--device=/dev/dri` would also hand over card*, the
# DRM master/modesetting node, which nothing in this container has a use for.
GPU_DEVICE := $(shell for node in /dev/dri/renderD*; do \
	[ -e "$$node" ] && echo "--device=$$node"; done)
RELAY_ENV := $(if $(strip $(RELAY_URL)),--env "BUZZ_RELAY_URL=$(RELAY_URL)",)
NETWORK_ARG := $(if $(strip $(BUZZ_NETWORK)),--network "$(BUZZ_NETWORK)",)

.PHONY: help check build network run recreate up test smoke connection-test stop logs vnc-log status url size-report

help:
	@echo "Buzznode local Docker workflow"
	@echo
	@echo "  make check      Validate scripts, tests, and pinned metadata"
	@echo "  make build      Build $(IMAGE)"
	@echo "  make run        Start or create the Buzznode container"
	@echo "  make recreate   Recreate the container without rebuilding"
	@echo "  make up         Build and recreate the container"
	@echo "  make test       Check, build, run, and smoke-test the environment"
	@echo "  make smoke      Test the node desktop and headless agent tools"
	@echo "  make connection-test  Test the configured external Buzz relay"
	@echo "  make logs       Follow container logs"
	@echo "  make vnc-log    Follow the KasmVNC session log"
	@echo "  make status     Show container and node status"
	@echo "  make stop       Stop and remove the container"
	@echo "  make url        Print the local desktop URL"
	@echo "  make size-report  Report the graphical stack's share of the image"
	@echo
	@echo "Overrides: PORT=8080 RELAY_URL=wss://buzz.example RESOLUTION=1600x900"
	@echo "           BUZZ_NETWORK=buzz-local VNC_STATS=true"

check:
	bash -n init.sh openbox/autostart shell/agent-runtime-login shell/buzznode \
		shell/buzznode-panel-status shell/chromium shell/welcome \
		tests/test-agent-runtime-login.sh tests/test-buzznode.sh
	bash tests/test-agent-runtime-login.sh
	bash tests/test-buzznode.sh
	@grep -q "^ARG BUZZ_VERSION=$(BUZZ_VERSION)$$" Dockerfile
	@grep -q "^ARG BUZZ_DEB_SHA256=$(BUZZ_DEB_SHA256)$$" Dockerfile
	@grep -q "^ARG CODEX_VERSION=$(CODEX_VERSION)$$" Dockerfile
	@grep -q "^ARG CLAUDE_CODE_VERSION=$(CLAUDE_CODE_VERSION)$$" Dockerfile
	@grep -q "^ARG CODEX_ACP_VERSION=$(CODEX_ACP_VERSION)$$" Dockerfile
	@grep -q "^ARG CLAUDE_ACP_VERSION=$(CLAUDE_ACP_VERSION)$$" Dockerfile
	@grep -q "^ARG GOOSE_VERSION=$(GOOSE_VERSION)$$" Dockerfile
	@grep -q "^ARG GOOSE_ARCHIVE_SHA256=$(GOOSE_ARCHIVE_SHA256)$$" Dockerfile
	@echo "Buzznode metadata, setup CLI, and shell syntax are valid."

build:
	$(DOCKER) build \
		--platform "$(PLATFORM)" \
		--build-arg TARGETARCH=amd64 \
		--build-arg "BUZZ_VERSION=$(BUZZ_VERSION)" \
		--build-arg "BUZZ_DEB_SHA256=$(BUZZ_DEB_SHA256)" \
		--build-arg "CODEX_VERSION=$(CODEX_VERSION)" \
		--build-arg "CLAUDE_CODE_VERSION=$(CLAUDE_CODE_VERSION)" \
		--build-arg "CODEX_ACP_VERSION=$(CODEX_ACP_VERSION)" \
		--build-arg "CLAUDE_ACP_VERSION=$(CLAUDE_ACP_VERSION)" \
		--build-arg "GOOSE_VERSION=$(GOOSE_VERSION)" \
		--build-arg "GOOSE_ARCHIVE_SHA256=$(GOOSE_ARCHIVE_SHA256)" \
		--tag "$(IMAGE)" \
		.

network:
	@if [ -n "$(strip $(BUZZ_NETWORK))" ]; then \
		if ! $(DOCKER) network inspect "$(BUZZ_NETWORK)" >/dev/null 2>&1; then \
			$(DOCKER) network create "$(BUZZ_NETWORK)" >/dev/null; \
			echo "Created Docker network $(BUZZ_NETWORK)."; \
		fi; \
	fi

run: network
	@if $(DOCKER) container inspect "$(CONTAINER)" >/dev/null 2>&1; then \
		if [ "$$($(DOCKER) container inspect --format '{{.State.Running}}' "$(CONTAINER)")" = "true" ]; then \
			echo "Container $(CONTAINER) is already running."; \
		else \
			$(DOCKER) start "$(CONTAINER)"; \
		fi; \
	else \
		$(DOCKER) run --detach \
			--name "$(CONTAINER)" \
			--platform "$(PLATFORM)" \
			--restart unless-stopped \
			--shm-size 1g \
			$(GPU_DEVICE) \
			$(NETWORK_ARG) \
			--publish "$(BIND_ADDRESS):$(PORT):6901" \
			$(RELAY_ENV) \
			--env "BUZZNODE_RESOLUTION=$(RESOLUTION)" \
			--env "BUZZNODE_VNC_STATS=$(VNC_STATS)" \
			--volume "$(VOLUME_PREFIX)-workspace:/workspace" \
			--volume "$(VOLUME_PREFIX)-config:/home/buzznode/.config" \
			--volume "$(VOLUME_PREFIX)-data:/home/buzznode/.local/share" \
			--volume "$(VOLUME_PREFIX)-nest:/home/buzznode/.buzz" \
			--volume "$(VOLUME_PREFIX)-codex:/home/buzznode/.codex" \
			--volume "$(VOLUME_PREFIX)-claude:/home/buzznode/.claude" \
			"$(IMAGE)"; \
	fi
	@$(MAKE) --no-print-directory url

recreate:
	@$(MAKE) --no-print-directory stop
	@$(MAKE) --no-print-directory run

up: build recreate

test: check up smoke

smoke:
	@echo "Waiting for Buzznode at http://$(BIND_ADDRESS):$(PORT) ..."
	@ready=false; \
	for attempt in $$(seq 1 60); do \
		if curl --fail --silent "http://$(BIND_ADDRESS):$(PORT)/index.html" >/dev/null; then \
			ready=true; \
			break; \
		fi; \
		sleep 2; \
	done; \
	if [ "$$ready" != "true" ]; then \
		echo "Buzznode did not become ready within 120 seconds."; \
		$(DOCKER) logs --tail 150 "$(CONTAINER)" || true; \
		exit 1; \
	fi
	@$(DOCKER) exec "$(CONTAINER)" bash -ec '\
		for command in agent-runtime-login buzznode buzz buzz-acp buzz-agent buzz-dev-mcp \
			codex codex-acp claude claude-agent-acp goose; do \
			command -v "$$command" >/dev/null; \
		done; \
		! command -v buzz-desktop >/dev/null; \
		! command -v buzz-relay >/dev/null; \
		! command -v postgres >/dev/null; \
		curl -fsS http://127.0.0.1:6901/ >/dev/null'
	@echo "Buzznode is ready with a desktop and one headless agent harness."

connection-test:
	@$(DOCKER) exec \
		--user agent \
		"$(CONTAINER)" \
		buzznode doctor

stop:
	@if $(DOCKER) container inspect "$(CONTAINER)" >/dev/null 2>&1; then \
		$(DOCKER) rm --force "$(CONTAINER)"; \
	else \
		echo "Container $(CONTAINER) does not exist."; \
	fi

logs:
	$(DOCKER) logs --follow "$(CONTAINER)"

vnc-log:
	$(DOCKER) exec "$(CONTAINER)" \
		bash -c 'tail --lines=200 --follow /home/buzznode/.vnc/*:1.log'

status:
	@$(DOCKER) ps --all \
		--filter "name=^/$(CONTAINER)$$" \
		--format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
	@if $(DOCKER) container inspect "$(CONTAINER)" >/dev/null 2>&1; then \
		$(DOCKER) exec "$(CONTAINER)" buzznode status || true; \
	fi

url:
	@echo "Desktop: http://$(BIND_ADDRESS):$(PORT)"

size-report:
	@DOCKER="$(DOCKER)" bash tools/size-report.sh "$(IMAGE)"
