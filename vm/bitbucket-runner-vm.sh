#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://support.atlassian.com/bitbucket-cloud/docs/set-up-and-use-runners-for-linux/

source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/vm/cloud-init.func") 2>/dev/null || true
load_functions

function header_info {
  clear
  cat <<"EOF"
    ____  _ __  __               __        __     ____
   / __ )(_) /_/ /_  __  _______/ /_____  / /_   / __ \__  ______  ____  ___  _____
  / __  / / __/ __ \/ / / / ___/ //_/ _ \/ __/  / /_/ / / / / __ \/ __ \/ _ \/ ___/
 / /_/ / / /_/ /_/ / /_/ / /__/ ,< /  __/ /_   / _, _/ /_/ / / / / / / /  __/ /
/_____/_/\__/_.___/\__,_/\___/_/|_|\___/\__/  /_/ |_|\__,_/_/ /_/_/ /_/\___/_/
EOF
}

APP="Bitbucket Runner"
APP_TYPE="vm"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="bitbucket-runner"
THIN="discard=on,ssd=1,"
USE_CLOUD_INIT="no"
BB_ACCOUNT_UUID=""
BB_REPOSITORY_UUID=""
BB_RUNNER_UUID=""
BB_OAUTH_CLIENT_ID=""
BB_OAUTH_CLIENT_SECRET=""

# OS selection defaults
OS_CHOICE="debian13"
OS_LABEL="Debian 13 (Trixie)"

header_info
echo -e "\n Loading..."

set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null

if vm_confirm_new_vm "$APP" "This will create a New $APP. Proceed?"; then
  :
else
  header_info && exit_script
fi

check_root
arch_check
pve_check
ssh_check

# ---------------------------------------------------------------------------
# OS Selection
# ---------------------------------------------------------------------------
function select_os() {
  local choice
  if choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "OS SELECTION" \
    --radiolist "Choose the base operating system:" --cancel-button Exit-Script 12 68 2 \
    "debian13" "Debian 13 (Trixie)" ON \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble Numbat)" OFF \
    3>&1 1>&2 2>&3); then
    OS_CHOICE="$choice"
    case "$OS_CHOICE" in
    debian13)
      OS_LABEL="Debian 13 (Trixie)"
      ;;
    ubuntu2404)
      OS_LABEL="Ubuntu 24.04 LTS (Noble Numbat)"
      ;;
    esac
    echo -e "${OS}${BOLD}${DGN}Base OS: ${BGN}${OS_LABEL}${CL}"
  else
    exit_script
  fi
}

select_os
if [[ "$OS_CHOICE" == "ubuntu2404" ]]; then
  CI_DEFAULT_USER="ubuntu"
else
  CI_DEFAULT_USER="debian"
fi
vm_prompt_cloud_init "$CI_DEFAULT_USER"

function default_settings() {
  VMID=$(get_valid_nextid)
  vm_apply_machine_type "q35"
  DISK_SIZE="20G"
  DISK_CACHE=""
  HN="bitbucket-runner"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="2"
  RAM_SIZE="8192"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"

  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$(vm_machine_type_label "$MACHINE_TYPE")${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}${USE_CLOUD_INIT}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}${START_VM}${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a ${OS_LABEL} Bitbucket Runner VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}${USE_CLOUD_INIT}${CL}"
  vm_prompt_vmid "${VMID:-$(get_valid_nextid)}"
  vm_prompt_machine_type "q35"
  vm_prompt_disk_size "${DISK_SIZE:-20G}" "Set Disk Size in GiB (min. 20 recommended)"
  vm_prompt_disk_cache "none"
  vm_prompt_hostname "bitbucket-runner"
  vm_prompt_cpu_model "host"
  vm_prompt_cpu_cores "2"
  vm_prompt_ram "8192"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_start_vm "yes"

  if vm_confirm_advanced_settings "Ready to create a ${OS_LABEL} Bitbucket Runner VM?"; then
    echo -e "${CREATING}${BOLD}${DGN}Creating a ${OS_LABEL} Bitbucket Runner VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if vm_choose_settings_mode; then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

