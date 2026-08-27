#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Robe (ComeCaramelos)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://support.atlassian.com/bitbucket-cloud/docs/set-up-runners-for-linux-shell/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y git
msg_ok "Installed Dependencies"

JAVA_VERSION="25" setup_java

if [[ -z "${var_account_uuid:-}" ]]; then
  read -r -p "${TAB3}Account UUID (from the Bitbucket runner setup command): " var_account_uuid
fi
if [[ -z "${var_account_uuid:-}" ]]; then
  msg_error "No account UUID provided. Cannot continue."
  exit 1
fi

if [[ -z "${var_repository_uuid:-}" ]]; then
  read -r -p "${TAB3}Repository UUID (leave blank for a workspace runner): " var_repository_uuid
fi

if [[ -z "${var_runner_uuid:-}" ]]; then
  read -r -p "${TAB3}Runner UUID: " var_runner_uuid
fi
if [[ -z "${var_runner_uuid:-}" ]]; then
  msg_error "No runner UUID provided. Cannot continue."
  exit 1
fi

if [[ -z "${var_oauth_client_id:-}" ]]; then
  read -r -p "${TAB3}OAuth Client ID: " var_oauth_client_id
fi
if [[ -z "${var_oauth_client_id:-}" ]]; then
  msg_error "No OAuth Client ID provided. Cannot continue."
  exit 1
fi

if [[ -z "${var_oauth_client_secret:-}" ]]; then
  read -r -p "${TAB3}OAuth Client Secret: " var_oauth_client_secret
fi
if [[ -z "${var_oauth_client_secret:-}" ]]; then
  msg_error "No OAuth Client Secret provided. Cannot continue."
  exit 1
fi

RUNNER_VERSION=$(curl_with_retry "https://product-downloads.atlassian.com/software/bitbucket/pipelines/CHANGELOG.md" "-" | grep -oP '^## \K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n1)
if [[ -z "$RUNNER_VERSION" ]]; then
  msg_error "Could not determine the latest Bitbucket Runner version."
  exit 1
fi

fetch_and_deploy_from_url "https://product-downloads.atlassian.com/software/bitbucket/pipelines/atlassian-bitbucket-pipelines-runner-${RUNNER_VERSION}.tar.gz" "/opt/bitbucket-runner"
echo "$RUNNER_VERSION" >~/.bitbucket-runner

msg_info "Configuring Runner"
mkdir -p /opt/bitbucket-runner_data
cat <<EOF >/opt/bitbucket-runner_data/runner.env
ACCOUNT_UUID=${var_account_uuid}
REPOSITORY_UUID=${var_repository_uuid}
RUNNER_UUID=${var_runner_uuid}
OAUTH_CLIENT_ID=${var_oauth_client_id}
OAUTH_CLIENT_SECRET=${var_oauth_client_secret}
WORKING_DIRECTORY=/opt/bitbucket-runner_data
RUNTIME=linux.shell
EOF
chmod +x /opt/bitbucket-runner/bin/start.sh
msg_ok "Configured Runner"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/bitbucket-runner.service
[Unit]
Description=Bitbucket Pipelines self-hosted runner (Linux Shell)
Documentation=https://support.atlassian.com/bitbucket-cloud/docs/set-up-runners-for-linux-shell/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bitbucket-runner/bin
EnvironmentFile=/opt/bitbucket-runner_data/runner.env
ExecStart=/opt/bitbucket-runner/bin/start.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now bitbucket-runner
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
