#!/bin/bash
#
# pxe_rack_provision.sh
#
# Run directly on bcm11-headnode. Controls power and/or PXE boot flag for
# one rack OR a range of racks via IPMI, for staged BCM PXE provisioning
# (start with 1-2 racks for an exercise before running the full 8).
#
# BMC IPs are generated from BCM's own internalnet numbering, confirmed
# against the full `cmsh -c "device; list"` output across all 8 racks:
#   bmc-rack01node01 -> 10.141.1.101   ...   bmc-rack01node18 -> 10.141.1.118
#   bmc-rack02node01 -> 10.141.2.101   ...   bmc-rack02node18 -> 10.141.2.118
#   ... same pattern through rack08 ...
# i.e. 10.141.<rack>.<100 + node_number>, 18 nodes per rack, confirmed
# consistent for all 8 racks currently in BCM's device list.
#
# MODES (mutually exclusive - pick at most one of -power / -pxe):
#   Default (neither flag): full PXE provisioning workflow - sets
#   bootdev pxe (EFI) THEN power cycles each node. Original behavior,
#   unchanged for backward compatibility.
#
#   -power on|off|cycle: does ONLY that single IPMI power action per node,
#   does NOT touch the boot device flag at all. Use for plain power
#   control (e.g. powering a freshly-racked rack on for the first time,
#   or powering a rack down) separate from PXE provisioning.
#
#   -pxe: does ONLY the bootdev pxe (EFI) call per node, does NOT power
#   cycle. Use when a node is already going to reboot on its own (or
#   you'll trigger the reboot separately) and you just need the next-boot
#   flag set first.
#
# USAGE:
#   Single rack, full PXE workflow (bootdev pxe + power cycle):
#     ./pxe_rack_provision.sh --rack 1
#     ./pxe_rack_provision.sh --dry-run --rack 1
#
#   Range of racks (like wipe_rack_fleet.sh's --racks style), same flag:
#     ./pxe_rack_provision.sh --rack 1-8
#     ./pxe_rack_provision.sh --dry-run --rack 1-8
#
#   Plain power control only, no bootdev change, single rack or range:
#     ./pxe_rack_provision.sh -power on --rack 1
#     ./pxe_rack_provision.sh -power off --rack 1-8
#     ./pxe_rack_provision.sh -power cycle --rack 3-5
#
#   Bootdev flag only, no power action:
#     ./pxe_rack_provision.sh -pxe --rack 1
#     ./pxe_rack_provision.sh -pxe --rack 1-8
#
#   Override node count only if a rack genuinely has a different number of
#   nodes than the confirmed default of 18 (check `cmsh -c "device; list" |
#   grep bmc-rackNN` first if unsure) - applies to every rack in range:
#     ./pxe_rack_provision.sh --rack 1 --nodes 12
#
#   Delay between nodes defaults to 0 (no delay). Override with --delay if
#   you want to stagger a large default-workflow run so a whole rack/range
#   doesn't hit the head node's PXE/image-sync at the same instant:
#     ./pxe_rack_provision.sh --rack 1-8 --delay 5
#
#   Override BMC credentials (defaults below are the known/open account):
#     ./pxe_rack_provision.sh -U root -P 'SomeOtherPass' --rack 1
#
#   Flags can appear in any order. For a single rack you'll be asked to
#   type "rack01" (etc.) to confirm; for a range you'll be asked to type
#   "rack01-rack08" (etc.) - the full range, not just one rack's label -
#   before anything is sent.

set -uo pipefail

BMC_USER="root"
BMC_PASS="0penBmc"

DEFAULT_DELAY_SECONDS=0   # gap between nodes. Set to 0 by default. Override
                          # with --delay <seconds> if you want to stagger a
                          # large default-workflow run (bootdev pxe + power
                          # cycle) so a whole rack/range doesn't hit the head
                          # node's PXE/image-sync at the same instant.
IP_OFFSET=100             # bmc-rackNNnodeXX -> 10.141.N.(100+XX)
DEFAULT_NODE_COUNT=18     # confirmed via full device list: every rack
                          # (01-08) currently has exactly 18 nodes

