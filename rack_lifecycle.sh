#!/bin/bash
#
# rack_lifecycle.sh
#
# Consolidated tool for the stages a rack goes through after BCM
# provisioning: handed off to a diag-team network, diag testing, and
# (eventually) on to production/customer. Replaces running the individual
# fixes from today's session (stale DNS, nslcd/pam_ldap, DCGM device-lock)
# by hand on each node, and tracks state so re-runs are safe/idempotent.
#
# Run from a host that has root SSH access to the target nodes (a jump
# host on the same network as the nodes, not necessarily bcm11-headnode -
# see today's findings on network segregation after handoff).
#
# STATUS FILE: /etc/rack-lifecycle-state on each node, one line per stage
# recorded (e.g. "handoff=2026-09-11T15:30:00", "pre-diag=..."). Subcommands
# read/write this so e.g. post-diag only restarts DCGM if pre-diag actually
# stopped it, and status can report a real history instead of just current
# live service state.
#
# RACKGROUPS: instead of typing --ip-range every time, define named racks
# once in rackgroups.conf (same directory as this script) and target them
# by name with --rackgroup <name>. One line per rack: name=start_ip-end_ip
#
# IMPORTANT: rack numbering is NOT consistent between BCM and the diag
# team's own network - confirmed 2026-09-11, a rack BCM calls "rack08"
# turned out to occupy the same diag-network IP range (192.168.132.137-154)
# that the diag tool's own JSON spec labels "rack03". There is no reliable
# formula to derive a rack's diag-network IP range from its BCM name or
# number - each entry in rackgroups.conf must be a confirmed, looked-up
# fact (e.g. from the multinode diag log's own "Connected successfully to
# <ip>" lines, or from whoever assigns IPs on the diag network), not
# something computed. rackgroups.conf ships as an empty template - fill it
# in with your own confirmed mappings before relying on --rackgroup.
#
# --category: an ALTERNATIVE to --rackgroup, ONLY valid BEFORE a rack is
# handed off the BCM cluster network. Queries `cmsh -c "device; list"`
# live for hostnames in the given BCM category, and SSHes by hostname
# instead of IP - no static config to maintain, always current. This
# requires (a) running from a host that can execute cmsh (bcm11-headnode),
# and (b) hostname DNS resolution to actually work for those nodes, which
# only holds while they're still on BCM's internalnet (BCM's own DNS
# server is what resolves rackXXnodeXX names - see the LDAP/DNS handoff
# fix in gb300_l10_build_log.md §25d for why that stops being true once a
# rack moves to a diag-team network with BCM's DNS deliberately removed).
# Once a rack is handed off, use --rackgroup or --ip-range instead - do
# not expect --category to work there.
#
# CAVEAT on --category (2026-09-11, flagged before real use): a BCM
# category does not necessarily correspond 1:1 to a single physical rack
# - it can span multiple racks, or include template/placeholder devices
# that aren't real provisioned nodes. --category is NOT a reliable way to
# say "give me exactly rack01's 18 nodes." Use --rack instead for that.
#
# --rack <N>: the RECOMMENDED way to target a whole physical rack, still
# pre-handoff only (same cmsh/hostname-DNS requirements as --category
# above). Filters `cmsh -c "device; list"` by HOSTNAME pattern
# ^rack0*N node[0-9]+$ instead of by category - e.g. --rack 1 matches
# exactly rack01node01..rack01nodeNN and nothing else, regardless of
# what category each node happens to be assigned to, and naturally
# excludes non-matching devices like bmc-rack01node01 or the head node.
#
# SUBCOMMANDS:
#   status      Report current state (DNS, nslcd, cmsupport, DCGM, and the
#               recorded lifecycle-state history) for each target node.
#               Read-only, makes no changes.
#
#   handoff     Apply the off-cluster fixes confirmed today (2026-09-11):
#                 - comment out stale DNS=10.141.255.254 in resolved.conf
#                 - preserve cmsupport as a local account before touching LDAP
#                 - stop+disable nslcd, strip pam_ldap.so from PAM stacks
#                 - nsswitch.conf passwd/group/netgroup -> files
#               Run this once per node, right after a rack moves off the
#               BCM cluster network. Idempotent - safe to re-run.
#
#   pre-diag    Stop AND disable cuda-dcgm.service (it holds /dev/nvidia* open
#               and blocks onediagfieldmn's module-unload step - confirmed
#               root cause of SYNC_CLIENT_NOT_REGISTERED, 2026-09-11).
#               Disables, not just stops - a plain stop only affects the
#               current boot; if the node power-cycles mid-diag-campaign
#               (plausible for GB300 diag testing), an enabled service
#               comes right back with no warning. Records whether it was
#               active/enabled before, for post-diag.
#
#   post-diag   Re-enable and restart cuda-dcgm.service, but ONLY to the
#               exact active/enabled state pre-diag recorded (avoids
#               enabling a service that wasn't supposed to be enabled in
#               the first place, on some future node where that might not
#               be true).
#
#   finalize    NOT YET IMPLEMENTED - what "ready for production/customer"
#               requires hasn't been confirmed yet (does the node rejoin
#               the BCM cluster network, or move to yet another production
#               network with the off-cluster fixes staying in place?).
#               Placeholder only - exits with an error if called, on
#               purpose, so it can't be run accidentally before this is
#               actually filled in.
#
# USAGE:
#   ./rack_lifecycle.sh status --ip-range 192.168.132.137 192.168.132.154
#   ./rack_lifecycle.sh handoff --dry-run --ip-range 192.168.132.137 192.168.132.154
#   ./rack_lifecycle.sh handoff --ip-range 192.168.132.137 192.168.132.154
#   ./rack_lifecycle.sh pre-diag --ip-range 192.168.132.137 192.168.132.154
#   ...run the diag...
#   ./rack_lifecycle.sh post-diag --ip-range 192.168.132.137 192.168.132.154
#
#   Or, once rackgroups.conf has a confirmed entry for a rack:
#   ./rack_lifecycle.sh status --rackgroup rack03
#   ./rack_lifecycle.sh pre-diag --rackgroup rack03
#   ./rack_lifecycle.sh post-diag --rackgroup rack03
#
#   Or, for a rack STILL ON the BCM cluster network (before handoff) -
#   queries cmsh live, uses hostnames, no config file needed:
#   ./rack_lifecycle.sh status --rack 1
#
#   (--category also exists but is NOT recommended for whole-rack use -
#   see header caveat. --rack is the correct choice for "a whole rack".)
#
#   List all defined rackgroups:
#   ./rack_lifecycle.sh rackgroups
#
#   Single node instead of a range:
#   ./rack_lifecycle.sh status 192.168.132.137
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RACKGROUPS_FILE="${SCRIPT_DIR}/rackgroups.conf"

