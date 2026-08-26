#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://support.atlassian.com/bitbucket-cloud/docs/configure-a-self-hosted-runner/

source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/vm/cloud-init.func") 2>/dev/null || true
load_functions

function header_info {
  clear
  cat <<"EOF"
    ____  _ __  __               __        __     ____                                 _    ____  ___
   / __ )(_) /_/ /_  __  _______/ /_____  / /_   / __ \__  ______  ____  ___  _____   | |  / /  |/  /
  / __  / / __/ __ \/ / / / ___/ //_/ _ \/ __/  / /_/ / / / / __ \/ __ \/ _ \/ ___/   | | / / /|_/ /
 / /_/ / / /_/ /_/ / /_/ / /__/ ,< /  __/ /_   / _, _/ /_/ / / / / / / /  __/ /       | |/ / /  / /
/_____/_/\__/_.___/\__,_/\___/_/|_|\___/\__/  /_/ |_|\__,_/_/ /_/_/ /_/\___/_/        |___/_/  /_/
EOF
}

APP="Bitbucket Runner VM"
APP_TYPE="vm"
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="bitbucket-runner-vm"
THIN="discard=on,ssd=1,"
USE_CLOUD_INIT="no"

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
debian13) URL="https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64.qcow2" ;;
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

FILE="$CACHE_FILE"

msg_info "Creating a ${OS_LABEL} Bitbucket Runner VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID $FILE $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
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

cat <<'INSTRUCTIONS'

  ┌─────────────────────────────────────────────────────────────────────────┐
  │               BITBUCKET RUNNER - BASE VM READY                          │
  ├─────────────────────────────────────────────────────────────────────────┤
  │  This is a minimal base VM. The Bitbucket self-hosted runner is NOT     │
  │  pre-installed. After first boot, log in and install the runner:        │
  │                                                                         │
  │    1. Get your runner setup token from the Bitbucket repo settings.     │
  │    2. Inside the VM, download and configure the runner:                 │
  │         https://support.atlassian.com/bitbucket-cloud/docs/             │
  │         configure-a-self-hosted-runner/                                 │
  │                                                                         │
  │  NOTE: 8GB+ RAM is recommended for smooth runner performance.           │
  └─────────────────────────────────────────────────────────────────────────┘

INSTRUCTIONS

if [ "$USE_CLOUD_INIT" = "yes" ] && declare -f display_cloud_init_info >/dev/null 2>&1; then
  display_cloud_init_info "$VMID" "$HN"
fi
