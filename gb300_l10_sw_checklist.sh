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
#   0.4.2  2026-08-07  Fixed two false-negative checks found during first
#                       full run: (1) "IOMMU Enabled" checked for an x86-style
#                       dmesg log string ('IOMMU enabled') that Grace/ARM never
#                       emits - platform uses SMMU instead, enabled via ACPI
#                       IORT rather than a boot-time log line. Replaced with a
#                       populated-/sys/kernel/iommu_groups/ count check, which
#                       is architecture-agnostic and reflects actual translation
#                       state rather than a specific kernel log message.
#                       (2) "CUDA Version (driver)" used
#                       `nvidia-smi --query-gpu=cuda_version`, which errors
#                       ("Field \"cuda_version\" is not a valid field to query")
#                       on this driver/nvidia-smi build. Replaced with parsing
#                       the "CUDA Version: X.Y" string from plain `nvidia-smi`
#                       header output instead.
#   0.4.3  2026-08-10  "nvcc (CUDA toolkit)" still reported MISSING when the
#                       script itself was run as `sudo ./gb300_l10_sw_checklist.sh`
#                       (its own documented Usage), even after adding
#                       /usr/local/cuda/bin to PATH via /etc/profile.d and
#                       /etc/bash.bashrc. Root cause: `sudo script.sh` is a
#                       non-interactive invocation, which never sources those
#                       files regardless of shell config - and sudo's own
#                       secure_path resets PATH independently besides. Fixed
#                       by adding /usr/local/cuda/bin to PATH defensively
#                       inside the script itself rather than relying on the
#                       caller's environment.
#   0.4.4  2026-08-10  Two corrections against NVOnline 1160245's full raw
#                       JSON component list (GB300MaxQNVL_72x1 2.0.0-build25),
#                       not just the Table 2 excerpt used for CUDA/driver in
#                       v0.4.1: (1) EXPECTED_FM corrected "570" -> "580.173.04"
#                       to match the confirmed GFM entry. (2) EXPECTED_MOFED
#                       removed entirely - confirmed via the full component
#                       list (every versioned item in the milestone checked,
#                       not just OFED-related ones) that MOFED/OFED has no
#                       independent version entry in this release; it's
#                       absorbed into DOCA_Host (already correct). The MOFED
#                       check is now informational-only, no PASS/FAIL target,
#                       since holding it to a target that doesn't exist in the
#                       source of truth would just reintroduce a different
#                       false "CHECK"/stale-value problem.
#   0.4.5  2026-08-10  Added "CX8 Firmware Version" check (EXPECTED_CX8_FW =
#                       40.49.1118, per Host Software Components matrix /
#                       NVOnline 1160245 "CX8" entry) - previously only BF3
#                       firmware had a version check, with no ConnectX-8
#                       equivalent despite CX8 FW being tracked elsewhere in
#                       the build log. Queries mt4131_pciconf0 (card 1 of 4;
#                       same placeholder-path caveat as the existing BF3
#                       check applies - confirm via `mst status` and adjust,
#                       or extend to loop over all 4 cards if per-card
#                       drift matters).
#                       Deliberately NOT adding a "BF3 DPU OS version" check:
#                       this build uses the firmware-only BF3 bundle (not the
#                       OS+firmware bundle) because BF3 is configured in NIC
#                       mode, where the DPU's Arm cores don't run a
#                       customer-facing OS. There is no OS version to read on
#                       this design, so the row would always read MISSING
#                       with no fix available. Waived for now; revisit only
#                       if BF3 mode changes to embedded/DPU mode.
#   0.4.6  2026-08-10  "Fabric Manager Service"/"Fabric Manager Version"
#                       reclassified from MISSING to a new N/A status (added
#                       note_na() helper + blue [N/A] row, excluded from the
#                       MISSING tally). Root cause: on the GB300 NVL72
#                       rack-scale design, the NVLink switch trays are
#                       self-contained managed switches running their own
#                       NVOS - fabric management lives there, not on the
#                       compute tray host. This host will never run
#                       `nvidia-fabricmanager`/`nv-fabricmanager` regardless
#                       of bring-up stage, racked or not, so treating it as
#                       MISSING was a structural false-negative, not
#                       deferred work (same category as "NVSwitch Devices",
#                       left as-is for now since it's a single-row informal
#                       case rather than a second N/A conversion in this
#                       pass). Simply dropping the EXPECTED_FM comparison
#                       (the MOFED v0.4.4 pattern) was considered and
#                       rejected - MOFED was present with no target to check
#                       against, so it resolved to OK; Fabric Manager is
#                       structurally absent here, so it would still read
#                       MISSING regardless of any target comparison. Needed
#                       an actual new status, not just a dropped target.
#                       EXPECTED_FM retained (not removed like EXPECTED_MOFED)
#                       since GFM 580.173.04 is still a real, valid component
#                       version per the NVOnline source of truth - it's just
#                       verified on the NVSwitch/NVOS side of bring-up, not by
#                       this script. Value is now referenced in the N/A row's
#                       message as a pointer for whoever does that check.
# ------------------------------------------------------------------------