DRY_RUN=0
SUBCOMMAND="${1:-}"
shift || true

IP_RANGE_START=""
IP_RANGE_END=""
SINGLE_TARGET=""
RACKGROUP=""
CATEGORY=""
RACK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --ip-range)
      [[ -z "${2:-}" || -z "${3:-}" ]] && { echo "ERROR: --ip-range requires two IPs (start end)."; exit 1; }
      IP_RANGE_START="$2"; IP_RANGE_END="$3"; shift 3 ;;
    --rackgroup)
      [[ -z "${2:-}" ]] && { echo "ERROR: --rackgroup requires a name."; exit 1; }
      RACKGROUP="$2"; shift 2 ;;
    --rackgroups-file)
      [[ -z "${2:-}" ]] && { echo "ERROR: --rackgroups-file requires a path."; exit 1; }
      RACKGROUPS_FILE="$2"; shift 2 ;;
    --category)
      [[ -z "${2:-}" ]] && { echo "ERROR: --category requires a BCM category name."; exit 1; }
      CATEGORY="$2"; shift 2 ;;
    --rack)
      [[ -z "${2:-}" ]] && { echo "ERROR: --rack requires a rack number, e.g. --rack 1."; exit 1; }
      [[ ! "$2" =~ ^[0-9]+$ ]] && { echo "ERROR: --rack must be a number (got '$2')."; exit 1; }
      RACK="$2"; shift 2 ;;
    *) SINGLE_TARGET="$1"; shift ;;
  esac