start_script

# ---------------------------------------------------------------------------
# Runner credentials (shown only once in the Bitbucket UI)
# ---------------------------------------------------------------------------
function prompt_runner_credentials() {
  msg_info "Runner credentials"
  stop_spinner
  echo -e "${INFO}${BOLD}${DGN}Where to find these values:${CL}"
  echo -e "${TAB}Bitbucket UI -> Workspace settings -> Workspace runners"
  echo -e "${TAB}(or repo Settings -> Runners) -> Add runner -> 'Run step'."
  echo -e "${TAB}Read the values from the -e flags of the docker command."
  echo -e "${YWB}These values are shown only ONCE - save them now!${CL}"

  while true; do
    if BB_ACCOUNT_UUID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "RUNNER CREDENTIALS" \
      --inputbox "Account UUID (from the -e ACCOUNT_UUID=... flag):" 8 65 "" \
      --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [[ -z "$BB_ACCOUNT_UUID" ]]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "RUNNER CREDENTIALS" \
          --msgbox "Account UUID is required." 8 50
        continue
      fi
      echo -e "${INFO}${BOLD}${DGN}Account UUID: ${BGN}${BB_ACCOUNT_UUID}${CL}"
      break
    else
      exit_script
    fi
  done

  while true; do
    if BB_REPOSITORY_UUID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "RUNNER CREDENTIALS" \
      --inputbox "Repository UUID (from the -e REPOSITORY_UUID=... flag).\nLeave empty for workspace runners:" 9 65 "" \
      --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      echo -e "${INFO}${BOLD}${DGN}Repository UUID: ${BGN}${BB_REPOSITORY_UUID:-<empty>}${CL}"
      break
    else
      exit_script
    fi
  done

  while true; do
    if BB_RUNNER_UUID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "RUNNER CREDENTIALS" \
      --inputbox "Runner UUID (from the -e RUNNER_UUID=... flag):" 8 65 "" \
      --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [[ -z "$BB_RUNNER_UUID" ]]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "RUNNER CREDENTIALS" \
          --msgbox "Runner UUID is required." 8 50
        continue
      fi
      echo -e "${INFO}${BOLD}${DGN}Runner UUID: ${BGN}${BB_RUNNER_UUID}${CL}"
      break
    else
      exit_script
    fi
  done

  while true; do
    if BB_OAUTH_CLIENT_ID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "RUNNER CREDENTIALS" \
      --inputbox "OAuth Client ID (from the -e OAUTH_CLIENT_ID=... flag):" 8 65 "" \
      --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [[ -z "$BB_OAUTH_CLIENT_ID" ]]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "RUNNER CREDENTIALS" \
          --msgbox "OAuth Client ID is required." 8 50
        continue
      fi
      echo -e "${INFO}${BOLD}${DGN}OAuth Client ID: ${BGN}${BB_OAUTH_CLIENT_ID}${CL}"
      break
    else
      exit_script
    fi
  done

  while true; do
    if BB_OAUTH_CLIENT_SECRET=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "RUNNER CREDENTIALS" \
      --passwordbox "OAuth Client Secret (from the -e OAUTH_CLIENT_SECRET=... flag):" 8 65 \
      --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [[ -z "$BB_OAUTH_CLIENT_SECRET" ]]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "RUNNER CREDENTIALS" \
          --msgbox "OAuth Client Secret is required." 8 50
        continue
      fi
      echo -e "${INFO}${BOLD}${DGN}OAuth Client Secret: ${BGN}********${CL}"
      break
    else
      exit_script
    fi
  done
}

prompt_runner_credentials

