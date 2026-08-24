#!/usr/bin/env bash

# RAG Agent deployment script for Linux EC2 hosts and macOS.
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/Pratik02-07/rag-agent.git}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${APP_DIR:-$SCRIPT_DIR}"

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
		install_linux_package docker-compose-plugin
	else
		as_root mkdir -p /usr/local/lib/docker/cli-plugins
		command_exists curl || install_linux_package curl
		as_root curl -fsSL \
			https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
			-o /usr/local/lib/docker/cli-plugins/docker-compose
		as_root chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
	fi

	docker compose version >/dev/null 2>&1 || fail "Docker Compose installation failed."
	success "Docker Compose is installed."
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

clone_repository() {
	if [ -f "${APP_DIR}/docker-compose.yml" ] || [ -f "${APP_DIR}/compose.yml" ]; then
		log "Using existing repository at ${APP_DIR}."
		cd -- "$APP_DIR"
		return
	fi
	if [ -e "$APP_DIR" ]; then
		fail "${APP_DIR} exists but is not a valid RAG Agent checkout."
	fi
	log "Cloning RAG Agent repository..."
	mkdir -p "$(dirname -- "$APP_DIR")"
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

	log "Starting RAG Agent containers..."
	compose up -d
	success "Docker Compose started."
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

detect_os
install_git
install_docker
install_docker_compose
install_nginx
clone_repository
check_project
deploy
check_containers

printf '\n[SUCCESS] RAG Agent deployment completed.\n'
printf 'Application: http://localhost:3000\n'
printf 'Backend: http://localhost:5000/api/health\n'
