#!/bin/bash
#
# pxe_rack_provision.sh
#
# VERSION: 1.2.0
#
# CHANGELOG:
#   1.0.0 (original) - single/range rack targeting, -power/-pxe/default modes,
#     --node <N> single-node targeting, --dry-run, --delay staggering.
#   1.1.0 - --node now accepts a range (N-M), e.g. --node 2-18, for bringing
#     up the rest of a rack after a canary/first node was handled separately.
#     Backward compatible with a single --node <N>.
#   1.2.0 - added --pxe-method ipmitool|redfish (default: ipmitool, unchanged
#     behavior). redfish PATCHes Boot.BootSourceOverrideEnabled=Once /
#     BootSourceOverrideTarget=Pxe instead of using ipmitool's own boot-flags
#     mechanism - this is the method actually validated by hand to correctly
#     target a specific NIC (1G port) on multi-NIC nodes, see header note
#     below. Added REDFISH_SYSTEM_ID (confirmed "System_0" on this hardware
#     only, NOT a universal default - re-verify per platform). Added
#     validation rejecting --pxe-method redfish combined with -power-only
#     mode (no PXE flag is set in that mode, so it would be a silent no-op).
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
#   Single node only, within a single rack (not valid with a rack range) -
#   use for a pilot/test run on one node before committing a whole rack:
#     ./pxe_rack_provision.sh --rack 1 --node 18
#     ./pxe_rack_provision.sh -pxe --rack 1 --node 18
#     ./pxe_rack_provision.sh -power cycle --rack 1 --node 18
#
#   Node RANGE within a single rack (not valid with a rack range) - use to
#   pick up the rest of a rack after a canary/first node was already
#   handled separately (e.g. node01 done manually, bring up node02-18):
#     ./pxe_rack_provision.sh --rack 8 --node 2-18
#     ./pxe_rack_provision.sh --rack 8 --node 2-18 --delay 5
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

#   PXE METHOD (default: ipmitool):
#   Two different mechanisms exist for setting the next-boot PXE flag, and
#   they are NOT guaranteed equivalent on all hardware:
#     ipmitool (default) - "chassis bootdev pxe options=efiboot" via IPMI's
#     own boot-flags mechanism. Simple, works, but does not let you target
#     a SPECIFIC NIC when a node has more than one PXE-capable interface
#     (e.g. a 1G onboard port AND a BlueField DPU port) - it resolves to
#     whichever PXE entry the firmware's own BootOrder ranks first.
#
#     redfish - PATCHes Boot.BootSourceOverrideEnabled=Once /
#     BootSourceOverrideTarget=Pxe via the Redfish API instead. This is the
#     mechanism actually validated by hand (2026-09-16/17, rack08node01,
#     see gb300_l10 session log SS9q-9r) to correctly land on the 1G NIC
#     on this hardware, confirmed via DHCP log cross-check. Same one-shot
#     ("Once", not "Continuous") semantics - never made persistent.
#     Requires the target's Redfish ComputerSystem resource ID, which is
#     NOT universally "System_0" - confirmed "System_0" on this specific
#     BMC/hardware (NVIDIA "CARLO_NEXT-T1") via a live
#     GET /redfish/v1/Systems enumeration, not assumed. If you point this
#     at different hardware, re-verify that resource ID first - see
#     REDFISH_SYSTEM_ID below, and don't assume "System_0" carries over.
#
#   ./pxe_rack_provision.sh --pxe-method redfish --rack 8 --node 2-18
#   ./pxe_rack_provision.sh -pxe --pxe-method redfish --rack 8 --node 1
#
set -uo pipefail

SCRIPT_VERSION="1.2.0"

BMC_USER="root"
BMC_PASS="0penBmc"
REDFISH_SYSTEM_ID="System_0"   # confirmed on this specific BMC/hardware model
                                 # (NVIDIA CARLO_NEXT-T1) via a live Redfish
                                 # /redfish/v1/Systems enumeration - NOT a
                                 # universal default. Re-verify with:
                                 #   curl -k -u $BMC_USER:$BMC_PASS \
                                 #     https://<bmc-ip>/redfish/v1/Systems
                                 # before trusting this on different hardware.

DEFAULT_DELAY_SECONDS=0   # gap between nodes. Set to 0 by default. Override
                          # with --delay <seconds> if you want to stagger a
                          # large default-workflow run (bootdev pxe + power
                          # cycle) so a whole rack/range doesn't hit the head
                          # node's PXE/image-sync at the same instant.
