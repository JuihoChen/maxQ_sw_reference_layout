#!/bin/bash
#
# *** DEPRECATED 2026-09-22 -- DO NOT USE FOR NEW RACKS ***
#
# Superseded by resync_rack_macs.sh. Production-line provisioning is
# now rack-by-rack through fixed bay slots (rack01, rack08, ...): the
# BCM device objects for each slot are built once and stay in place;
# a new physical rack rotating into a slot only needs its MAC
# addresses swapped in, not a fresh set of cloned device objects.
# resync_rack_macs.sh does exactly that (device use <existing-hostname>;
# set mac <new-mac>; commit) and additionally covers the
# SWITCH TRAY NVOS section that this script never did.
#
# This script's clone sources (base-bmc, maxq106) have been REMOVED
# from cmsh as of 2026-09-22 -- running this as-is will fail
# immediately on the first "clone" command. It's kept here only for
# historical reference (e.g. if a genuinely new bay slot/rack position
# needs to be built from scratch for the first time, in which case the
# clone-from-source approach below is still the right starting point --
# but note it was found to be unsafe to clone from a *live* node that
# holds a BCM role (see 2026-09-21 investigation: cloning from
# rack01node01 while it held the `provisioning` role would have carried
# that role onto every cloned node). Any revival of this approach needs
# a clean, role-free source device re-created first.
#
# --- Original header below, left unmodified for reference ---
#
# Parses inventory.list and clones cmsh device objects for every
# "COMPUTE TRAY BMC" and "COMPUTE TRAY OS" entry, across all
# rowXcolumnY sections. Single pass, single cmsh invocation.
#
# Source devices : base-bmc (BMC nodes), maxq106 (OS nodes)
# Sections       : COMPUTE TRAY BMC, COMPUTE TRAY OS
#                  (switch / PMC / leakage sections are ignored)
# Section header : any "#+ CARLO_NEXT_..." line. Rack number is read
#                  from a "rackNN" token if present (e.g.
#                  CARLO_NEXT_t1_rack01), else from a "columnN" token
#                  (older "rowXcolumnY" style inventories).
# Hostname map   : rack number -> rackNN
#                  tray order in file is 18 -> 1, so hostnames are
#                  node18 ... node01 within each rack
#                    BMC nodes: bmc-rackNNnodeMM
#                    OS  nodes: rackNNnodeMM
# IP             : static for both, set via
#                    "interfaces; use <iface>; set ip ...; commit"
#                  since device-level "set ip" is readonly after clone.
#                    BMC nodes: 10.141.<rack#>.<100+tray#>
#                      e.g. bmc-rack08node01 -> 10.141.8.101
#                    OS  nodes: 10.141.<160+rack#>.<100+tray#>
#                      e.g. rack08node01      -> 10.141.168.101
#                  (offset by 100 to avoid the .1 gateway address;
#                   OS network offset by +160 on the 3rd octet to
#                   keep BMC and OS address space distinct)
#
# Usage: ./clone_all_from_inventory.sh [-n|--dry-run] inventory.list
#   -n, --dry-run   Parse the inventory and print the generated cmsh
#                   script, but do not actually invoke cmsh.

echo "*** clone_all_from_inventory.sh is DEPRECATED as of 2026-09-22 ***" >&2
echo "Use resync_rack_macs.sh instead for rack-by-rack MAC resync of" >&2
echo "existing bay-slot device objects. See the header of this script" >&2
echo "for why, and for when reviving this approach would still be" >&2
echo "appropriate (a genuinely new bay slot, never built before)." >&2
echo "Refusing to run. Remove this guard only if you've re-verified" >&2
echo "the clone-source setup (see header) and really mean to use this." >&2
exit 1

set -e

SOURCE_BMC="base-bmc"
SOURCE_OS="maxq106"
BMC_IFACE="eth0"
OS_IFACE="enP5p9s0"
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

# awk does the parsing:
#  - detects section headers (lines starting with #+ CARLO_NEXT_rowXcolumnY)
#  - tracks current columnN -> rack number
#  - classifies each such section as bmc / os / other based on its label
#  - resets tray counter to 18 at the start of each COMPUTE TRAY section
#  - any other header line ends the current section
#  - emits: type hostname mac ip   (type is "bmc" or "os")
awk '
  /^#+[[:space:]]*CARLO_NEXT_/ {
    # Rack/column number can show up two ways depending on inventory
    # format: "...rowXcolumnY..." (older format) or "...rackNN..."
    # (e.g. CARLO_NEXT_t1_rack01). Handle both.
    if (match($0, /rack[0-9]+/)) {
      col = substr($0, RSTART + 4, RLENGTH - 4) + 0
    } else if (match($0, /column[0-9]+/)) {
      col = substr($0, RSTART + 6, RLENGTH - 6) + 0
    } else {
      col = 0
    }
    if (index($0, "COMPUTE TRAY BMC") > 0) {
      section = "bmc"
    } else if (index($0, "COMPUTE TRAY OS") > 0) {
      section = "os"
    } else {
      # any other CARLO_NEXT_ header (SWITCH TRAY BMC/NVOS, PMC,
      # LEAKAGE DETECTION, etc.) - not a section we clone from
      section = ""
    }
    tray = 18
    next
  }
  # any other header line also ends the current section
  /^#+/ {
    section = ""
    next
  }
  section != "" && $1 ~ /^[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]$/ {
    mac = $1
    if (section == "bmc") {
      hostname = sprintf("bmc-rack%02dnode%02d", col, tray)
      ip = sprintf("10.141.%d.%d", col, tray + 100)
    } else {
      hostname = sprintf("rack%02dnode%02d", col, tray)
      ip = sprintf("10.141.%d.%d", col + 160, tray + 100)
    }
    print section, hostname, mac, ip
    tray--
  }
' "$INPUT_FILE" | while read -r TYPE HOSTNAME MAC IP; do
  if [ "$TYPE" = "bmc" ]; then
    SRC="$SOURCE_BMC"
    IFACE="$BMC_IFACE"
    # BMC interface is plain static, no DHCP toggle needed.
    IFACE_CMDS="set ip ${IP}"
  else
    SRC="$SOURCE_OS"
    IFACE="$OS_IFACE"
    # OS interface is DHCP-managed ("prov,dhcp"); "set ip" alone is
    # rejected while dhcp is on, so flip it off, set the static IP,
    # then flip dhcp back on (cmsh keeps the static IP once set,
    # matching the "prov,dhcp" + fixed-IP behavior seen via cmsh GUI/CLI).
    IFACE_CMDS="set dhcp no
set ip ${IP}
set dhcp yes"
  fi
  cat >> "$CMSH_SCRIPT" <<EOF
clone ${SRC} ${HOSTNAME}
use ${HOSTNAME}
set mac ${MAC}
interfaces
use ${IFACE}
${IFACE_CMDS}
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