usage() {
  echo "Usage: $0 [--dry-run] [-power on|off|cycle | -pxe] [-U <bmc_user>] [-P <bmc_pass>] [--delay <seconds>] --rack <N|N-M> [--nodes <node_count>]"
  echo "  Default (neither -power nor -pxe): full PXE workflow - bootdev pxe THEN power cycle."
  echo "  -power on|off|cycle: ONLY that power action, no bootdev change."
  echo "  -pxe: ONLY the bootdev pxe (EFI) call, no power action."
  echo "  -power and -pxe are mutually exclusive."
  echo "  --rack accepts a single number (1) or a range (1-8)."
  echo "  --delay: seconds between nodes, default $DEFAULT_DELAY_SECONDS (no delay). Set >0 to stagger a large run."
  echo
  echo "  e.g.: $0 --rack 1                       (rack01 only, PXE workflow, real run)"
  echo "        $0 --dry-run --rack 1-8           (all 8 racks, PXE workflow, dry run)"
  echo "        $0 --rack 1-8 --delay 5           (all 8 racks, PXE workflow, stagger 5s between nodes)"
  echo "        $0 -power off --rack 1            (rack01 only, power off only)"
  echo "        $0 -pxe --rack 1                  (rack01 only, bootdev pxe flag only, no power action)"
  echo "        $0 --rack 1 --nodes 12            (rack01, override to 12 nodes)"
  echo "        $0 -U root -P 'Pass123' --rack 1  (rack01, override BMC credentials)"
  exit 1
}

DRY_RUN=0
POWER_ACTION=""   # "" = unset; else on|off|cycle
PXE_ONLY=0
RACK_ARG=""
NODE_COUNT=""
DELAY_SECONDS="$DEFAULT_DELAY_SECONDS"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -power)
      [[ -z "${2:-}" ]] && { echo "ERROR: -power requires a value (on|off|cycle)."; usage; }
      case "$2" in
        on|off|cycle) POWER_ACTION="$2" ;;
        *) echo "ERROR: -power must be on, off, or cycle (got '$2')."; usage ;;
      esac
      shift 2
      ;;
    -pxe)
      PXE_ONLY=1
      shift
      ;;
    --rack)
      [[ -z "${2:-}" ]] && { echo "ERROR: --rack requires a value (e.g. --rack 1 or --rack 1-8)."; usage; }
      RACK_ARG="$2"
      shift 2
      ;;
    --nodes)
      [[ -z "${2:-}" ]] && { echo "ERROR: --nodes requires a value (e.g. --nodes 18)."; usage; }
      NODE_COUNT="$2"
      shift 2
      ;;
    --delay)
      [[ -z "${2:-}" ]] && { echo "ERROR: --delay requires a value in seconds (e.g. --delay 2)."; usage; }
      [[ ! "$2" =~ ^[0-9]+$ ]] && { echo "ERROR: --delay must be a non-negative integer (got '$2')."; usage; }
      DELAY_SECONDS="$2"
      shift 2
      ;;
    -U)
      [[ -z "${2:-}" ]] && { echo "ERROR: -U requires a value."; usage; }
      BMC_USER="$2"
      shift 2
      ;;
    -P)
      [[ -z "${2:-}" ]] && { echo "ERROR: -P requires a value."; usage; }
      BMC_PASS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: unknown or unexpected argument '$1'."
      usage
      ;;
  esac
done

[[ -z "$RACK_ARG" ]] && { echo "ERROR: --rack is required."; usage; }
if [[ -n "$POWER_ACTION" && "$PXE_ONLY" -eq 1 ]]; then
  echo "ERROR: -power and -pxe are mutually exclusive - pick at most one, or use neither for the default combined workflow."
  usage
fi
NODE_COUNT="${NODE_COUNT:-$DEFAULT_NODE_COUNT}"

if [[ "$RACK_ARG" == *-* ]]; then
  RACK_START="${RACK_ARG%-*}"
  RACK_END="${RACK_ARG#*-}"
else
  RACK_START="$RACK_ARG"
  RACK_END="$RACK_ARG"
