#!/usr/bin/env bash
#
# gb300_l10_bmc_redfish_remote.sh
#
# Purpose : REMOTE, out-of-band read of a GB300 NVL compute tray's BMC over
#           Redfish - BMC/HMC firmware, BIOS, system identity, health, clock,
#           GPU VBIOS and the FirmwareInventory - compared against the same
#           NVIDIA 2.0.0GA targets used by gb300_l10_sw_checklist.sh.
#
#           Runs from any diag workstation (Linux or macOS) that can reach the
#           BMC management network. Needs NO login, agent or root on the host
#           OS, and works while the host is powered off (BMC on standby power).
#
# Usage   : ./gb300_l10_bmc_redfish_remote.sh -H <bmc_ip_or_name> [options]
#
#             -H host     BMC IP / hostname[:port]                (required)
#             -u user     Redfish user      (default: $BMC_USER, else root)
#             -o file     also write a plain-text report to <file>
#             -d dir      save every raw Redfish JSON response under <dir>
#                         (hand this to whoever does offline analysis)
#             -a          list ALL FirmwareInventory components, not only
#                         BMC/HMC/CPLD/EROT/FPGA/SMA
#             -C cafile   verify the BMC TLS cert against <cafile>
#                         (default: skip verification, see TLS note below)
#             -t secs     per-request timeout, default 20
#             -v          print version and exit
#
#           Password: taken from $BMC_PASS if set; otherwise prompted (hidden)
#           when run from a terminal - just press Enter at the prompt to use
#           the MaxQ factory default (0penBmc); with no terminal it falls back
#           to that same default with a warning. The password never appears on any command
#           line, so it is not visible in `ps` on a shared diag host.
#
#           Whole rack (export BMC_PASS once so it isn't prompted per tray):
#             export BMC_PASS='...'
#             for h in 10.0.1.{11..28}; do
#               ./gb300_l10_bmc_redfish_remote.sh -H "$h" -o "rf_${h}.log"
#             done
#
# Requires: bash 3.2+, curl, jq. Nothing on the target host.
#
# Exit    : 0 = report produced (check the summary for CHECK/MISSING rows)
#           2 = could not produce a report (BMC unreachable, bad credentials,
#               missing curl/jq, bad arguments)
#
# NOT covered here (in-band only, no Redfish equivalent - keep running
# gb300_l10_sw_checklist.sh on the host for these): OS/kernel/page size, apt
# holds, NVIDIA driver/CUDA/nvcc, IMEX/Fabric Manager packages, MOFED/DOCA/MFT,
# BF3/CX8 firmware via flint, DCGM/container runtime, disk hygiene, golden-image
# readiness.
#
# ------------------------------------------------------------------------
# Changelog
#   0.5.0  2026-11-13  Branched from gb300_l10_sw_checklist.sh v0.4.30 (see
#                       that file for the full history behind every EXPECTED_*
#                       value and the FirmwareInventory matching rules) for
#                       the diag team, who need BMC data remotely over Redfish
#                       rather than from a root shell on the host.
#                       (1) BMC address is now an argument (-H) instead of
#                       being discovered in-band via `ipmitool lan print 1`;
#                       root/EUID check removed (nothing local needs it).
#                       (2) In-band sections removed (listed above).
#                       (3) Auth: Redfish session (X-Auth-Token) with
#                       automatic fallback to basic auth; session is deleted
#                       on exit so repeated runs don't exhaust the BMC's
#                       session slots. Credentials passed to curl via a
#                       config fd, never argv.
#                       (4) Up-front reachability/auth probe - a dead or
#                       wrong-password BMC now fails fast with a clear reason
#                       instead of a wall of N/A rows.
#                       (5) New Redfish reads replacing in-band equivalents:
#                       Systems (BIOS version - was `dmidecode -s
#                       bios-version`; model/serial - was `dmidecode -s
#                       system-product-name`; power state; health), GPU VBIOS
#                       via Systems/*/Processors (best-effort - was
#                       nvidia-smi; reported N/A if this BMC doesn't expose
#                       Processor.FirmwareVersion).
#                       (6) New BMC-only reads: Managers (FW, health, clock
#                       drift vs. the diag host, NIC MAC/IP), Chassis health
#                       roll-up, Redfish service identity.
#                       (7) FirmwareInventory logic carried over unchanged
#                       (two-step GET - $expand is NOT honored by this
#                       Pegatron BMC, v0.4.15; HGX_FW_-anchored matching,
#                       v0.4.28), plus -a to list everything.
#                       (8) curl uses --noproxy for the BMC host, so a
#                       workstation's corporate HTTPS_PROXY doesn't swallow
#                       management-network traffic.
#                       (9) Summary table is now grouped under section
#                       headers (sections used to print as empty headings
#                       before the table).
# ------------------------------------------------------------------------