done

MODE_COUNT=0
[[ -n "$IP_RANGE_START" ]] && MODE_COUNT=$((MODE_COUNT+1))
[[ -n "$RACKGROUP" ]] && MODE_COUNT=$((MODE_COUNT+1))
[[ -n "$CATEGORY" ]] && MODE_COUNT=$((MODE_COUNT+1))
[[ -n "$RACK" ]] && MODE_COUNT=$((MODE_COUNT+1))
[[ -n "$SINGLE_TARGET" ]] && MODE_COUNT=$((MODE_COUNT+1))
if [[ $MODE_COUNT -gt 1 ]]; then
  echo "ERROR: --ip-range, --rackgroup, --category, --rack, and a direct hostname/IP are mutually exclusive - pick exactly one."
  exit 1
fi

CATEGORY_TARGETS=()
if [[ -n "$RACKGROUP" ]]; then
  if [[ ! -f "$RACKGROUPS_FILE" ]]; then
    echo "ERROR: rackgroups file not found at $RACKGROUPS_FILE"
    echo "Create it (one line per rack: name=start_ip-end_ip) or pass --rackgroups-file <path>."
    exit 1
  fi
  RACKGROUP_LINE=$(grep -E "^${RACKGROUP}=" "$RACKGROUPS_FILE" | grep -v "^#")
  if [[ -z "$RACKGROUP_LINE" ]]; then
    echo "ERROR: no entry for rackgroup '$RACKGROUP' in $RACKGROUPS_FILE."
    echo "Defined rackgroups: $(grep -vE '^\s*#|^\s*$' "$RACKGROUPS_FILE" | cut -d= -f1 | tr '\n' ' ')"
    exit 1
  fi
  RANGE_PART="${RACKGROUP_LINE#*=}"
  IP_RANGE_START="${RANGE_PART%-*}"
  IP_RANGE_END="${RANGE_PART#*-}"
  echo "Resolved rackgroup '$RACKGROUP' -> $IP_RANGE_START - $IP_RANGE_END (from $RACKGROUPS_FILE)"
