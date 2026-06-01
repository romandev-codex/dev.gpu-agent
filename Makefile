IMAGE       := hermes-all
COMPOSE     := docker compose
ENV_FILE    := .env

# ── All-in-one image (Dockerfile.app) ──────────────────────────────────────
.PHONY: build
build:
	docker build -f Dockerfile.app -t $(IMAGE) .

.PHONY: build-no-cache
build-no-cache:
	docker build --no-cache -f Dockerfile.app -t $(IMAGE) .

.PHONY: run
run: build
	docker run --rm --gpus all \
	  -p 127.0.0.1:8080:8080 \
	  -p 127.0.0.1:9222:9222 \
	  -p 127.0.0.1:9119:9119 \
	  -v "$(PWD)/models:/models:ro" \
	  -v "$(PWD)/data:/root/.hermes" \
	  --env-file $(ENV_FILE) \
	  $(IMAGE)

.PHONY: run-detach
run-detach: build
	docker run -d --name $(IMAGE) --gpus all \
	  -p 127.0.0.1:8080:8080 \
	  -p 127.0.0.1:9222:9222 \
	  -p 127.0.0.1:9119:9119 \
	  -v "$(PWD)/models:/models:ro" \
	  -v "$(PWD)/data:/root/.hermes" \
	  --env-file $(ENV_FILE) \
	  $(IMAGE)

.PHONY: logs
logs:
	docker logs -f $(IMAGE)

.PHONY: stop
stop:
	docker stop $(IMAGE) && docker rm $(IMAGE)

.PHONY: shell
shell:
	docker exec -it $(IMAGE) /bin/bash

# ── docker-compose (multi-container) ───────────────────────────────────────
.PHONY: up
up:
	$(COMPOSE) up -d

.PHONY: up-build
up-build:
	$(COMPOSE) up -d --build

.PHONY: down
down:
	$(COMPOSE) down

.PHONY: compose-logs
compose-logs:
	$(COMPOSE) logs -f

.PHONY: ps
ps:
	$(COMPOSE) ps

# ── Utilities ───────────────────────────────────────────────────────────────
.PHONY: models-dir
models-dir:
	mkdir -p models data

.PHONY: clean
clean:
	docker rmi $(IMAGE) || true

.PHONY: help
help:
	@echo ""
	@echo "  Single-container (Dockerfile.app)"
	@echo "  ──────────────────────────────────"
	@echo "  build          Build the $(IMAGE) image"
	@echo "  build-no-cache Build without Docker layer cache"
	@echo "  run            Build + run in foreground (--gpus all)"
	@echo "  run-detach     Build + run in background"
	@echo "  logs           Tail container logs"
	@echo "  stop           Stop and remove the container"
	@echo "  shell          Open a bash shell in the running container"
	@echo ""
	@echo "  docker-compose (multi-container)"
	@echo "  ──────────────────────────────────"
	@echo "  up             Start all services (detached)"
	@echo "  up-build       Start all services, rebuild first"
	@echo "  down           Stop and remove all services"
	@echo "  compose-logs   Tail all service logs"
	@echo "  ps             Show running services"
	@echo ""
	@echo "  Utilities"
	@echo "  ──────────────────────────────────"
	@echo "  models-dir     Create models/ and data/ directories"
	@echo "  clean          Remove the $(IMAGE) image"
	@echo "  help           Show this help"
	@echo ""