SCRIPT_VERSION="0.5.0"

set -uo pipefail

# ----------------------------------------------------------------------------
# 0. Config: expected versions - copied verbatim from gb300_l10_sw_checklist.sh
#    v0.4.30 (RN-11874-001_2.0.0GA rev 18). Keep the two files in sync on the
#    next GA reconciliation.
# ----------------------------------------------------------------------------
EXPECTED_HGX_BMC_FW="GB200Nvl-26.07-1"     # GA release notes BMC bundle, §0a
EXPECTED_HGX_EROT_FW="01.04.0055.0000_n04" # GA release notes BMC bundle + HMC EROT, §0a
EXPECTED_HGX_CPLD_FW="0.22"                # HGX baseboard CPLD ONLY - not FW_E1S_CPLD_* (v0.4.28)
EXPECTED_HGX_FPGA_FW="1.66"                # compute-tray/HMC FPGA - NOT the switch-tray 0.24 (§0b)
EXPECTED_MCU_SMA_FW="0003.00.0278.0000"    # GA release notes MCU SMA Firmware, §0a
EXPECTED_VBIOS="97.10.7D.00.16"            # GA HMC "GPU" field = VBIOS (v0.4.25)
CLOCK_DRIFT_MAX=300                        # seconds; BMC clock vs. diag host before CHECK
FACTORY_PASS="0penBmc"                     # MaxQ factory default (same as v0.4.14)

# ----------------------------------------------------------------------------
# 1. Arguments / prerequisites
# ----------------------------------------------------------------------------
usage() {
  sed -n '/^# Usage/,/^# Requires/p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

BMC_HOST=""
BMC_USER="${BMC_USER:-root}"
LOGFILE=""
DUMP_DIR=""
SHOW_ALL=0
CA_FILE=""
RF_TIMEOUT=20

while getopts "H:u:o:d:aC:t:vh" opt; do
  case "$opt" in
    H) BMC_HOST="$OPTARG" ;;
    u) BMC_USER="$OPTARG" ;;
    o) LOGFILE="$OPTARG" ;;
    d) DUMP_DIR="$OPTARG" ;;
    a) SHOW_ALL=1 ;;
    C) CA_FILE="$OPTARG" ;;
    t) RF_TIMEOUT="$OPTARG" ;;
    v) echo "gb300_l10_bmc_redfish_remote.sh version $SCRIPT_VERSION"; exit 0 ;;
    *) usage ;;
  esac
done

[[ -z "$BMC_HOST" ]] && { echo "ERROR: -H <bmc_ip_or_name> is required." >&2; usage; }

for bin in curl jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: '$bin' not found on this workstation - install it and re-run." >&2
    exit 2
  fi
done

if [[ -n "$CA_FILE" && ! -r "$CA_FILE" ]]; then
  echo "ERROR: CA file '$CA_FILE' not readable." >&2
  exit 2
fi

if [[ -n "$DUMP_DIR" ]]; then
  mkdir -p "$DUMP_DIR" || { echo "ERROR: cannot create dump dir '$DUMP_DIR'." >&2; exit 2; }
fi