elif [[ -n "$CATEGORY" ]]; then
  if ! command -v cmsh >/dev/null 2>&1; then
    echo "ERROR: cmsh not found. --category only works run from a host with cmsh available (bcm11-headnode),"
    echo "and only for nodes still on the BCM cluster network - see header comment. Use --rackgroup or"
    echo "--ip-range instead for racks already handed off to another network."
    exit 1
  fi
  # Parse `cmsh -c "device; list"` output - columns are Type, Hostname, MAC,
  # Category, IP, Network, Status (space-padded, not tab-separated) - see
  # real examples of this output format in gb300_l10_build_log.md /
  # session-summary.md. Only take rows where the category column matches
  # exactly, and only "PhysicalNode" rows (skip the HeadNode row etc).
  while IFS= read -r hostname; do
    [[ -n "$hostname" ]] && CATEGORY_TARGETS+=("$hostname")
  done < <(cmsh -c "device; list" 2>/dev/null | awk -v cat="$CATEGORY" '$1=="PhysicalNode" && $4==cat {print $2}')
  if [[ ${#CATEGORY_TARGETS[@]} -eq 0 ]]; then
    echo "ERROR: cmsh returned no PhysicalNode entries for category '$CATEGORY'."
    echo "Check the category name is exact: cmsh -c \"device; list\" | awk '\$1==\"PhysicalNode\"{print \$4}' | sort -u"
    exit 1
  fi
  echo "Resolved category '$CATEGORY' -> ${#CATEGORY_TARGETS[@]} node(s) via cmsh: ${CATEGORY_TARGETS[*]}"
  echo "NOTE: targeting by hostname - only valid while these nodes are still on the BCM cluster network"
  echo "      (see header comment - hostname DNS resolution stops working once a rack is handed off)."
elif [[ -n "$RACK" ]]; then
  if ! command -v cmsh >/dev/null 2>&1; then
    echo "ERROR: cmsh not found. --rack only works run from a host with cmsh available (bcm11-headnode),"
    echo "and only for nodes still on the BCM cluster network - see header comment. Use --rackgroup or"
    echo "--ip-range instead for racks already handed off to another network."
    exit 1
  fi
  RACK_PADDED=$(printf "rack%02d" "$RACK")
  # Match hostname exactly against ^rack0*Nnode[0-9]+$ - deliberately by
  # hostname, not category (see header caveat: categories don't reliably
  # map 1:1 to a physical rack). This also naturally excludes similarly-
  # named but different devices like bmc-rack01node01.
  while IFS= read -r hostname; do
    [[ -n "$hostname" ]] && CATEGORY_TARGETS+=("$hostname")
  done < <(cmsh -c "device; list" 2>/dev/null | awk -v pat="^${RACK_PADDED}node[0-9]+\$" '$1=="PhysicalNode" && $2 ~ pat {print $2}')
  if [[ ${#CATEGORY_TARGETS[@]} -eq 0 ]]; then
    echo "ERROR: cmsh returned no PhysicalNode entries matching hostname pattern ^${RACK_PADDED}node[0-9]+\$."
    echo "Check the rack number is right: cmsh -c \"device; list\" | awk '\$1==\"PhysicalNode\"{print \$2}' | sort -u"
    exit 1
  fi
  echo "Resolved rack '$RACK_PADDED' -> ${#CATEGORY_TARGETS[@]} node(s) via cmsh (by hostname): ${CATEGORY_TARGETS[*]}"
  echo "NOTE: targeting by hostname - only valid while these nodes are still on the BCM cluster network"
  echo "      (see header comment - hostname DNS resolution stops working once a rack is handed off)."
fi

usage() {
  echo "Usage: $0 <status|handoff|pre-diag|post-diag> [--dry-run] <hostname|IP>"
  echo "       $0 <status|handoff|pre-diag|post-diag> [--dry-run] --ip-range <start_ip> <end_ip>"
  echo "       $0 <status|handoff|pre-diag|post-diag> [--dry-run] --rackgroup <name>"
  echo "       $0 <status|handoff|pre-diag|post-diag> [--dry-run] --rack <N>            (pre-handoff, RECOMMENDED for whole-rack)"
  echo "       $0 <status|handoff|pre-diag|post-diag> [--dry-run] --category <bcm-category>  (pre-handoff, NOT reliable for whole-rack)"
  echo "       $0 rackgroups                     (list defined rackgroups)"
  echo "See header comment for full documentation."
  exit 1
}

if [[ "$SUBCOMMAND" == "rackgroups" ]]; then
  if [[ ! -f "$RACKGROUPS_FILE" ]]; then
    echo "No rackgroups file found at $RACKGROUPS_FILE"
    exit 1
  fi
  echo "Defined rackgroups (from $RACKGROUPS_FILE):"
  grep -vE '^\s*#|^\s*$' "$RACKGROUPS_FILE"
  exit 0
fi

case "$SUBCOMMAND" in
  status|handoff|pre-diag|post-diag) ;;
  finalize)
    echo "ERROR: 'finalize' is not yet implemented - what 'ready for production/customer' actually"
    echo "requires (rejoin BCM cluster? move to a different production network? something else?)"
    echo "hasn't been confirmed yet. Fill this in once that's decided - see header comment."
    exit 1
    ;;
  *) echo "ERROR: unknown or missing subcommand '$SUBCOMMAND'."; usage ;;
esac

[[ -z "$IP_RANGE_START" && -z "$SINGLE_TARGET" && ${#CATEGORY_TARGETS[@]} -eq 0 ]] && usage

if [[ -n "$IP_RANGE_START" ]]; then
  IP_PREFIX_START="${IP_RANGE_START%.*}"
  IP_PREFIX_END="${IP_RANGE_END%.*}"
  LAST_OCTET_START="${IP_RANGE_START##*.}"
  LAST_OCTET_END="${IP_RANGE_END##*.}"
  if [[ "$IP_PREFIX_START" != "$IP_PREFIX_END" ]]; then
    echo "ERROR: --ip-range start and end must be on the same /24 subnet."
    exit 1
  fi
  if ! [[ "$LAST_OCTET_START" =~ ^[0-9]+$ && "$LAST_OCTET_END" =~ ^[0-9]+$ ]] || [[ "$LAST_OCTET_START" -gt "$LAST_OCTET_END" ]]; then
    echo "ERROR: invalid IP range."
    exit 1
  fi
fi

remote() {
  # remote <target> <script>: run $script on $target via ssh, unless dry-run.
  local target="$1" script="$2"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] would run on $target:"
    echo "$script"
  else
    ssh "root@${target}" "$script"
  fi
}

do_status() {
  local target="$1"
  echo "=== $target ==="
  remote "$target" '
echo "DNS static entry : $(grep "^DNS=" /etc/systemd/resolved.conf 2>/dev/null || echo none)"
echo "nslcd            : $(systemctl is-active nslcd 2>/dev/null || echo not-installed)"
echo "cmsupport        : $(id cmsupport 2>&1)"
echo "cuda-dcgm        : active=$(systemctl is-active cuda-dcgm.service 2>/dev/null || echo not-installed) enabled=$(systemctl is-enabled cuda-dcgm.service 2>/dev/null || echo n/a)"
echo "nsswitch passwd  : $(grep "^passwd:" /etc/nsswitch.conf 2>/dev/null)"
echo "lifecycle state  :"
cat /etc/rack-lifecycle-state 2>/dev/null || echo "  (no recorded history)"
'
  echo
}

do_handoff() {
  local target="$1"
  echo "=== $target ==="
  remote "$target" '
set -u
echo "--- step 1: fix stale DNS entry ---"
if grep -q "^DNS=10.141.255.254" /etc/systemd/resolved.conf 2>/dev/null; then
  sed -i "s/^DNS=10.141.255.254/#DNS=10.141.255.254/" /etc/systemd/resolved.conf
  systemctl restart systemd-resolved
  echo "  fixed and restarted systemd-resolved"
else
  echo "  no stale DNS=10.141.255.254 line found, skipping"
fi

echo "--- step 2: preserve cmsupport as a LOCAL account before touching LDAP ---"
if id cmsupport >/dev/null 2>&1 && ! grep -q "^cmsupport:" /etc/passwd; then
  useradd -u 1000 -g 1000 -s /bin/bash -m -c "cmsupport (local, off-cluster)" cmsupport 2>&1 || \
    echo "  WARNING: useradd failed - check for uid/gid 1000 conflict"
else
  echo "  cmsupport already local, or did not resolve before this fix - nothing to do"
fi

echo "--- step 3: stop LDAP client daemon ---"
if systemctl list-unit-files nslcd.service >/dev/null 2>&1; then
  systemctl stop nslcd; systemctl disable nslcd
  echo "  nslcd stopped and disabled"
else
  echo "  nslcd not installed, skipping"
fi

echo "--- step 4: remove pam_ldap.so from PAM stacks ---"
for f in /etc/pam.d/common-account /etc/pam.d/common-auth /etc/pam.d/common-session; do
  [[ -f "$f" ]] && grep -q "pam_ldap\.so" "$f" && sed -i "/pam_ldap\.so/d" "$f" && echo "  removed from $f"
done

echo "--- step 5: nsswitch.conf to files-only ---"
sed -i "s/^passwd:.*/passwd:     files/; s/^group:.*/group:      files/; s/^netgroup:.*/netgroup:   files/" /etc/nsswitch.conf

echo "--- recording state ---"
echo "handoff=$(date -Iseconds)" >> /etc/rack-lifecycle-state

echo "--- verify ---"
echo "cmsupport: $(id cmsupport 2>&1)"
'
  echo "--- timing check ---"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] would run: time ssh -o BatchMode=yes root@${target} true"
  else
    time ssh -o BatchMode=yes "root@${target}" true
  fi
  echo
}

do_pre_diag() {
  local target="$1"
  echo "=== $target ==="
  remote "$target" '
set -u
WAS_ACTIVE=$(systemctl is-active cuda-dcgm.service 2>/dev/null)
WAS_ENABLED=$(systemctl is-enabled cuda-dcgm.service 2>/dev/null)
# disable (not just stop) - a plain "stop" only affects the current boot;
# if the node power-cycles mid-diag-campaign (plausible - diag tests can
# include reboot/power scenarios), an enabled service comes right back
# and silently reintroduces the device-lock conflict with no warning.
systemctl disable --now cuda-dcgm.service 2>&1
echo "cuda-dcgm: was active=$WAS_ACTIVE enabled=$WAS_ENABLED - now disabled+stopped (survives reboot/power-cycle)"
echo "pre-diag=$(date -Iseconds):was-active=${WAS_ACTIVE}:was-enabled=${WAS_ENABLED}" >> /etc/rack-lifecycle-state
echo "verify /dev/nvidia* now free of dcgm:"
lsof /dev/nvidia-uvm /dev/nvidia0 2>/dev/null | grep -v COMMAND || echo "  (clean)"
'
  echo
}

do_post_diag() {
  local target="$1"
  echo "=== $target ==="
  remote "$target" '
set -u
LAST_PREDIAG=$(grep "^pre-diag=" /etc/rack-lifecycle-state 2>/dev/null | tail -1)
if [[ -z "$LAST_PREDIAG" ]]; then
  echo "WARNING: no pre-diag record found - not touching cuda-dcgm. Check manually:"
  systemctl is-active cuda-dcgm.service 2>/dev/null
  echo "post-diag=$(date -Iseconds):no-pre-diag-record-skipped" >> /etc/rack-lifecycle-state
else
  WAS_ACTIVE=$(echo "$LAST_PREDIAG" | grep -oP "was-active=\K[a-z]+")
  WAS_ENABLED=$(echo "$LAST_PREDIAG" | grep -oP "was-enabled=\K[a-z]+")
  if [[ "$WAS_ENABLED" == "enabled" ]]; then
    systemctl enable cuda-dcgm.service 2>&1
  fi
  if [[ "$WAS_ACTIVE" == "active" ]]; then
    systemctl start cuda-dcgm.service 2>&1
  fi
  echo "Restored cuda-dcgm to pre-diag state (was active=$WAS_ACTIVE enabled=$WAS_ENABLED)"
  echo "post-diag=$(date -Iseconds):restored-active=${WAS_ACTIVE}:restored-enabled=${WAS_ENABLED}" >> /etc/rack-lifecycle-state
fi
echo "current cuda-dcgm: active=$(systemctl is-active cuda-dcgm.service 2>/dev/null) enabled=$(systemctl is-enabled cuda-dcgm.service 2>/dev/null)"
'
  echo
}

run_subcommand() {
  local target="$1"
  case "$SUBCOMMAND" in
    status) do_status "$target" ;;
    handoff) do_handoff "$target" ;;
    pre-diag) do_pre_diag "$target" ;;
    post-diag) do_post_diag "$target" ;;
  esac
}

if [[ -n "$IP_RANGE_START" ]]; then
  echo "IP range: ${IP_PREFIX_START}.${LAST_OCTET_START} - ${IP_PREFIX_START}.${LAST_OCTET_END}, subcommand: $SUBCOMMAND"
  echo
  for ((octet=LAST_OCTET_START; octet<=LAST_OCTET_END; octet++)); do
    run_subcommand "${IP_PREFIX_START}.${octet}"
  done
elif [[ ${#CATEGORY_TARGETS[@]} -gt 0 ]]; then
  echo "Category targets (${#CATEGORY_TARGETS[@]} nodes), subcommand: $SUBCOMMAND"
  echo
  for hostname in "${CATEGORY_TARGETS[@]}"; do
    run_subcommand "$hostname"
  done
else
  run_subcommand "$SINGLE_TARGET"
fi
