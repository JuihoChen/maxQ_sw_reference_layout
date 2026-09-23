#!/bin/bash
#
# Re-points existing BCM device objects (bay slots) at new physical
# hardware by updating only their MAC address, for every "COMPUTE TRAY
# BMC", "COMPUTE TRAY OS", and "SWITCH TRAY NVOS" entry in
# inventory.list.
#
# Unlike clone_all_from_inventory.sh, this does NOT create new device
# objects. It assumes the target hostnames (rackNNnodeMM /
# bmc-rackNNnodeMM / nvs-rackNNswN) already exist in cmsh, fully
# configured (category, disk setup, roles, static IP) from a prior
# build -- e.g. rack01 and rack08 acting as fixed production-line bay
# slots that a new physical rack rotates through. Only the "mac" field
# is changed; hostname, IP, category and role assignments are left
# exactly as they are.
#
# Section header / hostname derivation for COMPUTE TRAY BMC/OS:
# identical to clone_all_from_inventory.sh -- see that script's header
# comment for the full parsing rules (CARLO_NEXT_ sections,
# rackNN/columnN token, tray order 18 -> 1 within each section).
#
# SWITCH TRAY NVOS: hostname is nvs-rack<NN>sw<N> (N = 1..9, no
# zero-padding, matching existing nvs-rack01sw1..sw9 objects). MACs in
# this section are listed descending, tray 9 -> 1 (same direction as
# the compute tray sections, and matches the file's own
# "( FROM TRAY 9 TO 1 )" header) -- verified 2026-09-22 against a real
# t1_rack01.list against the live nvs-rack01sw1..sw9 device MACs, exact
# match.
#
# NOTE: inventory files also contain a "SWITCH TRAY BMC" section
# (9 entries/rack, same tray-9-to-1 ordering) which this script does
# NOT currently parse/act on -- there's no corresponding
# bmc-nvs-rack<NN>sw<N> (or similar) device object convention
# established yet. PMC and LEAKAGE DETECTION sections are intentionally
# ignored (not BCM device objects).
#
# NOTE: each data line in inventory files has two columns (MAC, then a
# second address -- e.g. 192.168.13.119) rather than MAC alone. Only
# the first column is used; the second is ignored here, same as
# clone_all_from_inventory.sh.
#
# IMPORTANT: this only updates cmsh's record of which MAC maps to which
# hostname/IP. It does NOT power-cycle or reinstall anything. After
# running this, the new hardware will PXE/DHCP under its new identity
# the next time it's rebooted -- follow up with the normal provisioning
# steps (SOP Section 3) to actually image it.
#
# Safety note: if the OLD hardware that previously held this MAC is
# still powered on and connected when you run this, you can end up with
# two devices answering to the same hostname's old vs new MAC
# transiently. Power off / disconnect the outgoing unit before swapping
# in the new one where practical.
#
# Usage: ./resync_rack_macs.sh [-n|--dry-run] inventory.list

set -e

DRY_RUN=0
INPUT_FILE=""

for arg in "$@"; do
  case "$arg" in
    -n|--dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      echo "Usage: $0 [-n|--dry-run] <inventory.list>"
      exit 0
      ;;
    *)
      INPUT_FILE="$arg"
      ;;
  esac
done

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "Usage: $0 [-n|--dry-run] <inventory.list>"
  exit 1
fi

CMSH_SCRIPT=$(mktemp)
echo "device" >> "$CMSH_SCRIPT"

awk '
  /^#+[[:space:]]*CARLO_NEXT_/ {
    if (match($0, /rack[0-9]+/)) {
      col = substr($0, RSTART + 4, RLENGTH - 4) + 0
    } else if (match($0, /column[0-9]+/)) {
      col = substr($0, RSTART + 6, RLENGTH - 6) + 0
    } else {
      col = 0
    }
    if (index($0, "COMPUTE TRAY BMC") > 0) {
      section = "bmc"
      tray = 18
    } else if (index($0, "COMPUTE TRAY OS") > 0) {
      section = "os"
      tray = 18
    } else if (index($0, "SWITCH TRAY NVOS") > 0) {
      section = "switch"
      tray = 9
    } else {
      section = ""
    }
    next
  }
  /^#+/ {
    section = ""
    next
  }
  section != "" && $1 ~ /^[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]$/ {
    mac = $1
    if (section == "bmc") {
      hostname = sprintf("bmc-rack%02dnode%02d", col, tray)
    } else if (section == "os") {
      hostname = sprintf("rack%02dnode%02d", col, tray)
    } else {
      hostname = sprintf("nvs-rack%02dsw%d", col, tray)
    }
    print section, hostname, mac
    tray--
  }
' "$INPUT_FILE" | while read -r TYPE HOSTNAME MAC; do
  cat >> "$CMSH_SCRIPT" <<EOF
use ${HOSTNAME}
set mac ${MAC}
commit
main
device
EOF
done

echo ""
echo "Generated cmsh script:"
echo "-----------------------"
cat "$CMSH_SCRIPT"
echo "-----------------------"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run: cmsh was NOT invoked. Nothing was changed."
  echo "Review the script above, then re-run without -n/--dry-run to apply it."
  rm -f "$CMSH_SCRIPT"
  exit 0
fi

echo "Running cmsh..."
cmsh -f "$CMSH_SCRIPT"

rm -f "$CMSH_SCRIPT"

echo "Done. Verify with: cmsh -c 'device; list -f hostname:20,mac:20,ip:15'"
echo "Next: power-cycle the new hardware and follow SOP Section 3 to (re)provision it."
