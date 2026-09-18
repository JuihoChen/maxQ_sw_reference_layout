# SOP: BCM Rack Provisioning — GB300 NVL L10

**Scope:** one rack (18 nodes) per pass — build image, provision, verify.
**Owner:** [assign engineering contact]
**Full rationale/evidence for every step:** see `session-summary.md` (§6, §8, §9).
**Node-range provisioning tool:** `pxe_rack_provision.sh` (supports `--rack N --node M-K` for staged rollout).

Replace `<image-name>`, `<category-name>`, `<source-archive>` throughout. Run on the BCM head node unless noted. Image build takes up to ~8.5 hrs — expected, do not interrupt.

**⚠️ STOP points — do not proceed without current engineering sign-off:**
- Which `--dgx-type` (`dgx_gb200` vs `dgx_gb300`) is correct for this hardware — not NV-confirmed.
- Whether `--no-cm-cuda-repo` is correct for **this specific archive** — confirmed only for `maxQ20GA-1032-doca341`.

---

## 1. Build the Image

```bash
# 1.1 Teardown prior attempt (skip if first build)
cmsh -c "softwareimage; remove <image-name>; commit"
rm -rf /cm/images/<image-name>

# 1.2 Build
cm-create-image -a /root/pre-built-images/<source-archive>.tgz \
  -n <image-name> --dgx-type dgx_gb300 -s --no-cm-cuda-repo
```

```bash
# 1.3 Verify driver stack
cm-chroot-sw-img /cm/images/<image-name>
dkms status
dpkg -l | grep -iE "nvidia|doca-host|mlnx-ofed"
ls -la /etc/systemd/system/nvidia-fabricmanager.service   # expect -> /dev/null
dpkg -l | grep -i "cuda-dcgm "                             # if missing, run 1.3a
exit
```