fi

if ! [[ "$RACK_START" =~ ^[0-9]+$ && "$RACK_END" =~ ^[0-9]+$ ]] || [[ "$RACK_START" -gt "$RACK_END" ]]; then
  echo "ERROR: invalid --rack value '$RACK_ARG'. Use a number (1) or a range (1-8) with start <= end."
  usage
fi

RACK_LABEL_START=$(printf "rack%02d" "$RACK_START")
RACK_LABEL_END=$(printf "rack%02d" "$RACK_END")
if [[ "$RACK_START" -eq "$RACK_END" ]]; then
  RANGE_LABEL="$RACK_LABEL_START"
else
  RANGE_LABEL="${RACK_LABEL_START}-${RACK_LABEL_END}"
fi
NUM_RACKS=$((RACK_END - RACK_START + 1))

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOGFILE="pxe_${RANGE_LABEL}_${TIMESTAMP}.log"

if [[ -n "$POWER_ACTION" ]]; then
  MODE_LABEL="Power ${POWER_ACTION} only (no bootdev change)"
  ACTION_VERB="POWER ${POWER_ACTION^^}"
elif [[ "$PXE_ONLY" -eq 1 ]]; then
  MODE_LABEL="Bootdev pxe only (no power action)"
  ACTION_VERB="SET BOOTDEV PXE ON"
else
  MODE_LABEL="Full PXE workflow (bootdev pxe + power cycle)"
  ACTION_VERB="PXE-boot-flag and POWER CYCLE"
fi

echo "Rack(s)     : $RANGE_LABEL ($NUM_RACKS rack$([[ $NUM_RACKS -gt 1 ]] && echo s))"
echo "Mode        : $MODE_LABEL"
echo "Node count  : $NODE_COUNT per rack$([[ "$NODE_COUNT" != "$DEFAULT_NODE_COUNT" ]] && echo " (overridden from default $DEFAULT_NODE_COUNT)")"
echo "Total nodes : $((NODE_COUNT * NUM_RACKS))"
echo "BMC user    : $BMC_USER"
echo "Delay/node  : ${DELAY_SECONDS}s$([[ "$DELAY_SECONDS" != "$DEFAULT_DELAY_SECONDS" ]] && echo " (overridden from default ${DEFAULT_DELAY_SECONDS}s)")"
echo "Dry run     : $([[ $DRY_RUN -eq 1 ]] && echo yes || echo no)"
echo "Log file    : $LOGFILE"
echo

if [[ $DRY_RUN -eq 0 ]]; then
  echo "!!! This will $ACTION_VERB $((NODE_COUNT * NUM_RACKS)) node(s) across $RANGE_LABEL. !!!"
  read -rp "Type '$RANGE_LABEL' exactly to confirm and proceed: " CONFIRM
  if [[ "$CONFIRM" != "$RANGE_LABEL" ]]; then
    echo "Confirmation did not match. Aborting, nothing was sent."
    exit 1
  fi
fi

declare -a FAILED_NODES=()
declare -a OK_NODES=()