IP_OFFSET=100             # bmc-rackNNnodeXX -> 10.141.N.(100+XX)
DEFAULT_NODE_COUNT=18     # confirmed via full device list: every rack
                          # (01-08) currently has exactly 18 nodes

usage() {
  echo "pxe_rack_provision.sh version $SCRIPT_VERSION"
  echo "Usage: $0 [--dry-run] [-power on|off|cycle | -pxe] [-U <bmc_user>] [-P <bmc_pass>] [--delay <seconds>] --rack <N|N-M> [--nodes <node_count>] [--node <N>]"
  echo "  Default (neither -power nor -pxe): full PXE workflow - bootdev pxe THEN power cycle."
  echo "  -power on|off|cycle: ONLY that power action, no bootdev change."
  echo "  -pxe: ONLY the bootdev pxe (EFI) call, no power action."
  echo "  -power and -pxe are mutually exclusive."
  echo "  --rack accepts a single number (1) or a range (1-8)."
  echo "  --node <N|N-M>: target only node N (or nodes N-M) within the rack given by --rack. Requires --rack to be a single rack (not a range)."
  echo "  --delay: seconds between nodes, default $DEFAULT_DELAY_SECONDS (no delay). Set >0 to stagger a large run."
  echo "  --pxe-method ipmitool|redfish: mechanism used to set the PXE boot flag, default ipmitool. redfish is the mechanism validated to correctly target a specific NIC (e.g. 1G port) on multi-NIC nodes - see header comment."
  echo
  echo "  e.g.: $0 --rack 1                       (rack01 only, PXE workflow, real run)"
  echo "        $0 --dry-run --rack 1-8           (all 8 racks, PXE workflow, dry run)"
  echo "        $0 --rack 1-8 --delay 5           (all 8 racks, PXE workflow, stagger 5s between nodes)"
  echo "        $0 -power off --rack 1            (rack01 only, power off only)"
  echo "        $0 -pxe --rack 1                  (rack01 only, bootdev pxe flag only, no power action)"
  echo "        $0 --rack 1 --nodes 12            (rack01, override to 12 nodes)"
  echo "        $0 --rack 1 --node 18             (rack01node18 only, PXE workflow)"
  echo "        $0 --rack 8 --node 2-18            (rack08node02 through rack08node18, PXE workflow)"
  echo "        $0 -power cycle --rack 8 --node 2-18 --delay 5  (rack08node02-18, power cycle only, staggered)"
  echo "        $0 --pxe-method redfish --rack 8 --node 2-18  (rack08node02-18, PXE via Redfish instead of ipmitool)"
  echo "        $0 -U root -P 'Pass123' --rack 1  (rack01, override BMC credentials)"
  exit 1
}

DRY_RUN=0
POWER_ACTION=""   # "" = unset; else on|off|cycle
PXE_ONLY=0
PXE_METHOD="ipmitool"   # ipmitool (default) | redfish
RACK_ARG=""
NODE_COUNT=""
SINGLE_NODE=""
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
    --node)
      [[ -z "${2:-}" ]] && { echo "ERROR: --node requires a value (e.g. --node 18 or --node 2-18)."; usage; }
      [[ ! "$2" =~ ^[0-9]+(-[0-9]+)?$ ]] && { echo "ERROR: --node must be a positive integer or a range N-M (got '$2')."; usage; }
      SINGLE_NODE="$2"
      shift 2
      ;;
    --delay)
      [[ -z "${2:-}" ]] && { echo "ERROR: --delay requires a value in seconds (e.g. --delay 2)."; usage; }
      [[ ! "$2" =~ ^[0-9]+$ ]] && { echo "ERROR: --delay must be a non-negative integer (got '$2')."; usage; }
      DELAY_SECONDS="$2"
      shift 2
      ;;
    --pxe-method)
      [[ -z "${2:-}" ]] && { echo "ERROR: --pxe-method requires a value (ipmitool|redfish)."; usage; }
      case "$2" in
        ipmitool|redfish) PXE_METHOD="$2" ;;
        *) echo "ERROR: --pxe-method must be ipmitool or redfish (got '$2')."; usage ;;
      esac
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
    --version)
      echo "pxe_rack_provision.sh version $SCRIPT_VERSION"
      exit 0
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
if [[ -n "$POWER_ACTION" && "$PXE_METHOD" == "redfish" ]]; then
  echo "ERROR: --pxe-method redfish has no effect in -power-only mode (no PXE flag is set). Drop --pxe-method, or use -pxe/default mode instead."
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

