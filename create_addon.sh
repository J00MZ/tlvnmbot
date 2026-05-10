#!/usr/bin/env bash
# ==============================================================================
# HA Add-on Setup Script
# Description: Bootstraps and updates a local Home Assistant Add-on using gh.
# ==============================================================================

# Fail fast on errors, unset variables, and pipeline failures
set -euo pipefail

# ==============================================================================
# 1. Configuration
# ==============================================================================
ADDONS_BASE_DIR="${ADDONS_BASE_DIR:-/addons}"
ADDON_SLUG="${ADDON_SLUG:-tlvnmbot}"
ADDON_DIR="$ADDONS_BASE_DIR/${ADDON_SLUG}_addon"

# Replaced REPO_URL with GH_REPO for the GitHub CLI
GH_REPO="${GH_REPO:-J00MZ/tlvnmbot}"
REPO_BRANCH="${REPO_BRANCH:-master}"

ADDON_NAME="${ADDON_NAME:-TLV Telegram Bot}"
ADDON_VERSION="${ADDON_VERSION:-1.0.0}"
ADDON_DESC="${ADDON_DESC:-Custom Telegram bot running via Poetry.}"

# ==============================================================================
# 2. Helper Functions
# ==============================================================================
log_info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_succ() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
log_err()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

setup_github_cli() {
    log_info "Checking for GitHub CLI (gh)..."
    
    # Check if gh is installed
    if ! command -v gh >/dev/null 2>&1; then
        log_warn "GitHub CLI not found. Attempting to install on Alpine..."
        
        # Check if we are on Alpine (apk is present)
        if command -v apk >/dev/null 2>&1; then
            # Attempt to install, fail if it doesn't succeed
            apk add --no-cache github-cli || log_err "Failed to install github-cli via apk."
            log_succ "GitHub CLI successfully installed."
        else
            log_err "apk package manager not found. This script can only auto-install 'gh' on Alpine Linux. Please install 'gh' manually."
        fi
    else
        log_succ "GitHub CLI is already installed."
    fi

    # Verify authentication status
    log_info "Verifying GitHub CLI authentication..."
    if ! gh auth status >/dev/null 2>&1; then
        log_err "GitHub CLI is not authenticated.\nPlease run 'gh auth login' to authenticate before running this script."
    else
        log_succ "GitHub CLI is authenticated and configured."
    fi
}

check_prereqs() {
    local cmds=("mkdir" "chmod" "cat" "jq")
    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            # Auto-install jq on Alpine if missing, as it's required for HA addon scripts
            if [ "$cmd" == "jq" ] && command -v apk >/dev/null 2>&1; then
                log_warn "'jq' not found. Installing..."
                apk add --no-cache jq || log_err "Failed to install jq."
            else
                log_err "Required command not found: $cmd"
            fi
        fi
    done
}

# ==============================================================================
# 3. Execution
# ==============================================================================

log_info "Starting Add-on setup for '$ADDON_NAME'..."

# Validate environment and GitHub CLI
setup_github_cli
check_prereqs

# Ensure the target directory exists
log_info "Ensuring addon directory exists: $ADDON_DIR"
mkdir -p "$ADDON_DIR"
cd "$ADDON_DIR"

# Idempotent GitHub CLI Sync
if [ -d "$ADDON_SLUG/.git" ]; then
    log_info "Repository found at $ADDON_SLUG. Syncing via GitHub CLI..."
    cd "$ADDON_SLUG"
    # Using gh repo sync to force-sync the local repository to match the remote branch
    gh repo sync --branch "$REPO_BRANCH" --force || log_err "Failed to sync repository via gh."
    cd ..
else
    log_info "Cloning repository $GH_REPO via GitHub CLI..."
    # Clone and pass standard git arguments after '--' to specify the branch
    gh repo clone "$GH_REPO" "$ADDON_SLUG" -- -b "$REPO_BRANCH" || log_err "Failed to clone repository via gh."
fi

# ==============================================================================
# 4. File Generation
# ==============================================================================

log_info "Generating config.yaml..."
cat << EOF > config.yaml
name: "${ADDON_NAME}"
description: "${ADDON_DESC}"
version: "${ADDON_VERSION}"
slug: "${ADDON_SLUG}"
init: false
arch:
  - aarch64
  - amd64
  - armv7
  - armhf
startup: application
boot: auto
options:
  TG_TOKEN: ""
schema:
  TG_TOKEN: "str"
EOF

log_info "Generating Dockerfile..."
cat << EOF > Dockerfile
ARG BUILD_FROM=python:3.11-alpine
FROM \$BUILD_FROM

# Install jq for config parsing, bash, and git (needed for pip git dependencies)
RUN apk add --no-cache jq bash git

# Install poetry globally
RUN pip install --no-cache-dir poetry

# Set the working directory
WORKDIR /app

# Copy the synced repo into the container
COPY ${ADDON_SLUG}/ /app/

# Install dependencies
RUN poetry install --no-root

# Setup the entrypoint script
COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
EOF

log_info "Generating run.sh entrypoint..."
cat << 'EOF' > run.sh
#!/usr/bin/env bash
set -eo pipefail

# Extract token from HA options
export TG_TOKEN=$(jq --raw-output '.TG_TOKEN' /data/options.json)

if [ -z "$TG_TOKEN" ] || [ "$TG_TOKEN" == "null" ]; then
    echo "[ERROR] TG_TOKEN is missing. Please set it in the HA Add-on Configuration tab."
    exit 1
fi

echo "[INFO] Starting $ADDON_NAME..."

cd /app
# Exec replaces the shell with the Python process for proper signal handling
exec poetry run python3 app.py
EOF

log_info "Applying execute permissions to run.sh..."
chmod +x run.sh

# ==============================================================================
# 5. Summary
# ==============================================================================
log_succ "======================================================="
log_succ "Add-on '$ADDON_NAME' successfully reconciled!"
log_succ "Location: $ADDON_DIR"
log_succ "If this is a code update, go to the HA Add-on UI and click 'Rebuild'."
log_succ "======================================================="
