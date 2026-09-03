#!/bin/bash
#
# wipe_rack_fleet.sh
#
# Run directly on bcm11-headnode. Removes the device objects created by
# clone_from_inventory / clone_bmc_from_inventory for the current 8-rack
# fleet, so a different fleet (different MACs) can be cloned in cleanly.
#
# THIS IS DESTRUCTIVE - it removes BCM device objects entirely (not just
# powers nodes off, and not just a category reassignment). There is no
# built-in undo; re-populating these entries means re-running
# clone_from_inventory / clone_bmc_from_inventory against new inventory data.
#
# SCOPE: targets exactly the numbered fleet entries:
#   rackNNnodeXX        (host OS device objects)
#   bmc-rackNNnodeXX     (BMC device objects)
#   for rack NN = 01..08, node XX = 01..18 (144 + 144 = 288 devices)
#
# Deliberately EXCLUDED, never touched by this script:
#   bcm11-headnode, base-bmc, maxq106
#   (these don't follow the rackNN/bmc-rackNN numbering and look like
#   standing reference/template entries, not part of the swappable fleet -
#   confirm this assumption before relying on it for a real wipe)
#
# USAGE:
#   Dry run first (lists what would be removed, touches nothing):
#     ./wipe_rack_fleet.sh --dry-run
#
#   Real run:
#     ./wipe_rack_fleet.sh
#
#   Override rack/node range if the fleet size ever differs from 8 racks x
#   18 nodes (check `cmsh -c "device; list"` first if unsure):
#     ./wipe_rack_fleet.sh --racks 1-8 --nodes 1-18

set -uo pipefail

RACK_START=1
RACK_END=8
NODE_START=1
NODE_END=18

usage() {
  echo "Usage: $0 [--dry-run] [--racks <start>-<end>] [--nodes <start>-<end>]"
  echo "  e.g.: $0 --dry-run"
  echo "        $0"
  echo "        $0 --racks 1-8 --nodes 1-18"
  exit 1
}

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --racks)
      [[ -z "${2:-}" ]] && { echo "ERROR: --racks requires a value like 1-8."; usage; }
      RACK_START="${2%-*}"
      RACK_END="${2#*-}"
      shift 2
      ;;
    --nodes)
      [[ -z "${2:-}" ]] && { echo "ERROR: --nodes requires a value like 1-18."; usage; }
      NODE_START="${2%-*}"
      NODE_END="${2#*-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: unknown argument '$1'."
      usage
      ;;
  esac
done

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOGFILE="wipe_rack_fleet_${TIMESTAMP}.log"

# Build the full target device list
TARGET_DEVICES=()
for ((r=RACK_START; r<=RACK_END; r++)); do
  RACK_LABEL=$(printf "rack%02d" "$r")
  for ((n=NODE_START; n<=NODE_END; n++)); do
    NODE_PADDED=$(printf "%02d" "$n")
    TARGET_DEVICES+=("${RACK_LABEL}node${NODE_PADDED}")
    TARGET_DEVICES+=("bmc-${RACK_LABEL}node${NODE_PADDED}")
  done
done