for ((r=RACK_START; r<=RACK_END; r++)); do
  RACK_LABEL=$(printf "rack%02d" "$r")
  echo "-------------------------------------------------------------------" | tee -a "$LOGFILE"
  echo "Rack: $RACK_LABEL" | tee -a "$LOGFILE"
  echo "-------------------------------------------------------------------" | tee -a "$LOGFILE"

  for ((i=1; i<=NODE_COUNT; i++)); do
    NODE_PADDED=$(printf "%02d" "$i")
    HOSTNAME="bmc-${RACK_LABEL}node${NODE_PADDED}"
    BMC_IP="10.141.${r}.$((IP_OFFSET + i))"

    echo "=== $HOSTNAME ($BMC_IP) ===" | tee -a "$LOGFILE"

    if [[ -n "$POWER_ACTION" ]]; then
      # --- Plain power control mode: single IPMI call, no bootdev change ---
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [dry-run] would run: ipmitool -I lanplus -H $BMC_IP -U $BMC_USER -P *** -C 17 chassis power $POWER_ACTION" | tee -a "$LOGFILE"
        continue
      fi

      if ipmitool -I lanplus -H "$BMC_IP" -U "$BMC_USER" -P "$BMC_PASS" -C 17 \
          chassis power "$POWER_ACTION" >>"$LOGFILE" 2>&1; then
        echo "  power $POWER_ACTION: OK" | tee -a "$LOGFILE"
        OK_NODES+=("$HOSTNAME ($BMC_IP)")
      else
        echo "  power $POWER_ACTION: FAILED" | tee -a "$LOGFILE"
        FAILED_NODES+=("$HOSTNAME ($BMC_IP) - power $POWER_ACTION failed")
      fi

      echo | tee -a "$LOGFILE"
      sleep "$DELAY_SECONDS"
      continue
    fi

    if [[ "$PXE_ONLY" -eq 1 ]]; then
      # --- PXE-flag-only mode: single IPMI call, no power action ---
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [dry-run] would run: ipmitool -I lanplus -H $BMC_IP -U $BMC_USER -P *** -C 17 chassis bootdev pxe options=efiboot" | tee -a "$LOGFILE"
        continue
      fi

      if ipmitool -I lanplus -H "$BMC_IP" -U "$BMC_USER" -P "$BMC_PASS" -C 17 \
          chassis bootdev pxe options=efiboot >>"$LOGFILE" 2>&1; then
        echo "  bootdev pxe: OK" | tee -a "$LOGFILE"
        OK_NODES+=("$HOSTNAME ($BMC_IP)")
      else
        echo "  bootdev pxe: FAILED" | tee -a "$LOGFILE"
        FAILED_NODES+=("$HOSTNAME ($BMC_IP) - bootdev failed")
      fi

      echo | tee -a "$LOGFILE"
      sleep "$DELAY_SECONDS"
      continue
    fi

    # --- Default mode: full PXE workflow (bootdev pxe THEN power cycle) ---
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  [dry-run] would run: ipmitool -I lanplus -H $BMC_IP -U $BMC_USER -P *** -C 17 chassis bootdev pxe options=efiboot" | tee -a "$LOGFILE"
      echo "  [dry-run] would run: ipmitool -I lanplus -H $BMC_IP -U $BMC_USER -P *** -C 17 chassis power cycle" | tee -a "$LOGFILE"
      continue
    fi

    if ipmitool -I lanplus -H "$BMC_IP" -U "$BMC_USER" -P "$BMC_PASS" -C 17 \
        chassis bootdev pxe options=efiboot >>"$LOGFILE" 2>&1; then
      echo "  bootdev pxe: OK" | tee -a "$LOGFILE"
    else
      echo "  bootdev pxe: FAILED" | tee -a "$LOGFILE"
      FAILED_NODES+=("$HOSTNAME ($BMC_IP) - bootdev failed")
      continue
    fi

    if ipmitool -I lanplus -H "$BMC_IP" -U "$BMC_USER" -P "$BMC_PASS" -C 17 \
        chassis power cycle >>"$LOGFILE" 2>&1; then
      echo "  power cycle: OK" | tee -a "$LOGFILE"
      OK_NODES+=("$HOSTNAME ($BMC_IP)")
    else
      echo "  power cycle: FAILED" | tee -a "$LOGFILE"
      FAILED_NODES+=("$HOSTNAME ($BMC_IP) - power cycle failed")
    fi

    echo | tee -a "$LOGFILE"
    sleep "$DELAY_SECONDS"
  done
done

echo "===================================================================="
echo "Summary: $RANGE_LABEL ($MODE_LABEL)"
echo "===================================================================="
echo "Succeeded (${#OK_NODES[@]}):"
for n in "${OK_NODES[@]:-}"; do [[ -n "$n" ]] && echo "  - $n"; done
echo
echo "Failed (${#FAILED_NODES[@]}):"
for n in "${FAILED_NODES[@]:-}"; do [[ -n "$n" ]] && echo "  - $n"; done
echo
echo "Full log: $LOGFILE"

if [[ ${#FAILED_NODES[@]} -gt 0 ]]; then
  exit 1
fi
