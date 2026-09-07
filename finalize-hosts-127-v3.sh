#!/bin/bash
#
# finalize-hosts-127-v3.sh
#
# Supersedes v1 (build log §8.9) and complements v2's systemd self-heal.
#
# ROOT CAUSE CONFIRMED (2026-09-02): per BCM's own shipped example script
# (/cm/local/apps/cmd/etc/htdocs/scripts/finalize/log_available_environment_variables.sh),
# "The root / of the running node is always mounted on /localdisk" during
# the finalize stage. v1 wrote to /etc/hosts, which at that point in the
# node-installer sequence is the ramdisk's own throwaway /etc/hosts, not
# the target node's persisted file - which is why the append never
# survived, confirmed directly in node-installer logs (the script ran and
# reported success, but the appended line was never present after boot).
#
# This version writes to /localdisk/etc/hosts instead - the correct path
# for the file that actually gets carried onto the booted node.
#
# Note: $CMD_HOSTNAME (if it exists - not yet confirmed against a real
# `env | grep CMD_` dump from this cluster) is tried first since it would
# be more directly authoritative than the ramdisk's own `hostname` output;
# falls back to `hostname` either way, matching v1's original behavior.
#
# Idempotent: safe to run again on a reinstall without duplicating the
# entry.

set -uo pipefail

HOSTS_FILE="/localdisk/etc/hosts"
NODE_HOSTNAME="${CMD_HOSTNAME:-$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)}"

if [[ -z "$NODE_HOSTNAME" ]]; then
  echo "finalize-hosts-127-v3: could not determine hostname (checked \$CMD_HOSTNAME and 'hostname') - skipping" >&2
  exit 0
fi

if [[ ! -f "$HOSTS_FILE" ]]; then
  echo "finalize-hosts-127-v3: ${HOSTS_FILE} does not exist at this stage - skipping" >&2
  exit 0
fi

if grep -qE "^127\.0\.1\.1[[:space:]]+${NODE_HOSTNAME}([[:space:]]|\$)" "$HOSTS_FILE" 2>/dev/null; then
  echo "finalize-hosts-127-v3: 127.0.1.1 ${NODE_HOSTNAME} already present - skipping"
else
  echo "127.0.1.1   ${NODE_HOSTNAME}" >> "$HOSTS_FILE"
  echo "finalize-hosts-127-v3: appended 127.0.1.1 ${NODE_HOSTNAME} to ${HOSTS_FILE}"
fi
