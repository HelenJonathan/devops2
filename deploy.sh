#!/bin/sh
# POSIX-compliant deploy script for Stage-1 Task
# Usage: ./deploy.sh      (interactive prompts)
#        ./deploy.sh --cleanup   (remove deployed containers & nginx config on remote)
set -eu

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOGFILE="deploy_${TIMESTAMP}.log"

log() { printf '%s %s\n' "[INFO]" "$*" | tee -a "$LOGFILE"; }
warn() { printf '%s %s\n' "[WARN]" "$*" | tee -a "$LOGFILE"; }
err() { printf '%s %s\n' "[ERROR]" "$*" | tee -a "$LOGFILE" 1>&2; }
die() { err "$*"; exit 1; }

trap 'err "Unexpected error. See $LOGFILE"; exit 2' INT TERM HUP

usage() {
   cat <<-USAGE
Usage: $0 [--cleanup]

Options:
   --cleanup    Remove deployed containers and nginx config on remote host then exit

This script will prompt for the parameters interactively if not provided as env vars.
It requires 'ssh' and either 'rsync' or 'scp' to be available locally.
USAGE
}

if [ "${1:-}" = "--help" ]; then
   usage
   exit 0
fi

DO_CLEANUP=0
if [ "${1:-}" = "--cleanup" ]; then
   DO_CLEANUP=1
fi

prompt() {
   # prompt <varname> <prompt text> <default>
   varname=$1; shift
   prompt_text=$1; shift
   default=$1; shift || true

   if [ -n "$default" ]; then
      printf '%s [%s]: ' "$prompt_text" "$default"
   else
      printf '%s: ' "$prompt_text"
   fi

   read val
   if [ -z "$val" ]; then
      val=$default
   fi
   # set caller var
   eval "$varname=\"$val\""
}

# Collect parameters (interactive)
prompt GIT_URL "Git repository URL (https)" ""
[ -n "$GIT_URL" ] || die "Git repository URL is required"

prompt GIT_PAT "Personal Access Token (PAT) (or press ENTER to use public repo)" ""
prompt GIT_BRANCH "Branch name" "main"
prompt SSH_USER "Remote SSH username" "ubuntu"
prompt SSH_HOST "Remote server IP/hostname" ""
[ -n "$SSH_HOST" ] || die "Remote SSH host is required"
prompt SSH_KEY "SSH private key path (absolute or relative)" "~/.ssh/id_rsa"
prompt APP_PORT "Application internal container port" "3000"

REMOTE_PROJECT_DIR="/home/${SSH_USER}/deployed_app"

log "Parameters summary:"
log "  Repo: $GIT_URL (branch: $GIT_BRANCH)"
log "  Remote: ${SSH_USER}@${SSH_HOST}"
log "  SSH key: ${SSH_KEY}"
log "  Remote project dir: ${REMOTE_PROJECT_DIR}"

# Build git clone URL (support PAT if provided)
if [ -n "$GIT_PAT" ]; then
   CLONE_URL=$(printf '%s' "$GIT_URL" | sed -E "s#https://#https://${GIT_PAT}@#")
else
   CLONE_URL=$GIT_URL
fi

# Local command checks
command -v ssh >/dev/null 2>&1 || die "ssh is required locally"
if ! command -v rsync >/dev/null 2>&1 && ! command -v scp >/dev/null 2>&1; then
   die "rsync or scp is required locally"
fi

ssh_opts="-o BatchMode=yes -o StrictHostKeyChecking=no -i ${SSH_KEY}"

run_ssh() {
   # run_ssh "command"
   cmd=$1
   ssh $ssh_opts ${SSH_USER}@${SSH_HOST} "$cmd"
}

if [ "$DO_CLEANUP" -eq 1 ]; then
   log "Running cleanup on remote host..."
   run_ssh "sudo docker compose -f ${REMOTE_PROJECT_DIR}/docker-compose.yml down --remove-orphans || true; sudo rm -f /etc/nginx/sites-enabled/deployed_app.conf /etc/nginx/sites-available/deployed_app.conf || true"
   log "Cleanup finished."
   exit 0
fi

