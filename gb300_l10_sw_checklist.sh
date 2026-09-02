#!/usr/bin/env bash
#
# gb300_l10_sw_checklist.sh
#
# Purpose : Display an L10 system-software checklist (component + installed
#           version) for a GB300 NVL reference layout bring-up, aligned to
#           the NVIDIA 2.0 release stack.
#
# Usage   : sudo ./gb300_l10_sw_checklist.sh [-o /path/to/logfile]
#
# Notes   : - Run as root (or with sudo) for full BIOS/BMC/PCIe visibility.
#           - Missing components are reported as [ MISSING ] rather than
#             causing the script to fail, so you can run this at any stage
#             of the bring-up process.
#           - Fill in EXPECTED_* variables below to match your NVIDIA 2.0
#             release note / compatibility matrix and get PASS/FAIL diffing.
#
# ------------------------------------------------------------------------
# Changelog
#   0.1.0  2026-08-05  Initial version. OS/kernel, driver/CUDA/GPU,
#                       NVLink/NVSwitch/FM, MOFED/DOCA, DCGM/container
#                       runtime sections. Bring-up still in progress -
#                       expect MISSING rows until later install stages.
#   0.2.0  2026-08-05  EXPECTED_KERNEL updated to match the Grace 64k-page
#                       HWE kernel (linux-nvidia-64k-hwe-24.04) instead of
#                       stock generic kernel. Added explicit PAGE_SIZE=65536
#                       check, since 64k pages are a hard requirement on
#                       Grace and worth catching automatically.
#   0.3.0  2026-08-05  Added "Kernel Package Held" and "unattended-upgrades"
#                       checks to catch apt-mark hold status and confirm
#                       automatic updates are disabled during bring-up.
#   0.3.1  2026-08-05  Split kernel-hold check into 3 rows (meta/image/
#                       headers) to match holding all three packages, not
#                       just the meta-package, since apt can otherwise
#                       still drift the underlying image/headers.
#   0.4.0  2026-08-05  EXPECTED_DRIVER, EXPECTED_DOCA updated to match the
#                       confirmed Host Software Components version matrix
#                       (driver 580.173.02, DOCA_Host 3.4.1-010000). Added
#                       MFT Tools and BF3 firmware version checks + expected
#                       values (4.36.0-147 / 32.49.1118). BF3 firmware check
#                       uses a placeholder mst device path - confirm actual
#                       path via `mst status` once MFT tools are installed.
#   0.4.1  2026-08-07  EXPECTED_CUDA corrected 12.8 -> 13.0 (matches Toolkit
#                       13.0.2). Previous value was an unverified assumption;
#                       confirmed via NVOnline 1160245 Table 2, which pairs
#                       CUDA Toolkit 13.0.2 with Datacenter Driver 580.173.02
#                       - an exact match to the already-installed/confirmed
#                       driver, giving high confidence in the pairing.
# ------------------------------------------------------------------------

SCRIPT_VERSION="0.4.1"

set -uo pipefail

# ----------------------------------------------------------------------------
# 0. Config: expected versions (edit to match your NVIDIA 2.0 release matrix)
# ----------------------------------------------------------------------------
EXPECTED_OS="24.04"
EXPECTED_KERNEL="nvidia-64k"   # Grace requires the 64k-page HWE kernel flavor;
                                # substring match only (exact build # will drift
                                # with HWE point updates, e.g. 6.17.0-1029)
EXPECTED_DRIVER="580.173.02"   # per Host Software Components matrix
                                # (NVIDIA-kernel-module-source-580.173.02)
EXPECTED_CUDA="13.0"          # corrected from stale 12.8 - confirmed via NVOnline 1160245
                                # Table 2, paired with Datacenter Driver 580.173.02 (exact
                                # match to installed driver) -> CUDA Toolkit 13.0.2
EXPECTED_FM="570"
EXPECTED_MOFED="24.10"
EXPECTED_DOCA="3.4.1"          # per Host Software Components matrix (3.4.1-010000)
EXPECTED_DCGM="3.3"
EXPECTED_MFT="4.36.0"          # per Host Software Components matrix (4.36.0-147)
EXPECTED_BF3_FW="32.49.1118"   # per Host Software Components matrix

