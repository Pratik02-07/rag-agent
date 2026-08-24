#!/usr/bin/env bash

# RAG Agent deployment script for Linux EC2 hosts and macOS.
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/Pratik02-07/rag-agent.git}"
MIN_FREE_GB="${MIN_FREE_GB:-0}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${APP_DIR+x}" ]; then
	if [ -f "${SCRIPT_DIR}/docker-compose.yml" ] || [ -f "${SCRIPT_DIR}/compose.yml" ]; then
		APP_DIR="$SCRIPT_DIR"
	else
		APP_DIR="${HOME}/rag-agent"
	fi
fi

log() { printf '\n[INFO] %s\n' "$1"; }
success() { printf '[SUCCESS] %s\n' "$1"; }
fail() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
on_error() {
	local exit_code=$?
	printf '[ERROR] Deployment failed near line %s (exit code %s).\n' \
		"${BASH_LINENO[0]}" "${exit_code}" >&2
	exit "$exit_code"
}
trap on_error ERR

as_root() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	else
		command_exists sudo || fail "sudo is required for package installation."
		sudo "$@"
	fi
}

detect_os() {
	if [ "$(uname -s)" = "Darwin" ]; then
		OS=macos
	elif [ -r /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	OS="${ID}"
	else
		fail "Unable to detect the operating system."
	fi
	log "Detected operating system: ${OS}"
}

install_linux_package() {
	local package_manager
	if command_exists apt-get; then
		package_manager=apt-get
		as_root apt-get update
		as_root apt-get install -y "$@"
	elif command_exists dnf; then
		package_manager=dnf
		as_root dnf install -y "$@"
	elif command_exists yum; then
		package_manager=yum
		as_root yum install -y "$@"
	else
		fail "No supported package manager (apt-get, dnf, or yum) was found."
	fi
	: "${package_manager}"
}

install_git() {
	command_exists git && { success "Git is already installed."; return; }
	log "Installing Git..."
	if [ "$OS" = macos ]; then
		command_exists brew || fail "Homebrew is required on macOS."
		brew install git
	else
		install_linux_package git
	fi
	command_exists git || fail "Git installation failed."
	success "Git is installed."
}

install_docker() {
	if ! command_exists docker; then
		log "Installing Docker..."
		if [ "$OS" = macos ]; then
			command_exists brew || fail "Homebrew is required on macOS."
			brew install --cask docker
		else
			if command_exists apt-get; then
				install_linux_package docker.io
			else
				install_linux_package docker
			fi
		fi
	fi
	if [ "$OS" != macos ] && command_exists systemctl; then
		as_root systemctl enable --now docker
		systemctl is-active --quiet docker || fail "Docker service failed to start."
	fi
	command_exists docker || fail "Docker installation failed."
	success "Docker is available."
}

install_docker_compose() {
	if docker compose version >/dev/null 2>&1; then
		success "Docker Compose plugin is already installed."
		return
	fi
	if command_exists docker-compose; then
		success "Docker Compose standalone command is already installed."
		return
	fi

	log "Installing Docker Compose..."
	if [ "$OS" = macos ]; then
		fail "Docker Desktop must be started before Docker Compose can be used."
	elif command_exists apt-get; then
		if ! as_root apt-get update || ! as_root apt-get install -y docker-compose; then
			as_root apt-get install -y ca-certificates curl gnupg lsb-release
			as_root install -m 0755 -d /etc/apt/keyrings
			as_root curl -fsSL https://download.docker.com/linux/ubuntu/gpg | as_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
			as_root chmod a+r /etc/apt/keyrings/docker.gpg
			printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n' \
				"$(dpkg --print-architecture)" "$(. /etc/os-release && echo "$VERSION_CODENAME")" | as_root tee /etc/apt/sources.list.d/docker.list >/dev/null
			as_root apt-get update
			as_root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
		fi
	else
		as_root mkdir -p /usr/local/lib/docker/cli-plugins
		command_exists curl || install_linux_package curl
		as_root curl -fsSL \
			https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
			-o /usr/local/lib/docker/cli-plugins/docker-compose
		as_root chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
	fi

	if docker compose version >/dev/null 2>&1 || command_exists docker-compose; then
		success "Docker Compose is installed."
		return
	fi
	fail "Docker Compose installation failed."
}

install_nginx() {
	if command_exists nginx; then
		success "Nginx is already installed."
		return
	fi
	log "Installing Nginx..."
	if [ "$OS" = macos ]; then
		command_exists brew || fail "Homebrew is required on macOS."
		brew install nginx
	else
		install_linux_package nginx
		command_exists systemctl && as_root systemctl enable nginx
	fi
	command_exists nginx || fail "Nginx installation failed."
	success "Nginx is installed."
}

configure_nginx() {
	if ! command_exists nginx; then
		log "Nginx is not installed; skipping reverse-proxy configuration."
		return
	fi

	local nginx_conf_dir nginx_conf nginx_default_site config_source
	config_source="${APP_DIR}/nginx/rag-agent.conf"
	if [ "$OS" = macos ]; then
		nginx_conf_dir="/usr/local/etc/nginx/servers"
		nginx_conf="/usr/local/etc/nginx/servers/rag-agent.conf"
		nginx_default_site="/usr/local/etc/nginx/conf.d/default.conf"
		mkdir -p "$nginx_conf_dir"
	else
		nginx_conf_dir="/etc/nginx/conf.d"
		nginx_conf="/etc/nginx/conf.d/rag-agent.conf"
		nginx_default_site="/etc/nginx/sites-enabled/default"
		as_root mkdir -p "$nginx_conf_dir"
	fi

	if [ ! -f "$config_source" ]; then
		fail "Nginx config template not found at ${config_source}."
	fi

	log "Configuring Nginx reverse proxy for the RAG app..."
	if [ "$OS" = macos ]; then
		cp "$config_source" "$nginx_conf"
	else
		as_root cp "$config_source" "$nginx_conf"
	fi

	if [ -f "$nginx_default_site" ] && [ "$OS" != macos ]; then
		as_root rm -f "$nginx_default_site"
	fi

	if [ "$OS" = macos ]; then
		nginx -t
		nginx -s reload 2>/dev/null || brew services restart nginx
	else
		as_root nginx -t
		if command_exists systemctl; then
			as_root systemctl reload nginx
		else
			as_root service nginx reload
		fi
	fi

	success "Nginx reverse proxy is configured."
}

check_disk_space() {
	local docker_root available_kb required_kb
	docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
	if [ -z "$docker_root" ] || [ "$docker_root" = ""$'\n'"/" ]; then
		if [ -d /var/lib/docker ]; then
			docker_root="/var/lib/docker"
		else
			docker_root="/"
		fi
	fi
	available_kb="$(df -Pk "$docker_root" 2>/dev/null | awk 'NR == 2 { print $4 }')"
	if [ -z "$available_kb" ]; then
		fail "Unable to measure free space for Docker storage at ${docker_root}. Check the VM disk or mount configuration."
	fi
	required_kb=$((MIN_FREE_GB * 1024 * 1024))

	log "Checking available Docker disk space..."
	printf '[INFO] Docker storage: %s (%s GB free)\n' \
		"$docker_root" "$((available_kb / 1024 / 1024))"
	if [ "$available_kb" -lt "$required_kb" ]; then
		fail "At least ${MIN_FREE_GB} GB free is required on the Docker filesystem. Clean Docker data or increase the VM disk, then retry."
	fi
	success "Enough Docker disk space is available."
}

clone_repository() {
	if [ -f "${APP_DIR}/docker-compose.yml" ] || [ -f "${APP_DIR}/compose.yml" ]; then
		log "Using existing repository at ${APP_DIR}."
		cd -- "$APP_DIR"
		return
	fi

	if [ -d "$APP_DIR" ]; then
		if git -C "$APP_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			log "Using existing Git checkout at ${APP_DIR}."
			cd -- "$APP_DIR"
			return
		fi
		if [ -n "$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
			fail "${APP_DIR} exists and is not an empty Git checkout. Set APP_DIR to another directory or remove this unrelated directory."
		fi
	else
		mkdir -p "$(dirname -- "$APP_DIR")"
	fi

	log "Cloning RAG Agent repository..."
	git clone "$REPO_URL" "$APP_DIR"
	cd -- "$APP_DIR"
	success "Repository cloned to ${APP_DIR}."
}

check_project() {
	[ -f docker-compose.yml ] || [ -f compose.yml ] || \
		fail "docker-compose.yml or compose.yml was not found."
	[ -d be-rag ] || fail "Backend directory 'be-rag' was not found."
	[ -d Fe-rag ] || fail "Frontend directory 'Fe-rag' was not found."
	success "Project structure looks valid."
}

compose() {
	if docker compose version >/dev/null 2>&1; then
		docker compose "$@"
	else
		docker-compose "$@"
	fi
}

deploy() {
	log "Building Docker images..."
	compose build
	success "Docker images built successfully."

	log "Starting Ollama..."
	compose up -d ollama
	wait_for_ollama
	provision_ollama_models

	log "Starting RAG Agent containers..."
	compose up -d backend
	wait_for_http "Backend" "http://127.0.0.1:5000/health/live" 60
	compose up -d frontend
	wait_for_http "Frontend" "http://127.0.0.1:3000/" 60
	check_backend_health
	success "Docker Compose started."
}

wait_for_http() {
	local service_name=$1 url=$2 max_attempts=$3 attempt
	for attempt in $(seq 1 "$max_attempts"); do
		if curl --fail --silent --show-error --max-time 5 "$url" >/dev/null; then
			success "${service_name} is responding."
			return
		fi
		sleep 2
	done
	compose ps
	compose logs --tail=100 "$(printf '%s' "$service_name" | tr '[:upper:]' '[:lower:]')" 2>/dev/null || true
	fail "${service_name} did not respond at ${url}."
}

wait_for_ollama() {
	local attempt health
	for attempt in $(seq 1 30); do
		health="$(docker inspect --format '{{.State.Health.Status}}' ollama 2>/dev/null || true)"
		if [ "$health" = healthy ]; then
			success "Ollama is healthy."
			return
		fi
		if [ "$health" = unhealthy ]; then
			fail "Ollama failed its health check. Check: docker logs ollama"
		fi
		sleep 2
	done
	fail "Ollama did not become healthy within 60 seconds. Check: docker logs ollama"
}

provision_ollama_models() {
	local model
	log "Checking required Ollama models..."
	for model in "${OLLAMA_MODEL:-gemma2:2b}" "${EMBEDDING_MODEL:-nomic-embed-text}"; do
		if docker exec ollama ollama list | awk 'NR > 1 { print $1 }' | grep -Fxq "$model" || \
			{ [[ "$model" != *:* ]] && docker exec ollama ollama list | awk 'NR > 1 { print $1 }' | grep -Fxq "${model}:latest"; }; then
			success "Ollama model is already available: ${model}"
		else
			log "Ollama model is missing; pulling ${model}..."
			docker exec ollama ollama pull "$model"
		fi
	done
	success "Required Ollama models are available."
}

check_backend_health() {
	log "Checking backend health..."
	if ! curl --fail --silent --show-error --max-time 30 http://localhost:5000/api/health; then
		printf '\n'
		fail "Backend health check failed. Check the backend and Ollama container logs."
	fi
	printf '\n'
	success "Backend health check passed."
}

check_containers() {
	local expected service running_services missing=false
	expected="$(compose config --services)"
	running_services="$(compose ps --status running --services)"
	compose ps

	while IFS= read -r service; do
		[ -z "$service" ] && continue
		if ! printf '%s\n' "$running_services" | grep -Fxq "$service"; then
			printf '[ERROR] Service is not running: %s\n' "$service" >&2
			missing=true
		fi
	done <<< "$expected"

	if [ "$missing" = true ]; then
		compose logs --tail=100
		fail "One or more RAG Agent services are not running."
	fi
	success "All RAG Agent services are running."
}

check_nginx_proxy() {
	if ! command_exists curl || ! command_exists nginx; then
		return
	fi

	log "Checking Nginx application proxy..."
	if ! curl --fail --silent --show-error --max-time 10 http://127.0.0.1/ >/dev/null; then
		fail "Nginx is not serving the frontend at http://127.0.0.1/. Check the Nginx configuration and frontend logs."
	fi
	success "Nginx is serving the frontend on port 80."
}

detect_os
install_git
install_docker
install_docker_compose
install_nginx
check_disk_space
clone_repository
check_project
configure_nginx
deploy
check_containers
check_backend_health
check_nginx_proxy

printf '\n[SUCCESS] RAG Agent deployment completed.\n'
printf 'Application: http://localhost/\n'
printf 'Frontend direct: http://localhost:3000\n'
printf 'Backend: http://localhost:5000/api/health\n'