# Password: env > hidden prompt > factory default (non-interactive only).
if [[ -z "${BMC_PASS+x}" ]]; then
  if [[ -t 0 ]]; then
    read -r -s -p "Redfish password for ${BMC_USER}@${BMC_HOST} [Enter = factory default]: " BMC_PASS
    echo >&2
    if [[ -z "$BMC_PASS" ]]; then
      BMC_PASS="$FACTORY_PASS"
      echo "Using the MaxQ factory default password." >&2
    fi
  else
    BMC_PASS="$FACTORY_PASS"
    echo "WARNING: BMC_PASS not set and no terminal to prompt - trying the MaxQ factory default." >&2
  fi
fi

# TLS: BMCs almost always ship self-signed certs, so verification is skipped
# by default (-k), same as the in-band script. Pass -C <cafile> to verify.
if [[ -n "$CA_FILE" ]]; then
  TLS_OPTS=(--cacert "$CA_FILE")
else
  TLS_OPTS=(-k)
fi

# Accepts: 10.0.1.11 | bmc-tray01 | 10.0.1.11:8443 | fe80::1 | [fe80::1]:443
# host:port is handy when the BMC is reached through an SSH tunnel
# (ssh -L 8443:<bmc>:443 jumphost  ->  -H 127.0.0.1:8443).
colons="${BMC_HOST//[^:]/}"
if [[ ${#colons} -ge 2 && "$BMC_HOST" != \[* ]]; then
  url_host="[$BMC_HOST]"            # bare IPv6 literal
else
  url_host="$BMC_HOST"
fi
BMC_BASE="https://${url_host}"
# Host part only (no port/brackets) for --noproxy matching.
NOPROXY_HOST="${url_host#[}"; NOPROXY_HOST="${NOPROXY_HOST%%]*}"
[[ ${#colons} -eq 1 ]] && NOPROXY_HOST="${NOPROXY_HOST%%:*}"

# ----------------------------------------------------------------------------
# 2. Redfish helpers
# ----------------------------------------------------------------------------
AUTH_TOKEN=""
SESSION_URI=""
AUTH_MODE="basic"

# Emits a curl config snippet with the credentials. Read by curl through a
# process-substitution fd (-K), so neither the password nor the session token
# ever shows up in argv. printf is a shell builtin - no argv leak there either.
rf_auth_cfg() {
  if [[ -n "$AUTH_TOKEN" ]]; then
    printf 'header = "X-Auth-Token: %s"\n' "$AUTH_TOKEN"
  else
    local up="${BMC_USER}:${BMC_PASS}"
    up=${up//\\/\\\\}
    up=${up//\"/\\\"}
    printf 'user = "%s"\n' "$up"
  fi
}

# --noproxy: management-network traffic must go straight to the BMC, not via
# whatever corporate HTTPS_PROXY the diag workstation has configured.
rf_curl() {
  curl -s --noproxy "$NOPROXY_HOST" --connect-timeout 5 --max-time "$RF_TIMEOUT" \
       "${TLS_OPTS[@]}" -K <(rf_auth_cfg) "$@"
}

# HTTP status only ("000" = no connection).
rf_code() {
  rf_curl -o /dev/null -w '%{http_code}' "${BMC_BASE}$1" 2>/dev/null
}

# GET a URI; prints the JSON body, returns non-zero on transport error or non-2xx.
rf_get() {
  local uri="$1" out code body f
  out=$(rf_curl -w '\n%{http_code}' "${BMC_BASE}${uri}" 2>/dev/null) || return 1
  code=${out##*$'\n'}
  body=${out%$'\n'*}
  [[ "$code" == 2?? ]] || return 1
  if [[ -n "$DUMP_DIR" ]]; then
    f="${uri#/}"; f="${f//\//_}"; f="${f//\?/_}"
    printf '%s\n' "$body" > "${DUMP_DIR}/${f:-root}.json"
  fi
  printf '%s' "$body"
}

# Create a Redfish session. Body is built by jq from env vars (not argv) and
# fed to curl on stdin.
rf_login() {
  local hdrs loc
  hdrs=$(RF_U="$BMC_USER" RF_P="$BMC_PASS" jq -nc '{UserName: env.RF_U, Password: env.RF_P}' \
    | curl -s --noproxy "$NOPROXY_HOST" --connect-timeout 5 --max-time "$RF_TIMEOUT" \
           "${TLS_OPTS[@]}" -o /dev/null -D - \
           -H 'Content-Type: application/json' --data-binary @- \
           "${BMC_BASE}/redfish/v1/SessionService/Sessions" 2>/dev/null) || return 1
  hdrs=$(printf '%s\n' "$hdrs" | tr -d '\r')
  AUTH_TOKEN=$(printf '%s\n' "$hdrs" | awk -F': *' 'tolower($1)=="x-auth-token"{print $2; exit}')
  loc=$(printf '%s\n' "$hdrs" | awk -F': *' 'tolower($1)=="location"{print $2; exit}')
  [[ "$loc" == *://* ]] && loc="/${loc#*://*/}"
  SESSION_URI="$loc"
  [[ -n "$AUTH_TOKEN" ]]
}

# Delete our session on any exit - OpenBMC has a small fixed number of
# session slots, and a rack-wide loop would otherwise leave one behind per run.
rf_logout() {
  if [[ -n "$AUTH_TOKEN" && -n "$SESSION_URI" ]]; then
    rf_curl -o /dev/null -X DELETE "${BMC_BASE}${SESSION_URI}" 2>/dev/null
  fi
  return 0
}
trap rf_logout EXIT

# jq field helper: jget "$json" '.Path.To.Field'
jget() {
  jq -r "($2) // empty" 2>/dev/null <<< "$1" | head -n1 | tr -d '\r'
}

members() {
  jq -r '.Members[]?."@odata.id" // empty' 2>/dev/null <<< "$1"
}

# Seconds since epoch for an ISO-8601 Redfish DateTime; empty if unparseable.
to_epoch() {
  local dt="$1"
  date -u -d "$dt" +%s 2>/dev/null && return 0
  # macOS/BSD date: only safe when the BMC reports UTC.
  case "$dt" in
    *Z|*+00:00) date -u -j -f '%Y-%m-%dT%H:%M:%S' "${dt:0:19}" +%s 2>/dev/null ;;
  esac
}

# ----------------------------------------------------------------------------
# 3. Row helpers (same OK / CHECK / MISSING / N/A semantics as the in-band
#    script; "##" rows are section headers for the final table)
# ----------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

declare -a ROWS=()

add_row() {
  local v="${2:--}"
  ROWS+=("${1}|${v//|//}|${3}")
}

section() { ROWS+=("##|$1|"); }

note_na() { add_row "$1" "$2" "N/A"; }

# Exact match on purpose (not substring) - see in-band v0.4.10, where
# "inactive" substring-matched "active".
rf_check() {
  local name="$1" val="$2" expected="${3:-}"
  if [[ -z "$val" ]]; then
    add_row "$name" "-" "MISSING"
  elif [[ -n "$expected" && "$val" != "$expected" ]]; then
    add_row "$name" "${val} (expected ${expected} per GA §0a)" "CHECK"
  else
    add_row "$name" "$val" "OK"
  fi
}

health_row() {
  local name="$1" health="$2" extra="${3:-}"
  local val="${health:-not reported}${extra:+ ${extra}}"
  case "$health" in
    OK) add_row "$name" "$val" "OK" ;;
    "") add_row "$name" "$val" "N/A" ;;
    *)  add_row "$name" "$val" "CHECK" ;;
  esac
}

print_row() {
  local name="$1" val="$2" status="$3" color
  case "$status" in
    OK)      color="$GREEN" ;;
    MISSING) color="$RED" ;;
    N/A)     color="$BLUE" ;;
    *)       color="$YELLOW" ;;
  esac
  printf " %-34s : %-44s [${color}%s${NC}]\n" "$name" "$val" "$status"
}

# ----------------------------------------------------------------------------
# 4. Connect: reachability -> session -> auth probe. Fail fast with a reason.
# ----------------------------------------------------------------------------
echo "Connecting to BMC ${BMC_HOST} ..." >&2

root_code=$(rf_code /redfish/v1)
if [[ "$root_code" == "000" ]]; then
  echo "ERROR: no HTTPS response from ${BMC_HOST} (timeout / refused / TLS failure)." >&2
  echo "       Check the address, that this workstation can route to the BMC" >&2
  echo "       management network, and (if using -C) the CA file." >&2
  exit 2
fi
root_json=$(rf_get /redfish/v1) || {
  echo "ERROR: ${BMC_HOST} answered HTTP ${root_code} on /redfish/v1 - not a Redfish service?" >&2
  exit 2
}

if rf_login; then
  AUTH_MODE="session"
else
  AUTH_TOKEN=""; SESSION_URI=""; AUTH_MODE="basic"
fi

auth_code=$(rf_code /redfish/v1/Managers)
case "$auth_code" in
  2??) ;;
  401|403)
    echo "ERROR: Redfish authentication failed for user '${BMC_USER}' (HTTP ${auth_code})." >&2
    echo "       Set the right password:  export BMC_PASS='...'  (and -u / BMC_USER if not root)." >&2
    exit 2 ;;
  *)
    echo "ERROR: unexpected HTTP ${auth_code} from /redfish/v1/Managers." >&2
    exit 2 ;;