LOGFILE=""
while getopts "o:v" opt; do
  case "$opt" in
    o) LOGFILE="$OPTARG" ;;
    v) echo "gb300_l10_sw_checklist.sh version $SCRIPT_VERSION"; exit 0 ;;
    *) echo "Usage: $0 [-o logfile] [-v]"; exit 1 ;;
  esac
done

# ----------------------------------------------------------------------------
# 1. Helpers
# ----------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

declare -a ROWS=()   # accumulates rows for final summary table

check() {
  # check "Component" "command" "expected_substr(optional)"
  local name="$1" cmd="$2" expected="${3:-}"
  local out status

  out=$(eval "$cmd" 2>/dev/null | head -n1 | tr -d '\r')
  if [[ -z "$out" ]]; then
    status="MISSING"
    out="-"
  elif [[ -n "$expected" && "$out" != *"$expected"* ]]; then
    status="CHECK"
  else
    status="OK"
  fi
  ROWS+=("${name}|${out}|${status}")
}

print_row() {
  local name="$1" val="$2" status="$3" color
  case "$status" in
    OK)      color="$GREEN" ;;
    MISSING) color="$RED" ;;
    *)       color="$YELLOW" ;;
  esac
  printf " %-32s : %-38s [${color}%s${NC}]\n" "$name" "$val" "$status"
}

section() {
  echo
  echo -e "${BOLD}== $1 ==${NC}"
}

# ----------------------------------------------------------------------------
# 2. Collect: OS / Kernel / Platform
# ----------------------------------------------------------------------------
section "OS / Kernel / Platform"
check "Ubuntu Release"        "lsb_release -rs" "$EXPECTED_OS"
check "Kernel Version"        "uname -r" "$EXPECTED_KERNEL"
check "Kernel Page Size"      "getconf PAGE_SIZE" "65536"
check "Architecture"          "uname -m"
check "BMC/BIOS (dmidecode)"  "dmidecode -s bios-version"
check "System Product Name"   "dmidecode -s system-product-name"
check "IOMMU Enabled"         "dmesg | grep -m1 -i 'IOMMU enabled'"
check "Kernel Pkgs Held (meta)"    "apt-mark showhold | grep -m1 '^linux-nvidia-64k-hwe'"
check "Kernel Pkgs Held (image)"   "apt-mark showhold | grep -m1 '^linux-image-nvidia-64k-hwe'"
check "Kernel Pkgs Held (headers)" "apt-mark showhold | grep -m1 '^linux-headers-nvidia-64k-hwe'"
check "unattended-upgrades"   "systemctl is-active unattended-upgrades" "inactive"

# ----------------------------------------------------------------------------
# 3. Collect: NVIDIA Driver / CUDA / GPU
# ----------------------------------------------------------------------------
section "NVIDIA Driver / CUDA / GPU"
check "NVIDIA Driver Version" "nvidia-smi --query-gpu=driver_version --format=csv,noheader -i 0" "$EXPECTED_DRIVER"
check "CUDA Version (driver)" "nvidia-smi --query-gpu=cuda_version --format=csv,noheader -i 0" "$EXPECTED_CUDA"
check "nvcc (CUDA toolkit)"   "nvcc --version | grep release"
check "GPU Count"             "nvidia-smi --query-gpu=count --format=csv,noheader -i 0"
check "GPU Name"              "nvidia-smi --query-gpu=name --format=csv,noheader -i 0"
check "VBIOS Version"         "nvidia-smi --query-gpu=vbios_version --format=csv,noheader -i 0"
check "Persistence Mode"      "nvidia-smi --query-gpu=persistence_mode --format=csv,noheader -i 0"
check "GPU Kernel Module"     "modinfo nvidia | grep -m1 ^version"