SCRIPT_VERSION="0.4.6"

set -uo pipefail

# Ensure the CUDA toolkit is discoverable even when this script is invoked
# non-interactively (e.g. `sudo ./gb300_l10_sw_checklist.sh`, per the Usage
# line above) or via cron/CI. Non-interactive shells don't source
# /etc/profile.d/, /etc/bash.bashrc, or ~/.bashrc, and sudo's own secure_path
# resets PATH regardless - so relying on the caller's shell environment for
# this is not reliable. Handled defensively here instead.
[[ -d /usr/local/cuda/bin ]] && PATH="/usr/local/cuda/bin:$PATH"

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
EXPECTED_FM="580.173.04"       # corrected from stale "570" - confirmed via NVOnline
                                # 1160245 source file (GFM: 580.173.04). Kept as a
                                # documentation reference only as of v0.4.6 - GFM lives
                                # on the NVSwitch tray's NVOS, not this compute host, so
                                # the checks below no longer compare against it.
# EXPECTED_MOFED removed - confirmed via NVOnline 1160245 (full component list
# checked) that MOFED/OFED is NOT independently versioned in this release; it
# is absorbed into DOCA_Host (3.4.1-010000, already correct above). The
# "MOFED Version" check below is now informational-only (no PASS/FAIL target).
EXPECTED_DOCA="3.4.1"          # per Host Software Components matrix (3.4.1-010000)
EXPECTED_DCGM="3.3"
EXPECTED_MFT="4.36.0"          # per Host Software Components matrix (4.36.0-147)
EXPECTED_BF3_FW="32.49.1118"   # per Host Software Components matrix
EXPECTED_CX8_FW="40.49.1118"   # per Host Software Components matrix (CX8 entry,
                                # NVOnline 1160245); confirmed via ibstat mlx5_5

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
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

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

note_na() {
  # note_na "Component" "reason" - for components that are structurally not
  # present on this host (e.g. owned by a different tray/OS), rather than
  # genuinely-pending bring-up work. Excluded from the MISSING count so it
  # doesn't read as a false-negative failure.
  local name="$1" reason="$2"
  ROWS+=("${name}|${reason}|N/A")
}

print_row() {
  local name="$1" val="$2" status="$3" color
  case "$status" in
    OK)      color="$GREEN" ;;
    MISSING) color="$RED" ;;
    N/A)     color="$BLUE" ;;
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
check "IOMMU Enabled"         "[ $(ls /sys/kernel/iommu_groups/ 2>/dev/null | wc -l) -gt 0 ] && echo yes"
check "Kernel Pkgs Held (meta)"    "apt-mark showhold | grep -m1 '^linux-nvidia-64k-hwe'"
check "Kernel Pkgs Held (image)"   "apt-mark showhold | grep -m1 '^linux-image-nvidia-64k-hwe'"
check "Kernel Pkgs Held (headers)" "apt-mark showhold | grep -m1 '^linux-headers-nvidia-64k-hwe'"
check "unattended-upgrades"   "systemctl is-active unattended-upgrades" "inactive"