esac

# ----------------------------------------------------------------------------
# 5. Redfish service identity
# ----------------------------------------------------------------------------
section "Redfish Service"
add_row "BMC Endpoint" "${BMC_HOST} (auth: ${AUTH_MODE})" "OK"
rf_check "Redfish Version" "$(jget "$root_json" '.RedfishVersion')"
rf_vendor="$(jget "$root_json" '.Vendor') $(jget "$root_json" '.Product')"
rf_vendor="${rf_vendor# }"; rf_vendor="${rf_vendor% }"
if [[ -n "$rf_vendor" ]]; then
  add_row "Redfish Vendor/Product" "$rf_vendor" "OK"
else
  note_na "Redfish Vendor/Product" "not reported by service root"
fi
rf_check "Service UUID" "$(jget "$root_json" '.UUID')"

# ----------------------------------------------------------------------------
# 6. Managers (BMC_0, HGX_BMC_0/HMC, ...)
# ----------------------------------------------------------------------------
section "Managers (BMC / HMC)"
mgr_coll=$(rf_get /redfish/v1/Managers)
mgr_uris=$(members "$mgr_coll")
if [[ -z "$mgr_uris" ]]; then
  add_row "Managers" "-" "MISSING"
else
  local_now=$(date -u +%s)
  while IFS= read -r uri; do
    [[ -z "$uri" ]] && continue
    m=$(rf_get "$uri") || { add_row "Manager ${uri##*/}" "GET failed" "MISSING"; continue; }
    id=$(jget "$m" '.Id'); id="${id:-${uri##*/}}"

    # FW is informational here; the GA-target comparison for HGX_BMC is done
    # once, on the FirmwareInventory HGX_FW_BMC_* entry below.
    rf_check "Manager ${id} FW" "$(jget "$m" '.FirmwareVersion')"

    mtype=$(jget "$m" '.ManagerType'); model=$(jget "$m" '.Model')
    if [[ -n "$mtype$model" ]]; then
      add_row "Manager ${id} Type/Model" "${mtype}${model:+ / ${model}}" "OK"
    fi

    health_row "Manager ${id} Health" "$(jget "$m" '.Status.Health')" \
      "$( s=$(jget "$m" '.Status.State'); [[ -n "$s" ]] && echo "($s)" )"

    dt=$(jget "$m" '.DateTime')
    if [[ -n "$dt" ]]; then
      bmc_epoch=$(to_epoch "$dt")
      if [[ -n "$bmc_epoch" ]]; then
        drift=$(( bmc_epoch - local_now ))
        adrift=${drift#-}
        if (( adrift > CLOCK_DRIFT_MAX )); then
          add_row "Manager ${id} Clock" "${dt} (drift ${drift}s vs diag host - SEL timestamps off)" "CHECK"
        else
          add_row "Manager ${id} Clock" "${dt} (drift ${drift}s)" "OK"
        fi
      else
        add_row "Manager ${id} Clock" "${dt} (drift not computed on this OS)" "OK"
      fi
    fi

    # BMC network identity - handy for matching a tray to its switch port.
    eth_coll_uri=$(jget "$m" '.EthernetInterfaces."@odata.id"')
    if [[ -n "$eth_coll_uri" ]]; then
      eth_coll=$(rf_get "$eth_coll_uri")
      while IFS= read -r euri; do
        [[ -z "$euri" ]] && continue
        e=$(rf_get "$euri") || continue
        eid=$(jget "$e" '.Id'); eid="${eid:-${euri##*/}}"
        mac=$(jget "$e" '.MACAddress')
        ips=$(jq -r '[.IPv4Addresses[]?.Address // empty] | join(",")' 2>/dev/null <<< "$e")
        [[ -z "$mac$ips" ]] && continue
        add_row "Manager ${id} NIC ${eid}" "${mac:--}${ips:+ ${ips}}" "OK"
      done <<< "$(members "$eth_coll")"
    fi
  done <<< "$mgr_uris"
fi

# ----------------------------------------------------------------------------
# 7. Systems - BIOS / identity / power (replaces in-band dmidecode rows),
#    plus GPU VBIOS via Processors (replaces in-band nvidia-smi row,
#    best-effort: depends on the BMC exposing Processor.FirmwareVersion).
# ----------------------------------------------------------------------------
section "Systems (Host / HGX)"
sys_coll=$(rf_get /redfish/v1/Systems)
sys_uris=$(members "$sys_coll")
gpu_list=""
if [[ -z "$sys_uris" ]]; then
  add_row "Systems" "-" "MISSING"
else
  while IFS= read -r uri; do
    [[ -z "$uri" ]] && continue
    s=$(rf_get "$uri") || { add_row "System ${uri##*/}" "GET failed" "MISSING"; continue; }
    id=$(jget "$s" '.Id'); id="${id:-${uri##*/}}"

    mfg=$(jget "$s" '.Manufacturer'); model=$(jget "$s" '.Model')
    [[ -n "$mfg$model" ]] && add_row "System ${id} Model" "${mfg}${mfg:+ }${model}" "OK"
    sn=$(jget "$s" '.SerialNumber')
    [[ -n "$sn" ]] && add_row "System ${id} Serial" "$sn" "OK"
    bios=$(jget "$s" '.BiosVersion')
    [[ -n "$bios" ]] && add_row "System ${id} BIOS" "$bios" "OK"

    pstate=$(jget "$s" '.PowerState')
    health_row "System ${id} Health" "$(jget "$s" '.Status.Health')" "${pstate:+(power ${pstate})}"

    cpus=$(jget "$s" '.ProcessorSummary.Count'); mem=$(jget "$s" '.MemorySummary.TotalSystemMemoryGiB')
    if [[ -n "$cpus$mem" ]]; then
      add_row "System ${id} CPU/Mem" "${cpus:-?} CPU, ${mem:-?} GiB" "OK"
    fi

    proc_coll_uri=$(jget "$s" '.Processors."@odata.id"')
    if [[ -n "$proc_coll_uri" ]]; then
      proc_coll=$(rf_get "$proc_coll_uri")
      while IFS= read -r puri; do
        [[ -z "$puri" ]] && continue
        p=$(rf_get "$puri") || continue
        [[ "$(jget "$p" '.ProcessorType')" == "GPU" ]] || continue
        pid=$(jget "$p" '.Id'); pid="${pid:-${puri##*/}}"
        pfw=$(jget "$p" '.FirmwareVersion')
        gpu_list+="${id}/${pid} ${pfw}"$'\n'
      done <<< "$(members "$proc_coll")"
    fi
  done <<< "$sys_uris"
fi

# One row if every GPU agrees (the normal case), per-GPU rows if they differ.
if [[ -z "$gpu_list" ]]; then
  note_na "GPU VBIOS" "no GPU Processors exposed via Redfish - use nvidia-smi in-band"
else
  gpu_n=$(printf '%s' "$gpu_list" | grep -c .)
  gpu_fws=$(printf '%s' "$gpu_list" | awk '{print $2}' | sort -u)
  if [[ -z "$gpu_fws" ]]; then
    note_na "GPU VBIOS (${gpu_n} GPUs)" "BMC lists GPUs but no FirmwareVersion - use nvidia-smi in-band"
  elif [[ "$(printf '%s\n' "$gpu_fws" | grep -c .)" -eq 1 ]]; then
    rf_check "GPU VBIOS (${gpu_n} GPUs)" "$gpu_fws" "$EXPECTED_VBIOS"
  else
    while read -r gname gfw; do
      [[ -z "$gname" ]] && continue
      rf_check "GPU VBIOS ${gname}" "$gfw" "$EXPECTED_VBIOS"
    done <<< "$gpu_list"
  fi
fi

# ----------------------------------------------------------------------------
# 8. Chassis - tray identity + health roll-up. A GB300 tray exposes many
#    chassis (one per GPU/ERoT/etc.), so only the enclosure-level one(s) get
#    identity rows; everything else is summarized as healthy / not healthy.
# ----------------------------------------------------------------------------
section "Chassis"
ch_coll=$(rf_get /redfish/v1/Chassis)
ch_uris=$(members "$ch_coll")
if [[ -z "$ch_uris" ]]; then
  add_row "Chassis" "-" "MISSING"
else
  ch_total=0; ch_bad=""
  while IFS= read -r uri; do
    [[ -z "$uri" ]] && continue
    c=$(rf_get "$uri") || continue
    ch_total=$((ch_total + 1))
    cid=$(jget "$c" '.Id'); cid="${cid:-${uri##*/}}"
    ctype=$(jget "$c" '.ChassisType')
    case "$ctype" in
      RackMount|Enclosure|Sled|StandAlone|Blade)
        cmodel=$(jget "$c" '.Model'); csn=$(jget "$c" '.SerialNumber'); cpn=$(jget "$c" '.PartNumber')
        add_row "Chassis ${cid}" "${cmodel:--} SN ${csn:--} PN ${cpn:--}" "OK" ;;
    esac
    chealth=$(jget "$c" '.Status.Health')
    if [[ -n "$chealth" && "$chealth" != "OK" ]]; then
      ch_bad+="${cid}=${chealth} "
    fi
  done <<< "$ch_uris"
  if [[ -z "$ch_bad" ]]; then
    add_row "Chassis Health (${ch_total})" "no Warning/Critical" "OK"
  else
    add_row "Chassis Health (${ch_total})" "${ch_bad% }" "CHECK"
  fi