if [[ -n "$SINGLE_NODE" && "$RACK_START" -ne "$RACK_END" ]]; then
  echo "ERROR: --node requires a single rack for --rack (got range '$RACK_ARG'). Specify one rack, e.g. --rack $RACK_START --node $SINGLE_NODE."
  usage
fi

NODE_START=""
NODE_END=""
if [[ -n "$SINGLE_NODE" ]]; then
  if [[ "$SINGLE_NODE" == *-* ]]; then
    NODE_START="${SINGLE_NODE%-*}"
    NODE_END="${SINGLE_NODE#*-}"
  else
    NODE_START="$SINGLE_NODE"
    NODE_END="$SINGLE_NODE"
  fi
  if [[ "$NODE_START" -gt "$NODE_END" ]]; then
    echo "ERROR: invalid --node range '$SINGLE_NODE' - start must be <= end."
    usage
  fi
  if [[ "$NODE_START" -lt 1 || "$NODE_END" -gt "${NODE_COUNT:-$DEFAULT_NODE_COUNT}" ]]; then
    echo "ERROR: --node $SINGLE_NODE is out of range for a rack of ${NODE_COUNT:-$DEFAULT_NODE_COUNT} nodes. Use --nodes to override the rack size if needed."
    usage
  fi
fi

RACK_LABEL_START=$(printf "rack%02d" "$RACK_START")
RACK_LABEL_END=$(printf "rack%02d" "$RACK_END")
if [[ -n "$SINGLE_NODE" ]]; then
  NODE_START_PADDED=$(printf "%02d" "$NODE_START")
  NODE_END_PADDED=$(printf "%02d" "$NODE_END")
  if [[ "$NODE_START" -eq "$NODE_END" ]]; then
    RANGE_LABEL="${RACK_LABEL_START}node${NODE_START_PADDED}"
  else
    RANGE_LABEL="${RACK_LABEL_START}node${NODE_START_PADDED}-node${NODE_END_PADDED}"
  fi
elif [[ "$RACK_START" -eq "$RACK_END" ]]; then
  RANGE_LABEL="$RACK_LABEL_START"
else
  RANGE_LABEL="${RACK_LABEL_START}-${RACK_LABEL_END}"
fi
NUM_RACKS=$((RACK_END - RACK_START + 1))
TOTAL_NODES=$([[ -n "$SINGLE_NODE" ]] && echo $((NODE_END - NODE_START + 1)) || echo $((NODE_COUNT * NUM_RACKS)))

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

echo "Rack(s)     : $RANGE_LABEL ($([[ -n "$SINGLE_NODE" ]] && echo "$TOTAL_NODES node$([[ $TOTAL_NODES -gt 1 ]] && echo s)" || echo "$NUM_RACKS rack$([[ $NUM_RACKS -gt 1 ]] && echo s)"))"
echo "Script ver. : $SCRIPT_VERSION"
echo "Mode        : $MODE_LABEL"
if [[ -z "$SINGLE_NODE" ]]; then
  echo "Node count  : $NODE_COUNT per rack$([[ "$NODE_COUNT" != "$DEFAULT_NODE_COUNT" ]] && echo " (overridden from default $DEFAULT_NODE_COUNT)")"
fi
echo "Total nodes : $TOTAL_NODES"
echo "PXE method  : $PXE_METHOD$([[ "$PXE_METHOD" == "redfish" ]] && echo " (Systems/$REDFISH_SYSTEM_ID)")"
echo "BMC user    : $BMC_USER"
echo "Delay/node  : ${DELAY_SECONDS}s$([[ "$DELAY_SECONDS" != "$DEFAULT_DELAY_SECONDS" ]] && echo " (overridden from default ${DEFAULT_DELAY_SECONDS}s)")"
echo "Dry run     : $([[ $DRY_RUN -eq 1 ]] && echo yes || echo no)"
echo "Log file    : $LOGFILE"
echo

if [[ $DRY_RUN -eq 0 ]]; then
  echo "!!! This will $ACTION_VERB $TOTAL_NODES node(s) across $RANGE_LABEL. !!!"
  read -rp "Type '$RANGE_LABEL' exactly to confirm and proceed: " CONFIRM
  if [[ "$CONFIRM" != "$RANGE_LABEL" ]]; then
    echo "Confirmation did not match. Aborting, nothing was sent."
    exit 1
  fi
fi

