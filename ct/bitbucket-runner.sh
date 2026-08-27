#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Robe (ComeCaramelos)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://support.atlassian.com/bitbucket-cloud/docs/set-up-runners-for-linux-shell/

APP="Bitbucket-Runner"
var_tags="${var_tags:-ci}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}" # Bitbucket only offers the Linux Shell runner as x86_64 (arm64 is Docker-runner only)
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"

# Values the install script accepts up front (see "Application Settings").
# Without the export they never reach the container.
export var_account_uuid="${var_account_uuid:-}"
export var_repository_uuid="${var_repository_uuid:-}"
export var_runner_uuid="${var_runner_uuid:-}"
export var_oauth_client_id="${var_oauth_client_id:-}"
export var_oauth_client_secret="${var_oauth_client_secret:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/bitbucket-runner/bin/runner.jar ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  LATEST_VERSION=$(curl_with_retry "https://product-downloads.atlassian.com/software/bitbucket/pipelines/CHANGELOG.md" "-" | grep -oP '^## \K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n1)
  if [[ -z "$LATEST_VERSION" ]]; then
    msg_error "Could not determine the latest Bitbucket Runner version."
    exit 1
  fi

  if [[ "$LATEST_VERSION" != "$(cat ~/.bitbucket-runner 2>/dev/null)" ]]; then
    msg_info "Stopping Service"
    systemctl stop bitbucket-runner
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_from_url "https://product-downloads.atlassian.com/software/bitbucket/pipelines/atlassian-bitbucket-pipelines-runner-${LATEST_VERSION}.tar.gz" "/opt/bitbucket-runner"
    echo "$LATEST_VERSION" >~/.bitbucket-runner

    msg_info "Starting Service"
    systemctl start bitbucket-runner
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

if [[ -n "${mode:-}" ]]; then
  if [[ -z "${var_account_uuid:-}" || -z "${var_runner_uuid:-}" || -z "${var_oauth_client_id:-}" || -z "${var_oauth_client_secret:-}" ]]; then
    msg_error "var_account_uuid, var_runner_uuid, var_oauth_client_id and var_oauth_client_secret are required for unattended installs."
    exit 1
  fi
fi

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} After first boot, the runner registers itself with Bitbucket using the credentials you provided.${CL}"