fi

# ----------------------------------------------------------------------------
# 9. FirmwareInventory - same logic as in-band §6b (v0.4.15 two-step GET,
#    v0.4.28 HGX_FW_-anchored matching). See gb300_l10_sw_checklist.sh for
#    the full reasoning behind each pattern.
# ----------------------------------------------------------------------------
section "Firmware Inventory"
fw_coll=$(rf_get /redfish/v1/UpdateService/FirmwareInventory)
fw_all=$(members "$fw_coll")
if [[ -z "$fw_all" ]]; then
  add_row "FirmwareInventory" "query failed / empty" "MISSING"
else
  if [[ "$SHOW_ALL" -eq 1 ]]; then
    fw_uris="$fw_all"
  else
    fw_uris=$(printf '%s\n' "$fw_all" | grep -iE 'CPLD|EROT|HMC|BMC|FPGA|SMA')
  fi
  fw_total=$(printf '%s\n' "$fw_all" | grep -c .)
  fw_sel=$(printf '%s\n' "$fw_uris" | grep -c .)
  if [[ "$SHOW_ALL" -eq 1 ]]; then
    add_row "FirmwareInventory" "${fw_total} components (all shown)" "OK"
  else
    add_row "FirmwareInventory" "${fw_total} components (${fw_sel} shown, -a for all)" "OK"
  fi

  while IFS= read -r uri; do
    [[ -z "$uri" ]] && continue
    comp_json=$(rf_get "$uri") || { add_row "FW: ${uri##*/}" "GET failed" "MISSING"; continue; }
    comp_id=$(jget "$comp_json" '.Id'); comp_id="${comp_id:-${uri##*/}}"
    comp_ver=$(jget "$comp_json" '.Version')
    [[ -z "$comp_ver" ]] && continue
    # Order matters: ERoT before BMC ("HGX_FW_ERoT_BMC_0"). Bare FW_BMC_0 and
    # FW_E1S_CPLD_* deliberately have no target (different parts/versioning).
    comp_expected=""
    case "$comp_id" in
      HGX_FW_ERoT_*) comp_expected="$EXPECTED_HGX_EROT_FW" ;;
      HGX_FW_CPLD_*) comp_expected="$EXPECTED_HGX_CPLD_FW" ;;
      HGX_FW_FPGA_*) comp_expected="$EXPECTED_HGX_FPGA_FW" ;;
      HGX_FW_SMA_*)  comp_expected="$EXPECTED_MCU_SMA_FW" ;;
      HGX_FW_BMC_*)  comp_expected="$EXPECTED_HGX_BMC_FW" ;;
    esac
    rf_check "FW: ${comp_id}" "$comp_ver" "$comp_expected"
  done <<< "$fw_uris"