TOTAL_TARGETS=${#TARGET_DEVICES[@]}

echo "Rack range   : $(printf 'rack%02d' "$RACK_START") - $(printf 'rack%02d' "$RACK_END")"
echo "Node range   : $NODE_START - $NODE_END"
echo "Total targets: $TOTAL_TARGETS device objects ($((TOTAL_TARGETS/2)) host + $((TOTAL_TARGETS/2)) BMC)"
echo "Excluded     : bcm11-headnode, base-bmc, maxq106 (never touched by this script)"
echo "Dry run      : $([[ $DRY_RUN -eq 1 ]] && echo yes || echo no)"
echo "Log file     : $LOGFILE"
echo

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[dry-run] Devices that would be removed:"
  printf '  %s\n' "${TARGET_DEVICES[@]}"
  echo
  echo "[dry-run] Nothing was sent to cmsh. Re-run without --dry-run to execute."
  exit 0
fi

# --- Pre-check: confirm which target devices actually exist, and whether
# any are currently UP (a device mid-install/mid-boot is not something you
# want to yank out from under itself) ---
echo "Checking current device status before removing anything..."
CURRENT_LIST=$(cmsh -c "device; list" 2>&1)

EXISTING_DEVICES=()
MISSING_DEVICES=()
UP_DEVICES=()

for dev in "${TARGET_DEVICES[@]}"; do
  LINE=$(echo "$CURRENT_LIST" | grep -E "^\S+\s+${dev}\s" || true)
  if [[ -z "$LINE" ]]; then
    MISSING_DEVICES+=("$dev")
    continue
  fi
  EXISTING_DEVICES+=("$dev")
  if echo "$LINE" | grep -qE '\[\s*UP\s*\]'; then
    UP_DEVICES+=("$dev")
  fi
done

echo "  Found in BCM   : ${#EXISTING_DEVICES[@]} / $TOTAL_TARGETS"
echo "  Not found      : ${#MISSING_DEVICES[@]} (already absent - fine, will be skipped)"
echo "  Currently UP   : ${#UP_DEVICES[@]}"
echo

if [[ ${#UP_DEVICES[@]} -gt 0 ]]; then
  echo "!!! WARNING: the following target devices currently show UP - likely mid-boot"
  echo "!!! or mid-install. Removing their device object while they're active is"
  echo "!!! not recommended. Review before proceeding:"
  printf '    %s\n' "${UP_DEVICES[@]}"
  echo
  read -rp "Type 'PROCEED ANYWAY' to continue despite the above, or anything else to abort: " UP_CONFIRM
  if [[ "$UP_CONFIRM" != "PROCEED ANYWAY" ]]; then
    echo "Aborting. Nothing was removed."
    exit 1
  fi
fi

if [[ ${#EXISTING_DEVICES[@]} -eq 0 ]]; then
  echo "No target devices found in BCM - nothing to remove. Exiting."
  exit 0
fi

# --- Confirmation ---
echo "!!! This will PERMANENTLY REMOVE ${#EXISTING_DEVICES[@]} device object(s) from BCM. !!!"
echo "!!! This cannot be undone - re-populating requires re-running               !!!"
echo "!!! clone_from_inventory / clone_bmc_from_inventory against new data.        !!!"
echo
CONFIRM_PHRASE="WIPE ${#EXISTING_DEVICES[@]} DEVICES"
read -rp "Type '$CONFIRM_PHRASE' exactly to confirm and proceed: " CONFIRM
if [[ "$CONFIRM" != "$CONFIRM_PHRASE" ]]; then
  echo "Confirmation did not match. Aborting, nothing was removed."
  exit 1
fi

# --- Execute: one cmsh session, one remove per existing device, one commit ---
echo "Removing ${#EXISTING_DEVICES[@]} device(s)..." | tee -a "$LOGFILE"

CMSH_SCRIPT="device"
for dev in "${EXISTING_DEVICES[@]}"; do
  CMSH_SCRIPT+=$'\n'"remove $dev"
done
CMSH_SCRIPT+=$'\n'"commit"

echo "$CMSH_SCRIPT" | cmsh 2>&1 | tee -a "$LOGFILE"

echo
echo "Removal command sent. Verifying..." | tee -a "$LOGFILE"

# --- Post-check: confirm the targeted devices are actually gone ---
POST_LIST=$(cmsh -c "device; list" 2>&1)
STILL_PRESENT=()
for dev in "${EXISTING_DEVICES[@]}"; do
  if echo "$POST_LIST" | grep -qE "^\S+\s+${dev}\s"; then
    STILL_PRESENT+=("$dev")
  fi
done

echo "====================================================================" | tee -a "$LOGFILE"
echo "Summary" | tee -a "$LOGFILE"
echo "====================================================================" | tee -a "$LOGFILE"
echo "Targeted for removal : ${#EXISTING_DEVICES[@]}" | tee -a "$LOGFILE"
echo "Confirmed removed    : $((${#EXISTING_DEVICES[@]} - ${#STILL_PRESENT[@]}))" | tee -a "$LOGFILE"
echo "Still present (FAIL) : ${#STILL_PRESENT[@]}" | tee -a "$LOGFILE"
if [[ ${#STILL_PRESENT[@]} -gt 0 ]]; then
  echo "  The following were NOT removed - investigate before re-cloning:" | tee -a "$LOGFILE"
  printf '    %s\n' "${STILL_PRESENT[@]}" | tee -a "$LOGFILE"
fi
echo
echo "Full log: $LOGFILE"

if [[ ${#STILL_PRESENT[@]} -gt 0 ]]; then
  exit 1
fi