# ---------------------------------------------------------------------------
# RAM warning: Bitbucket Runner works best with at least 8GB
# ---------------------------------------------------------------------------
if [[ "$RAM_SIZE" -lt 8192 ]]; then
  msg_warn "Bitbucket Runner works best with at least 8192 MiB RAM. You have selected ${RAM_SIZE} MiB."
  if ! whiptail --backtitle "Proxmox VE Helper Scripts" --title "LOW RAM DETECTED" \
    --yesno "Bitbucket Runner works best with at least 8GB of RAM.\nYou have selected ${RAM_SIZE} MiB.\n\nContinue anyway?" 10 60; then
    exit_script
  fi
fi

post_to_api_vm

vm_select_storage "$HN"
vm_define_disk_references 2
DISK_IMPORT="-format ${DISK_IMPORT_FORMAT}"

# ---------------------------------------------------------------------------
# Download cloud image (cached)
# ---------------------------------------------------------------------------
case "$OS_CHOICE" in
ubuntu2404) URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img" ;;
debian13)
  if [ "$USE_CLOUD_INIT" = "yes" ]; then
    URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  else
    URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2"
  fi
  ;;
esac

msg_info "Retrieving the URL for the ${OS_LABEL} Cloud Image"
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"

CACHE_DIR="/var/lib/vz/template/cache"
CACHE_FILE="${CACHE_DIR}/$(basename "$URL")"
mkdir -p "$CACHE_DIR"

if [[ ! -s "$CACHE_FILE" ]]; then
  curl -f#SL -o "$CACHE_FILE" "$URL"
  echo -en "\e[1A\e[0K"
  msg_ok "Downloaded ${CL}${BL}$(basename "$CACHE_FILE")${CL}"
else
  msg_ok "Using cached image ${CL}${BL}$(basename "$CACHE_FILE")${CL}"
fi

# ---------------------------------------------------------------------------
# Image customization (Docker + Bitbucket Runner)
# ---------------------------------------------------------------------------
if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing libguestfs-tools for virt-customize"
  $STD apt install -y libguestfs-tools
  msg_ok "Installed libguestfs-tools"
fi

msg_info "Customizing the ${OS_LABEL} image (Docker + Bitbucket Runner)"
WORK_FILE=$(mktemp --suffix=.qcow2)
cp "$CACHE_FILE" "$WORK_FILE"
export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1

if ! virt-customize -q -a "$WORK_FILE" --install qemu-guest-agent,curl,ca-certificates >/dev/null 2>&1; then
  msg_error "Failed to install base packages in the image"
  exit 1
fi

if ! virt-customize -q -a "$WORK_FILE" --run-command "curl -fsSL https://get.docker.com | sh" >/dev/null 2>&1 ||
  ! virt-customize -q -a "$WORK_FILE" --run-command "systemctl enable docker" >/dev/null 2>&1; then
  msg_error "Failed to install Docker in the image"
  exit 1
fi

# Atlassian best practices: no swap, low swappiness, weekly prune
if ! virt-customize -q -a "$WORK_FILE" --run-command "sed -ri '/^[[:space:]]*#/!s/^[^#]*\sswap\s.*$//' /etc/fstab" >/dev/null 2>&1 ||
  ! virt-customize -q -a "$WORK_FILE" --run-command "grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness = 1' >> /etc/sysctl.conf" >/dev/null 2>&1 ||
  ! virt-customize -q -a "$WORK_FILE" --run-command "(crontab -l 2>/dev/null; echo '0 0 * * 0 docker system prune -af') | crontab -" >/dev/null 2>&1; then
  msg_error "Failed to apply Atlassian best practices (swap/swappiness/prune) in the image"
  exit 1
fi

# Upload runner credentials (host variables expanded into the image)
BB_ENV_TMP=$(mktemp)
cat >"$BB_ENV_TMP" <<ENVEOF
ACCOUNT_UUID="${BB_ACCOUNT_UUID}"
REPOSITORY_UUID="${BB_REPOSITORY_UUID}"
RUNNER_UUID="${BB_RUNNER_UUID}"
OAUTH_CLIENT_ID="${BB_OAUTH_CLIENT_ID}"
OAUTH_CLIENT_SECRET="${BB_OAUTH_CLIENT_SECRET}"
ENVEOF
if ! virt-customize -q -a "$WORK_FILE" --upload "${BB_ENV_TMP}:/root/bitbucket-runner.env" >/dev/null 2>&1; then
  msg_error "Failed to upload runner credentials to the image"
  exit 1