# Local clone or pull
TMP_CLONE_DIR="./.deploy_tmp_repo"
if [ -d "$TMP_CLONE_DIR" ]; then
   log "Updating existing temporary clone"
   (cd "$TMP_CLONE_DIR" && git fetch --all --prune && git checkout "$GIT_BRANCH" && git pull origin "$GIT_BRANCH") || die "Failed to update repo"
else
   log "Cloning repository"
   rm -rf "$TMP_CLONE_DIR"
   git clone --branch "$GIT_BRANCH" "$CLONE_URL" "$TMP_CLONE_DIR" 2>&1 | tee -a "$LOGFILE" || die "Git clone failed"
fi

if [ ! -f "$TMP_CLONE_DIR/Dockerfile" ] && [ ! -f "$TMP_CLONE_DIR/docker-compose.yml" ]; then
   die "Repository must contain a Dockerfile or docker-compose.yml"
fi

log "Testing SSH connectivity to remote host"
if ! ssh $ssh_opts ${SSH_USER}@${SSH_HOST} 'echo ok' >/dev/null 2>&1; then
   die "SSH connection failed. Check SSH_USER, SSH_HOST and SSH_KEY"
fi
log "SSH connectivity OK"

# Prepare remote: attempt apt-based install (Debian/Ubuntu). Adjust if remote uses other distro.
log "Preparing remote environment (attempting apt-based installs where required)"
run_ssh "set -e; sudo apt-get update -y || true; if ! command -v docker >/dev/null 2>&1; then curl -fsSL https://get.docker.com | sudo sh; fi; sudo usermod -aG docker ${SSH_USER} || true; if ! command -v docker-compose >/dev/null 2>&1; then sudo apt-get install -y docker-compose-plugin || true; fi; if ! command -v nginx >/dev/null 2>&1; then sudo apt-get install -y nginx || true; fi; sudo systemctl enable --now docker || true; sudo systemctl enable --now nginx || true; docker --version || true; nginx -v || true"

log "Syncing project files to remote host"
if command -v rsync >/dev/null 2>&1; then
   RSYNC_EXCLUDES='--exclude .git --exclude node_modules --exclude .env'
   rsync -avz $RSYNC_EXCLUDES -e "ssh $ssh_opts" "$TMP_CLONE_DIR/" ${SSH_USER}@${SSH_HOST}:"${REMOTE_PROJECT_DIR}/" | tee -a "$LOGFILE"
else
   scp -r -i "$SSH_KEY" "$TMP_CLONE_DIR" ${SSH_USER}@${SSH_HOST}:"${REMOTE_PROJECT_DIR}" || die "scp failed"
fi

log "Deploying application on remote using docker compose"
run_ssh "set -e; cd ${REMOTE_PROJECT_DIR}; if [ -f docker-compose.yml ]; then sudo docker compose up -d --build; elif [ -f Dockerfile ]; then sudo docker build -t deployed_app_image . && sudo docker run -d --name deployed_app -p ${APP_PORT}:${APP_PORT} deployed_app_image; else echo 'No compose or Dockerfile' >&2; exit 1; fi"

log "Configuring Nginx reverse proxy on remote"
NGINX_CONF="server { listen 80; server_name _; location / { proxy_pass http://127.0.0.1:${APP_PORT}; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto $scheme; } }"
run_ssh "printf '%s' \"${NGINX_CONF}\" | sudo tee /etc/nginx/sites-available/deployed_app.conf >/dev/null; sudo ln -sf /etc/nginx/sites-available/deployed_app.conf /etc/nginx/sites-enabled/deployed_app.conf; sudo nginx -t; sudo systemctl reload nginx"

log "Validating deployment"
run_ssh "sudo docker ps --filter name=deployed_app --format 'table {{.Names}}\t{{.Status}}' || sudo docker ps --format 'table {{.Names}}\t{{.Status}}'"
run_ssh "curl -fsS --max-time 5 http://127.0.0.1:${APP_PORT} >/dev/null && echo 'LOCAL_OK' || echo 'LOCAL_FAIL'"

log "Final checks from control host"
log "Checking gateway via SSH-exposed Nginx (http://${SSH_HOST})"
if curl -fsS --max-time 5 "http://${SSH_HOST}" >/dev/null 2>&1; then
   log "HTTP gateway reachable"
else
   warn "HTTP gateway not reachable from control host (may be firewall). Try remote curl via SSH to inspect service locally."
fi

log "Deployment finished. See $LOGFILE for details."