# ----------------------------------------------------------------------------
# 4. Collect: NVLink / NVSwitch / Fabric Manager
# ----------------------------------------------------------------------------
section "NVLink / NVSwitch / Fabric Manager"
check "Fabric Manager Service" "systemctl is-active nvidia-fabricmanager"
check "Fabric Manager Version" "nv-fabricmanager --version" "$EXPECTED_FM"
check "NVLink Active Links"    "nvidia-smi nvlink -s -i 0 | grep -c 'Active'"
check "NVSwitch Devices"       "nvidia-smi -q | grep -m1 -i 'NVSwitch'"
check "GPU Topology (summary)" "nvidia-smi topo -m | head -1"

# ----------------------------------------------------------------------------
# 5. Collect: Networking (MOFED / RDMA / DOCA / BlueField)
# ----------------------------------------------------------------------------
section "Networking / MOFED / DOCA (BlueField)"
check "MOFED Version"          "ofed_info -s" "$EXPECTED_MOFED"
check "IB Devices"             "ibstat -l | tr '\n' ' '"
check "RDMA Link Status"       "rdma link show | head -1"
check "DOCA Version"           "doca_version 2>/dev/null || dpkg -l | grep -m1 doca-runtime" "$EXPECTED_DOCA"
check "BlueField DPU Detected" "lspci | grep -m1 -i 'BlueField'"
check "MFT Tools Version"      "mst version 2>/dev/null || flint -v 2>/dev/null | head -1" "$EXPECTED_MFT"
check "BF3 Firmware Version"   "flint -d /dev/mst/mt41692_pciconf0 q 2>/dev/null | grep -m1 'FW Version'" "$EXPECTED_BF3_FW"
    # NOTE: /dev/mst/mt41692_pciconf0 is a placeholder mst device path - confirm
    # actual device name via `mst status` once MFT tools are installed and adjust.

# ----------------------------------------------------------------------------
# 6. Collect: DCGM / Container Runtime / Orchestration
# ----------------------------------------------------------------------------
section "DCGM / Container Runtime"
check "DCGM Version"           "dcgmi --version" "$EXPECTED_DCGM"
check "DCGM Service"           "systemctl is-active nvidia-dcgm"
check "Docker Version"         "docker --version"
check "containerd Version"     "containerd --version"
check "nvidia-container-toolkit" "nvidia-ctk --version"
check "Default Runtime = nvidia" "docker info 2>/dev/null | grep -m1 'Default Runtime'"

# ----------------------------------------------------------------------------
# 7. Print summary table
# ----------------------------------------------------------------------------
echo
echo -e "${BOLD}==================================================================${NC}"
echo -e "${BOLD} GB300 NVL L10 SYSTEM SOFTWARE CHECKLIST  v${SCRIPT_VERSION}  ($(date '+%Y-%m-%d %H:%M:%S'))${NC}"
echo -e "${BOLD}==================================================================${NC}"

pass=0; fail=0; check_n=0
for row in "${ROWS[@]}"; do
  IFS='|' read -r name val status <<< "$row"
  print_row "$name" "$val" "$status"
  case "$status" in
    OK) ((pass++)) ;;
    MISSING) ((fail++)) ;;
    *) ((check_n++)) ;;
  esac
done

echo -e "${BOLD}------------------------------------------------------------------${NC}"
echo -e " Summary: ${GREEN}${pass} OK${NC} | ${YELLOW}${check_n} NEEDS REVIEW${NC} | ${RED}${fail} MISSING${NC}"
echo -e "${BOLD}==================================================================${NC}"

# ----------------------------------------------------------------------------
# 8. Optional: write to logfile (plain text, no color codes)
# ----------------------------------------------------------------------------
if [[ -n "$LOGFILE" ]]; then
  {
    echo "GB300 NVL L10 System Software Checklist - v${SCRIPT_VERSION} - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "===================================================================="
    for row in "${ROWS[@]}"; do
      IFS='|' read -r name val status <<< "$row"
      printf " %-32s : %-38s [%s]\n" "$name" "$val" "$status"
    done
    echo "--------------------------------------------------------------------"
    echo "Summary: ${pass} OK | ${check_n} NEEDS REVIEW | ${fail} MISSING"
  } > "$LOGFILE"
  echo
  echo "Log written to: $LOGFILE"
fi

exit 0