fi
rm -f "$BB_ENV_TMP"

# Upload first-boot setup script (no host variable expansion - single-quoted heredoc)
BB_SETUP_TMP=$(mktemp)
cat >"$BB_SETUP_TMP" <<'SETUPEOF'
#!/bin/bash
exec > /var/log/bitbucket-runner-setup.log 2>&1
echo "[$(date)] Bitbucket Runner setup started"
for i in {1..60}; do docker info >/dev/null 2>&1 && break; sleep 5; done
set -a; source /root/bitbucket-runner.env; set +a
docker pull docker-public.packages.atlassian.com/sox/atlassian/bitbucket-pipelines-runner
docker container rm -f bitbucket-runner 2>/dev/null || true
docker run -d --restart unless-stopped --name bitbucket-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/docker/containers:/var/lib/docker/containers:ro \
  -v /tmp:/tmp \
  -e ACCOUNT_UUID="$ACCOUNT_UUID" \
  -e REPOSITORY_UUID="$REPOSITORY_UUID" \
  -e RUNNER_UUID="$RUNNER_UUID" \
  -e OAUTH_CLIENT_ID="$OAUTH_CLIENT_ID" \
  -e OAUTH_CLIENT_SECRET="$OAUTH_CLIENT_SECRET" \
  -e WORKING_DIRECTORY=/tmp \
  -e RUNTIME_PREREQUISITES_ENABLED=true \
  docker-public.packages.atlassian.com/sox/atlassian/bitbucket-pipelines-runner
echo "[$(date)] Bitbucket Runner setup finished"
touch /root/.bitbucket-runner-setup-done
SETUPEOF
if ! virt-customize -q -a "$WORK_FILE" --upload "${BB_SETUP_TMP}:/root/bitbucket-runner-setup.sh" --run-command "chmod +x /root/bitbucket-runner-setup.sh" >/dev/null 2>&1; then
  msg_error "Failed to upload the first-boot setup script to the image"
  exit 1
fi
rm -f "$BB_SETUP_TMP"

# Upload first-boot systemd service
BB_SVC_TMP=$(mktemp)
cat >"$BB_SVC_TMP" <<'SVCEOF'
[Unit]
Description=Bitbucket Pipelines Runner first-boot setup
After=network-online.target docker.service
Wants=network-online.target
ConditionPathExists=!/root/.bitbucket-runner-setup-done

[Service]
Type=oneshot
ExecStart=/root/bitbucket-runner-setup.sh
TimeoutStartSec=600
StandardOutput=journal+console
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF
if ! virt-customize -q -a "$WORK_FILE" --upload "${BB_SVC_TMP}:/etc/systemd/system/bitbucket-runner-setup.service" --run-command "systemctl enable bitbucket-runner-setup.service" >/dev/null 2>&1; then
  msg_error "Failed to upload the first-boot setup service to the image"
  exit 1
fi
rm -f "$BB_SVC_TMP"

msg_info "Finalizing image (hostname, SSH config)"
virt-customize -q -a "$WORK_FILE" --hostname "${HN}" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "truncate -s 0 /etc/machine-id" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "rm -f /var/lib/dbus/machine-id" >/dev/null 2>&1 || true

# Configure SSH for Cloud-Init
if [ "$USE_CLOUD_INIT" = "yes" ]; then
  virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
else
  # Configure auto-login for nocloud images (no Cloud-Init)
  virt-customize -q -a "$WORK_FILE" --run-command "mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d" >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" --run-command 'cat > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF' >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" --run-command "mkdir -p /etc/systemd/system/getty@tty1.service.d" >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" --run-command 'cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF' >/dev/null 2>&1 || true
fi
msg_ok "Finalized image"

