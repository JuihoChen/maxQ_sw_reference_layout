#!/bin/bash
#
# Parses inventory.list and clones maxq106 into new cmsh device objects
# for every "COMPUTE TRAY OS" entry, across all rowXcolumnY sections.
#
# Source device : maxq106
# Section       : COMPUTE TRAY OS only (BMC / switch / PMC / leakage ignored)
# Hostname map  : row6column1 -> rack01, row6column2 -> rack02, ... columnN -> rackNN
#                 tray order in file is 18 -> 1, so hostnames are
#                 rackNNnode18 ... rackNNnode01
# IP            : not set explicitly. internalnet is DHCP-managed, and
#                 setting "ip" on the device object after clone fails with
#                 "Base name mismatch" / "Readonly properties cannot be set"
#                 (cmsh ties device.ip to the interface, e.g. enP5p9s0 - to
#                 change it you'd need: interface use enP5p9s0; set ip ...).
#                 Since DHCP handles it, we just leave it alone.
#
# Usage: ./clone_from_inventory.sh inventory.list

set -e

SOURCE_DEVICE="maxq106"
INPUT_FILE="$1"

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "Usage: $0 <inventory.list>"
  exit 1
fi

CMSH_SCRIPT=$(mktemp)
echo "device" >> "$CMSH_SCRIPT"

# awk does the parsing:
#  - detects section headers (lines starting with ## or ###)
#  - tracks current columnN -> rackNN mapping
#  - only emits MAC addresses while inside a "COMPUTE TRAY OS" section
#  - resets tray counter to 18 at the start of each such section
awk '
  /^#+[[:space:]]*CARLO_NEXT_row[0-9]+column[0-9]+/ {
    line = $0
    sub(/.*column/, "", line)
    sub(/[^0-9].*/, "", line)
    col = line + 0
    rack = sprintf("rack%02d", col)
    in_os_section = (index($0, "COMPUTE TRAY OS") > 0) ? 1 : 0
    tray = 18
    next
  }
  # any other header line (##/### not matching row/column pattern above, e.g. BMC/SWITCH/PMC/LEAKAGE) ends OS section
  /^#+/ {
    in_os_section = 0
    next
  }
  in_os_section && $1 ~ /^[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]$/ {
    mac = $1
    hostname = sprintf("%snode%02d", rack, tray)
    print hostname, mac
    tray--
  }
' "$INPUT_FILE" | while read -r HOSTNAME MAC; do
  cat >> "$CMSH_SCRIPT" <<EOF
clone ${SOURCE_DEVICE} ${HOSTNAME}
set mac ${MAC}
commit
EOF
done

echo ""
echo "Generated cmsh script:"
echo "-----------------------"
cat "$CMSH_SCRIPT"
echo "-----------------------"
echo ""
echo "Running cmsh..."
cmsh -f "$CMSH_SCRIPT"

rm -f "$CMSH_SCRIPT"

echo "Done. Verify with: cmsh -c 'device; list'"