# ----------------------------------------------------------------------------
# 3. Collect: NVIDIA Driver / CUDA / GPU
# ----------------------------------------------------------------------------
section "NVIDIA Driver / CUDA / GPU"
check "NVIDIA Driver Version" "nvidia-smi --query-gpu=driver_version --format=csv,noheader -i 0" "$EXPECTED_DRIVER"
check "CUDA Version (driver)" "nvidia-smi | grep -oP 'CUDA Version:\s*\K[0-9.]+' | head -n1" "$EXPECTED_CUDA"
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
# Fabric Manager: reclassified N/A as of v0.4.6, not a MISSING/failure. On the
# GB300 NVL72 rack-scale design, fabric management runs on the NVSwitch
# tray's own NVOS, not this compute host - `nvidia-fabricmanager`/
# `nv-fabricmanager` are not expected to exist here at any bring-up stage,
# racked or not. Verify GFM version (target: $EXPECTED_FM) on the
# NVSwitch/NVOS side of bring-up instead.
note_na "Fabric Manager Service" "runs on NVSwitch tray (NVOS), not this host"
note_na "Fabric Manager Version" "verify via NVOS, target $EXPECTED_FM"
check "NVLink Active Links"    "nvidia-smi nvlink -s -i 0 | grep -c 'Active'"
check "NVSwitch Devices"       "nvidia-smi -q | grep -m1 -i 'NVSwitch'"
check "GPU Topology (summary)" "nvidia-smi topo -m | head -1"

# ----------------------------------------------------------------------------
# 5. Collect: Networking (MOFED / RDMA / DOCA / BlueField)
# ----------------------------------------------------------------------------
section "Networking / MOFED / DOCA (BlueField)"
check "MOFED Version"          "ofed_info -s"
check "IB Devices"             "ibstat -l | tr '\n' ' '"
check "RDMA Link Status"       "rdma link show | head -1"
check "DOCA Version"           "doca_version 2>/dev/null || dpkg -l | grep -m1 doca-runtime" "$EXPECTED_DOCA"
check "BlueField DPU Detected" "lspci | grep -m1 -i 'BlueField'"
check "MFT Tools Version"      "mst version 2>/dev/null || flint -v 2>/dev/null | head -1" "$EXPECTED_MFT"
check "BF3 Firmware Version"   "flint -d /dev/mst/mt41692_pciconf0 q 2>/dev/null | grep -m1 'FW Version'" "$EXPECTED_BF3_FW"
check "CX8 Firmware Version"   "flint -d /dev/mst/mt4131_pciconf0 q 2>/dev/null | grep -m1 'FW Version'" "$EXPECTED_CX8_FW"
    # NOTE: /dev/mst/mt41692_pciconf0 and /dev/mst/mt4131_pciconf0 are placeholder
    # mst device paths - confirm actual device names via `mst status` once MFT
    # tools are installed and adjust. CX8 check above only covers card 1 of 4;
    # extend to loop over all cards if per-card firmware drift is a concern.
    #
    # NOTE: no "BF3 DPU OS version" check - waived deliberately, not an
    # oversight. This build uses the firmware-only BF3 bundle (NIC mode), so
    # the DPU Arm cores never run a customer-facing OS; there is no OS
    # version to read here. Revisit only if BF3 mode changes to embedded/DPU
    # mode with a full OS+firmware bundle.

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

pass=0; fail=0; check_n=0; na=0
for row in "${ROWS[@]}"; do
  IFS='|' read -r name val status <<< "$row"
  print_row "$name" "$val" "$status"
  case "$status" in
    OK) ((pass++)) ;;
    MISSING) ((fail++)) ;;
    N/A) ((na++)) ;;
    *) ((check_n++)) ;;
  esac
done

echo -e "${BOLD}------------------------------------------------------------------${NC}"
echo -e " Summary: ${GREEN}${pass} OK${NC} | ${YELLOW}${check_n} NEEDS REVIEW${NC} | ${RED}${fail} MISSING${NC} | ${BLUE}${na} N/A${NC}"
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
    echo "Summary: ${pass} OK | ${check_n} NEEDS REVIEW | ${fail} MISSING | ${na} N/A"
  } > "$LOGFILE"
  echo
  echo "Log written to: $LOGFILE"
fi

exit 0