fi

# ----------------------------------------------------------------------------
# 10. Print summary table
# ----------------------------------------------------------------------------
TITLE="GB300 NVL L10 BMC REDFISH (REMOTE)  v${SCRIPT_VERSION}  ${BMC_HOST}  ($(date '+%Y-%m-%d %H:%M:%S'))"

echo
echo -e "${BOLD}==========================================================================================${NC}"
echo -e "${BOLD} ${TITLE}${NC}"
echo -e "${BOLD}==========================================================================================${NC}"

pass=0; fail=0; check_n=0; na=0
for row in "${ROWS[@]}"; do
  IFS='|' read -r name val status <<< "$row"
  if [[ "$name" == "##" ]]; then
    echo; echo -e "${BOLD}== ${val} ==${NC}"; continue
  fi
  print_row "$name" "$val" "$status"
  case "$status" in
    OK) pass=$((pass + 1)) ;;
    MISSING) fail=$((fail + 1)) ;;
    N/A) na=$((na + 1)) ;;
    *) check_n=$((check_n + 1)) ;;
  esac
done

echo -e "${BOLD}------------------------------------------------------------------------------------------${NC}"
echo -e " Summary: ${GREEN}${pass} OK${NC} | ${YELLOW}${check_n} NEEDS REVIEW${NC} | ${RED}${fail} MISSING${NC} | ${BLUE}${na} N/A${NC}"
echo -e "${BOLD}==========================================================================================${NC}"
[[ -n "$DUMP_DIR" ]] && echo "Raw Redfish JSON saved under: $DUMP_DIR"

# ----------------------------------------------------------------------------
# 11. Optional: plain-text logfile (no color codes)
# ----------------------------------------------------------------------------
if [[ -n "$LOGFILE" ]]; then
  {
    echo "$TITLE"
    echo "=========================================================================================="
    for row in "${ROWS[@]}"; do
      IFS='|' read -r name val status <<< "$row"
      if [[ "$name" == "##" ]]; then
        echo; echo "== ${val} =="; continue
      fi
      printf " %-34s : %-44s [%s]\n" "$name" "$val" "$status"
    done
    echo "------------------------------------------------------------------------------------------"
    echo "Summary: ${pass} OK | ${check_n} NEEDS REVIEW | ${fail} MISSING | ${na} N/A"
  } > "$LOGFILE"
  echo
  echo "Log written to: $LOGFILE"
fi

exit 0