**1.3a — if `cuda-dcgm` (not just `cuda-dcgm-libs`) is missing, install it** (confirmed required on `maxQ20GA`/DOCA-3.4.1 archives — do NOT install `cuda-dcgm-nvvs` alongside it, it's ~1.2GB and not needed for health checks):
```bash
cm-chroot-sw-img /cm/images/<image-name>
chmod 1777 /tmp && rm -rf /tmp/*
apt-get install -y cuda-dcgm
exit
```

```bash
# 1.4 Mount cleanup — run after EVERY cm-chroot-sw-img session
umount -l /cm/images/<image-name>/sys/firmware/efi/efivars 2>/dev/null
umount -l /cm/images/<image-name>/var/tmp/* 2>/dev/null
for m in dev/pts dev proc sys run/systemd/resolve/resolv.conf run; do
  umount -l "/cm/images/<image-name>/$m" 2>/dev/null
done
grep "/cm/images/<image-name>/" /proc/mounts   # must be empty
```

**Only if a fix was applied inside a chroot session** (see `session-summary.md` §6/§9 for known fixes), run mount cleanup, then re-commit before re-verifying:
```bash
cm-create-image -d /cm/images/<image-name> -n <image-name> -s --no-cm-cuda-repo
```

---

## 2. Pre-Provisioning Checks

```bash
# 2.0 Create category — clone an existing known-good category if one exists (preferred):
cmsh
% category
% clone <source-category> <category-name>
% commit
% category use <category-name>
% set softwareimage <image-name>       # cloning does NOT update this — always set it explicitly
% commit
```
If no suitable category exists yet to clone, create one blank instead:
```bash
cmsh
% category
% add <category-name>
% commit
```

```bash
# 2.1 Config directories
cm-chroot-sw-img /cm/images/<image-name>
ls -la /etc/network/interfaces.d/ /etc/ntpsec/
exit
# if either missing:
mkdir -p /cm/images/<image-name>/etc/network/interfaces.d
mkdir -p /cm/images/<image-name>/etc/ntpsec

# 2.2 Disk setup
cmsh -c "category use <category-name>; get disksetup"
# if empty, set via cmsh (layout in session-summary.md §8.10) then commit

# 2.3 Hostname finalize script
cmsh -c "category use <category-name>; get finalizescript"
# expect finalize-hosts-127-v3.sh — if not set:
cmsh -c "category use <category-name>; set finalizescript finalize-hosts-127-v3.sh; commit"

# 2.4 Suppress known false-positive service monitor (mst)
# mst is never a real systemd service on this fleet (confirmed fleet-wide) —
# this stops CMDaemon flagging health check failures for it.
cmsh
% category use <category-name>
% services
% add mst
% commit
```

---

## 3. Assign and Provision

```bash
cmsh -c "category use <category-name>; set softwareimage <image-name>; commit"
```
1. Assign the 18 nodes to the category.
2. Set installmode `FULL`, reboot nodes (PXE/IPMI).
3. Watch status in `cmsh`/Base View.
4. Run L11 partnerdiag once all 18 are up.

**Staged rollout (recommended for a new archive):**
1. Provision node01 alone first, verify Section 4 checks pass clean.
2. If node01 was assigned the `provisioning` role (to serve the rest of the rack), run this **before** rebooting the other 17 — required, not optional:
   ```bash
   cmsh -c "softwareimage; updateprovisioners <image-name>"
   ```
   Without this, CMDaemon does not recognize node01 as having an up-to-date image (its own client FULL install does not count), and all 17 remaining requests silently fall through to the head node's own default provisioning role — capped at 10 concurrent slots, causing ~half the rack to queue and take 3.5-4x longer. Confirm the log shows `Provisioning completed: sent ... to <node>:...` — if it says nothing to send, node01 was already current.
3. Bring up the rest with `pxe_rack_provision.sh --rack <N> --node 2-18` (supports single node or a range — see script's own `--help`).

Any error not covered here → pull the exact log line, escalate. Don't guess.

---

## 4. Post-Provisioning Verification

Sample multiple nodes, not just one:
```bash
cm-chroot-sw-img /cm/images/<image-name>
dpkg -l | grep -E "^[hi]i.*linux-(image|modules|headers)"
ls -la /boot/vmlinuz* /boot/initrd*
dkms status
ls -la /etc/systemd/system/nvidia-fabricmanager.service
ls -la /etc/network/interfaces.d/ /etc/ntpsec/
dpkg -l | grep -i -E "^ii\s+(ntp|chrony)"
systemctl is-enabled chrony
systemctl is-enabled systemd-timesyncd
exit
cmsh -c "softwareimage; list"
```
Ignore the image's own `grub.cfg` — never used; BCM regenerates boot config per-node.

---

## 5. Known Issues (escalate, do not fix ad hoc)

| Symptom | Status |
|---|---|
| `ntp` health check FAILs, or chrony syncs off public internet NTP | Chrony install works, but internal time-source address was never assigned — escalate before pointing at a real internal server. |
| `ldap` health check PASS but `nslcd` log shows `Can't contact LDAP server` | Inconsistent signal — confirm `cmsupport` is genuinely LDAP-backed (not a local `/etc/passwd` fallback) before trusting `ldap: PASS`. |
| `/swap.img` bloats image ~8GB | Known, cosmetic/storage only. |

## 6. Known-Acceptable (do not re-investigate)

| Symptom | Verdict |
|---|---|
| Long stall on "Installing CM packages" | Expected, not a hang. |
| `uname -r` wrong inside chroot | Shows head node's kernel — ignore. |
| `bind9`/`slapd` disable error | Harmless, non-fatal. |
| `nvidia-fabricmanager` version mismatch, or `xpmem` package version string showing wrong kernel | Cosmetic metadata only — trust `dkms status`. |
| Extra files in provisioned node's `/home` | Expected, non-full installs skip `/home`. |
| `gpu_health_nvlink`/`gpu_health_overall` FAIL right after provisioning | Expected until rack NVSwitch GFM is configured. |
| "already mounted" from `cm-chroot-sw-img` | Run Section 1.3, then retry. |
| `mst died`/`not restarted` in event log | Fleet-wide, pre-existing — no real `mst.service` has ever existed on any rack. Suppress via 2.4, don't chase it further. |
| `cuda-dcgm died`/crash loop right after fresh provisioning | Check if it clears within ~1-2 min on its own (stale health-check snapshot mid-startup) before assuming it's a real failure — confirm with a fresh `device latesthealthdata <node>` read. |
| Freshly-reinstalled node's SSH host key mismatch warning | Expected — every reinstall regenerates host keys. `ssh-keygen -R <hostname>` before first connect. |

---

## 7. Escalation

Anything not covered, or an unresolved ⚠️ STOP point → contact engineering before continuing. A wrong guess here goes onto 18 nodes at once.