set_pxe_flag() {
  # set_pxe_flag <bmc_ip> <logfile>: sets the next-boot PXE flag using
  # $PXE_METHOD, appending raw output/errors to logfile. Returns 0/1.
  local bmc_ip="$1" logfile="$2"
  if [[ "$PXE_METHOD" == "redfish" ]]; then
    # One-shot only ("Once", never "Continuous") - does not touch BootOrder.
    # Confirmed working (2026-09-16/17, rack08node01) to correctly resolve
    # to the 1G NIC on this hardware - see header comment. REDFISH_SYSTEM_ID
    # must be correct for the target hardware, not universally "System_0".
    local http_code
    http_code=$(curl -sk -o /dev/null -w "%{http_code}" -u "${BMC_USER}:${BMC_PASS}" -X PATCH \
      -H "Content-Type: application/json" \
      -d '{"Boot": {"BootSourceOverrideEnabled": "Once", "BootSourceOverrideTarget": "Pxe"}}' \
      "https://${bmc_ip}/redfish/v1/Systems/${REDFISH_SYSTEM_ID}" 2>>"$logfile")
    echo "  (redfish PATCH to Systems/${REDFISH_SYSTEM_ID} -> HTTP $http_code)" >>"$logfile"
    [[ "$http_code" =~ ^2 ]]
  else
    ipmitool -I lanplus -H "$bmc_ip" -U "$BMC_USER" -P "$BMC_PASS" -C 17 \
      chassis bootdev pxe options=efiboot >>"$logfile" 2>&1
  fi
}

declare -a FAILED_NODES=()
declare -a OK_NODES=()

for ((r=RACK_START; r<=RACK_END; r++)); do
  RACK_LABEL=$(printf "rack%02d" "$r")
  echo "-------------------------------------------------------------------" | tee -a "$LOGFILE"
  echo "Rack: $RACK_LABEL" | tee -a "$LOGFILE"
  echo "-------------------------------------------------------------------" | tee -a "$LOGFILE"

  for ((i=$([[ -n "$SINGLE_NODE" ]] && echo "$NODE_START" || echo 1); i<=$([[ -n "$SINGLE_NODE" ]] && echo "$NODE_END" || echo "$NODE_COUNT"); i++)); do
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
      # --- PXE-flag-only mode: single call, no power action ---
      if [[ $DRY_RUN -eq 1 ]]; then
        if [[ "$PXE_METHOD" == "redfish" ]]; then
          echo "  [dry-run] would run: curl -X PATCH https://$BMC_IP/redfish/v1/Systems/$REDFISH_SYSTEM_ID (Boot.BootSourceOverrideEnabled=Once, Target=Pxe)" | tee -a "$LOGFILE"
        else
          echo "  [dry-run] would run: ipmitool -I lanplus -H $BMC_IP -U $BMC_USER -P *** -C 17 chassis bootdev pxe options=efiboot" | tee -a "$LOGFILE"
        fi
        continue
      fi

      if set_pxe_flag "$BMC_IP" "$LOGFILE"; then
        echo "  bootdev pxe ($PXE_METHOD): OK" | tee -a "$LOGFILE"
        OK_NODES+=("$HOSTNAME ($BMC_IP)")
      else
        echo "  bootdev pxe ($PXE_METHOD): FAILED" | tee -a "$LOGFILE"
        FAILED_NODES+=("$HOSTNAME ($BMC_IP) - bootdev failed")
      fi

      echo | tee -a "$LOGFILE"
      sleep "$DELAY_SECONDS"
      continue
    fi

    # --- Default mode: full PXE workflow (bootdev pxe THEN power cycle) ---
    if [[ $DRY_RUN -eq 1 ]]; then
      if [[ "$PXE_METHOD" == "redfish" ]]; then
        echo "  [dry-run] would run: curl -X PATCH https://$BMC_IP/redfish/v1/Systems/$REDFISH_SYSTEM_ID (Boot.BootSourceOverrideEnabled=Once, Target=Pxe)" | tee -a "$LOGFILE"
      else
        echo "  [dry-run] would run: ipmitool -I lanplus -H $BMC_IP -U $BMC_USER -P *** -C 17 chassis bootdev pxe options=efiboot" | tee -a "$LOGFILE"
      fi
      echo "  [dry-run] would run: ipmitool -I lanplus -H $BMC_IP -U $BMC_USER -P *** -C 17 chassis power cycle" | tee -a "$LOGFILE"
      continue
    fi

    if set_pxe_flag "$BMC_IP" "$LOGFILE"; then
      echo "  bootdev pxe ($PXE_METHOD): OK" | tee -a "$LOGFILE"
    else
      echo "  bootdev pxe ($PXE_METHOD): FAILED" | tee -a "$LOGFILE"
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