FILE="$WORK_FILE"
msg_ok "Docker + Bitbucket Runner pre-installed in the image"

msg_info "Creating a ${OS_LABEL} Bitbucket Runner VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID $FILE $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
rm -f "$WORK_FILE" 2>/dev/null || true
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -boot order=scsi0 \
  -serial0 socket >/dev/null
set_description

msg_info "Resizing disk to $DISK_SIZE"
qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null

if [ "$USE_CLOUD_INIT" = "yes" ] && declare -f setup_cloud_init >/dev/null 2>&1; then
  case "$OS_CHOICE" in
  ubuntu2404) setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes" "${CLOUDINIT_USER:-ubuntu}" "${CLOUDINIT_NETWORK_MODE:-dhcp}" "${CLOUDINIT_IP:-}" "${CLOUDINIT_GW:-}" "${CLOUDINIT_DNS:-${CLOUDINIT_DNS_SERVERS:-1.1.1.1 8.8.8.8}}" ;;
  debian13) setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes" "${CLOUDINIT_USER:-debian}" "${CLOUDINIT_NETWORK_MODE:-dhcp}" "${CLOUDINIT_IP:-}" "${CLOUDINIT_GW:-}" "${CLOUDINIT_DNS:-${CLOUDINIT_DNS_SERVERS:-1.1.1.1 8.8.8.8}}" ;;
  esac
else
  # Attach cloud-init drive for basic DHCP networking even without interactive CI config
  qm set $VMID --ide2 "${STORAGE}:cloudinit" >/dev/null 2>&1 ||
    qm set $VMID --scsi1 "${STORAGE}:cloudinit" >/dev/null 2>&1 || true
  qm set $VMID --ipconfig0 "ip=dhcp" >/dev/null 2>&1 || true
fi

msg_ok "Created a ${OS_LABEL} Bitbucket Runner VM ${CL}${BL}(${HN})"
if [ "$START_VM" = "yes" ]; then
  msg_info "Starting Bitbucket Runner VM"
  qm start $VMID
  msg_ok "Started Bitbucket Runner VM"
fi

post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"

# Access line depends on the user's Cloud-Init choice (not on success/failure)
if [ "$USE_CLOUD_INIT" = "yes" ]; then
  BB_ACCESS="Cloud-Init user and password are shown below.                  │"
else
  BB_ACCESS="root auto-login on the serial console (ttyS0) or on tty1.      │"
fi

cat <<INSTRUCTIONS

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    BITBUCKET RUNNER VM - READY                          │
  ├─────────────────────────────────────────────────────────────────────────┤
  │  Docker and the Bitbucket self-hosted runner are pre-installed in       │
  │  the image. The runner is configured ONLY on first boot (service        │
  │  bitbucket-runner-setup).                                               │
  │                                                                         │
  │  Access: ${BB_ACCESS}
  │                                                                         │
  │  Verify after first boot:                                               │
  │    - journalctl -u bitbucket-runner-setup -f                            │
  │    - docker ps (container: bitbucket-runner)                            │
  │    - The runner shows as ONLINE in the Bitbucket UI                     │
  │                                                                         │
  │  Setup log: /var/log/bitbucket-runner-setup.log                         │
  │                                                                         │
  │  Update the runner version:                                             │
  │    docker pull docker-public.packages.atlassian.com/sox/atlassian/      │
  │      bitbucket-pipelines-runner                                         │
  │    docker container rm -f bitbucket-runner                              │
  │    then re-run the SAME docker run command (tokens do not change).      │
  │                                                                         │
  │  Swap disabled, vm.swappiness=1 and weekly 'docker system prune -af'    │
  │    cron job are already configured.                                     │
  └─────────────────────────────────────────────────────────────────────────┘

INSTRUCTIONS

if [ "$USE_CLOUD_INIT" = "yes" ] && declare -f display_cloud_init_info >/dev/null 2>&1; then
  display_cloud_init_info "$VMID" "$HN"
fi
