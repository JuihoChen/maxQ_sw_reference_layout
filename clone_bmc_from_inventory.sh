#!/bin/bash
#
# Parses inventory.list and clones base-bmc into new cmsh device objects
# for every "COMPUTE TRAY BMC" entry, across all rowXcolumnY sections.
#
# Source device : base-bmc
# Section       : COMPUTE TRAY BMC only (OS / switch / PMC / leakage ignored)
# Hostname map  : row6column1 -> rack01, ... columnN -> rackNN
#                 tray order in file is 18 -> 1, so hostnames are
#                 bmc-rack01node18 ... bmc-rack01node01, etc.
#                 (paired with OS node rackNNnodeMM)
# IP            : static, 10.141.<rack#>.<100+tray#>  e.g. bmc-rack01node18 -> 10.141.1.118
#                 (offset by 100 to avoid the .1 gateway address)
#                 Set via "interfaces; use eth0; set ip ...; commit" since
#                 device-level "set ip" is readonly after clone.
#
# Usage: ./clone_bmc_from_inventory.sh inventory.list

set -e

SOURCE_DEVICE="base-bmc"
BMC_IFACE="eth0"
INPUT_FILE="$1"

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "Usage: $0 <inventory.list>"
  exit 1
fi

CMSH_SCRIPT=$(mktemp)

awk '
  /^#+[[:space:]]*CARLO_NEXT_row[0-9]+column[0-9]+/ {
    line = $0
    sub(/.*column/, "", line)
    sub(/[^0-9].*/, "", line)
    col = line + 0
    rack = sprintf("rack%02d", col)
    in_bmc_section = (index($0, "COMPUTE TRAY BMC") > 0) ? 1 : 0
    tray = 18
    next
  }
  # any other header line ends the section (SWITCH TRAY BMC, COMPUTE TRAY OS, PMC, etc.)
  /^#+/ {
    in_bmc_section = 0
    next
  }
  in_bmc_section && $1 ~ /^[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]$/ {
    mac = $1
    hostname = sprintf("bmc-rack%02dnode%02d", col, tray)
    ip = sprintf("10.141.%d.%d", col, tray + 100)
    print hostname, mac, ip
    tray--
  }
' "$INPUT_FILE" | while read -r HOSTNAME MAC IP; do
  cat >> "$CMSH_SCRIPT" <<EOF
device
clone ${SOURCE_DEVICE} ${HOSTNAME}
set mac ${MAC}
commit
use ${HOSTNAME}
interfaces
use ${BMC_IFACE}
set ip ${IP}
commit
main
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

echo "Done. Verify with: cmsh -c 'device; list -f hostname:20,mac:20,ip:15' | grep bmc"
