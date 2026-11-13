# SOP: BCM Rack Provisioning — GB300 NVL L10

**Scope:** one rack (18 nodes) per pass — build image, provision, verify.
**Owner:** [assign engineering contact]
**Full rationale/evidence for every step:** see `session-summary.md` (§6, §8, §9, §11), or the same content by topic in the Engineering Manual.
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

# 2.3 Finalize script (one combined script per category)
cmsh -c "category use <category-name>; get finalizescript"
# expect finalize-hosts-127-v7.sh — if not set:
cmsh -c "category use <category-name>; set finalizescript finalize-hosts-127-v7.sh; commit"
#   Part 1  127.0.1.1 <hostname> in /etc/hosts            (was v3)
#   Part 2  LDAP detach + local cmsupport + service masks (v4) - nodes come up with
#           nsswitch 'files' and a local cmsupport BY DESIGN (not the old 8.8 regression)
#   Part 3  link-watch: provisioning NIC plugged in after boot gets its address and
#           the node reconnects to BCM on its own (v5-v7)
# Use v3 instead only for a category that must NOT be LDAP-detached - ask engineering.
# Never run the finalize script by hand on a live node - it applies all three parts.

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
2. Set installmode `FULL`, reboot nodes (PXE/IPMI). `FULL` is for bring-up only — see step 5.
3. Watch status in `cmsh`/Base View.
4. Run L11 partnerdiag once all 18 are up.
5. **Once Section 4 verification has passed, reset the category off `FULL` before the rack is power-cycled again for any reason:**
   ```bash
   cmsh -c "category use <category-name>; set installmode AUTO; commit"   # or NOSYNC — agree which with engineering
   cmsh -c "category use <category-name>; get installmode"
   ```
   Left at `FULL`, every reboot or AC power event with the cable connected wipes and reinstalls the node (Section 6). **Do not unplug the provisioning cable as a workaround** — reset `installmode` instead. This is a category commit: if a diag campaign is running on these nodes, re-run `./rack_lifecycle.sh pre-diag --rack <N>` afterwards.

### Peer-Provisioning (optional, recommended for a full 18-node rollout)

**What this is:** normally every node pulls its image from the head node directly. If you bring up 18 nodes at once, they compete for the same head-node bandwidth and slots — roughly half the rack ends up waiting, taking 3-4x longer than it needs to. Peer-provisioning designates one already-provisioned node in the rack as a second source, so the head node and that node can each serve nodes at the same time. **Confirmed working**, validated end-to-end on a real 18-node rollout — a rack that took ~2h20m without this took ~1h in an identical retest with it.

**How to set it up — do this in order, before bringing up the rest of the rack:**

1. **Provision node01 by itself first** (`pxe_rack_provision.sh --rack <N> --node 1`). Wait for it to finish and confirm it's healthy (Section 4 checks).

2. **Assign it the `provisioning` role**, scoped to this rack's image and category:
   ```bash
   cmsh
   % device use <rack>node01
   % roles
   % assign provisioning
   % set localimages <image-name>
   % set categories <category-name>
   % commit
   ```

3. **Run this — confirmed required, do not skip it:**
   ```bash
   cmsh -c "softwareimage; updateprovisioners <image-name>"
   ```
   **Why this matters:** the BCM admin manual documents that CMDaemon tracks which provisioning nodes have an "up-to-date" image, and that changing a provisioning role's settings auto-triggers this update — but it does *not* say whether a node's own normal client install (as opposed to a role-attribute change) satisfies that tracking. We tested it directly: it doesn't. A rack was set up with the role correctly assigned, the node finished its own install normally, and every other node's request still went to the head node alone — confirmed via logs, zero exceptions. Running `updateprovisioners` (bare, with no image name, run interactively) afterward genuinely pushed data and immediately reported `Provisioning completed: sent ...`, proving the node hadn't been considered current until then. A second rack, set up the same way, used this **image-scoped** form instead (`updateprovisioners <image-name>`, one-line) — it reports differently (`"...will be updated in the background"`, no immediate confirmation line) but was independently confirmed working afterward via the peering result itself. Either form works; they just report their result differently, so don't be thrown by which message you see.

   Skip this step entirely and every other node will silently fall back to the head node, with no error or warning. If you used the bare form and see `Provisioning completed: sent ... to <rack>node01:...`, that's your confirmation (if it says there's nothing to send, node01 was already current — fine, means this ran before with no changes since). If you used the image-scoped form and only get the "background" message, don't worry — confirm success the way described below instead (`lastprovisioningnode`), since this form doesn't report success synchronously.

4. **Bring up the rest of the rack** as usual:
   ```bash
   pxe_rack_provision.sh --rack <N> --node 2-18
   ```

**How to confirm it's actually working**, once nodes are mid-install:
```bash
cmsh -c "device use <rack>node05; lastprovisioningnode"
```
If this shows `<rack>node01` as the server, peering is working. If it shows the head node's hostname for every node you check, peering isn't active — go back and confirm step 3 actually ran and reported a real sync.

**What to expect, so you don't mistake normal behavior for a problem:**
- The split between the two sources won't be even (e.g. 9-vs-8, not 9-vs-9) — this is normal. Each node's request is assigned to whichever source is least busy *at that exact moment*, and both sources are capped at 10 concurrent transfers.
- **Once a node is assigned to a source, it stays there for the rest of that node's install — even if the other source finishes early and sits idle.** If node01 finishes serving its share in 20 minutes and the head node is still working through its share an hour later, that's expected, not a sign peering "stopped working." There's currently no way to move an already-running transfer to the idle source.
- A pending/queued node's `cmsh` status shows `"waiting for FULL provisioning to '/' to start"` — this is normal queuing, not a failure.

Full investigation history, evidence, and edge cases (why this was originally missed, what a broken vs. working setup looks like in the logs, further optimization ideas) are in `session-summary.md` §9p onward.

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

Then on **one provisioned node** (finalize v5+ only), confirm the cable watcher landed and stayed quiet:
```bash
sed -n 2p /usr/local/sbin/link-watch.sh       # names the finalize version that installed it (expect v7)
systemctl is-active link-watch                # active
journalctl -t link-watch -b --no-pager        # expect: -- No entries --  (normal boot, cable in)
```

---

## 5. Rack Handoff to Production Line

**When to run this:** once a rack has passed Section 4 verification and is leaving the BCM cluster network for good (going to the production/diag floor). **Run once per node.** Tool: `rack_lifecycle.sh` (same host it runs on doesn't matter — it SSHes to each target node to make the changes).

**⚠️ Handoff is ONE-WAY.** There is no rejoin/finalize path in the script. Once run on a node, that node does not go back to being BCM-managed on its own or via a reboot. Do not run this on a node you might need to bring back onto the cluster network later.

### 5.1 What handoff does

```bash
./rack_lifecycle.sh handoff --rack <N>
```
(also accepts `--category <name>`, `--ip-range <start> <end>`, or `--rackgroup <name>` — use `--rack <N>` for a normal whole-rack handoff; see the script's own header comment if targeting differently)

Per node, in order:
1. Comments out a stale DNS entry in `resolved.conf` (only if present) and restarts `systemd-resolved`.
2. Tries to preserve `cmsupport` as a **local** account before LDAP is cut off.
3. Stops and disables `nslcd` (the LDAP client daemon).
4. Strips `pam_ldap.so` out of the PAM stacks.
5. Sets `nsswitch.conf` (`passwd`/`group`/`netgroup`) to `files` only.
6. Automatically disables **CMDaemon's own monitoring** of `cuda-dcgm` for every targeted node (one `cmsh` call from the head node, not per-node) — see 5.3 for exactly what this does and doesn't do.

Run with `--dry-run` first if you want to see what it would do without changing anything.

### 5.2 ⚠️ Known bug — verify `cmsupport` yourself, every time

Step 2 above is supposed to keep the `cmsupport` account working locally after LDAP is cut. **On every node handed off so far (rack08), `cmsupport` has ended up missing entirely instead** — root cause not yet found. **Do not assume this step worked.** After running handoff, always check:
```bash
./rack_lifecycle.sh status --rack <N>          # or --ip-range / --rackgroup, matching what you used above
```
and look at the `cmsupport` line for each node. If it reports `no such user`, the account needs to be created manually on that node (`useradd -u 1000 -g 1000 -s /bin/bash -m cmsupport`, then set a password) before handing the node to whoever needs local login. Escalate the underlying bug per Section 7 — don't spend time root-causing it on the floor.

### 5.3 DCGM monitoring — what's disabled and what isn't

Handoff automatically disables CMDaemon's *awareness* of `cuda-dcgm` at the BCM level (`monitored no`, `autostart no`). This stops BCM from flagging health-check failures for it and from auto-restarting it if it's ever stopped.

**This does NOT stop the `cuda-dcgm` systemd service itself.** After handoff, `cuda-dcgm.service` is still running normally on the node — handoff only takes BCM's hands off it. If the node is also going straight into diag testing that needs the GPUs free of `cuda-dcgm` (it holds `/dev/nvidia*` open), that's a **separate, additional** step:
```bash
./rack_lifecycle.sh pre-diag --rack <N>        # stops AND disables cuda-dcgm.service itself
```
`pre-diag` is reversible afterward with `post-diag` (restores whatever state `pre-diag` recorded) — but only if someone actually runs `post-diag` later. If diag testing starts immediately after handoff, you can do both in one shot:
```bash
./rack_lifecycle.sh handoff --with-pre-diag --rack <N>
```
This will ask you to type `yes` to confirm (skipped only under `--dry-run`), because it compounds handoff's one-way permanence with a second change. **Only use `--with-pre-diag` when diag starts right away** — otherwise a node can sit off-cluster indefinitely with GPU monitoring off and nobody remembering to run `post-diag`.

If you skip `--with-pre-diag` and diag testing does not follow immediately, do nothing further — the node is fully handed off, `cuda-dcgm` keeps running normally, and that's the expected end state.

### 5.4 Verifying a handoff

```bash
./rack_lifecycle.sh status --rack <N>
```
Read-only, makes no changes. Confirms per node: DNS entry, `nslcd` state, `cmsupport` (see 5.2), `nsswitch.conf`, DCGM state, and the recorded handoff/pre-diag/post-diag history. Handoff is idempotent — safe to re-run `status` (or even `handoff` itself) if you're unsure whether it already ran on a given node.

Any error not covered here → pull the exact output, escalate. Don't guess — this step is one-way.

---

## 6. Known Issues (escalate, do not fix ad hoc)

| Symptom | Status |
|---|---|
| `ntp` health check FAILs, or chrony syncs off public internet NTP | Chrony install works, but internal time-source address was never assigned — escalate before pointing at a real internal server. |
| `ldap` health check PASS but `nslcd` log shows `Can't contact LDAP server` | Inconsistent signal — confirm `cmsupport` is genuinely LDAP-backed (not a local `/etc/passwd` fallback) before trusting `ldap: PASS`. |
| `cmsupport` missing after handoff | Known bug, not yet root-caused — see Section 5.2. Always verify with `status`, don't assume it worked. |
| `/swap.img` bloats image ~8GB | Known, cosmetic/storage only. |
| `cuda-dcgm` health check FAILs on `maxQ-1032-doca350` nodes even though `cuda-dcgm` monitoring is already `no`/`no` in `services` | The daemon isn't in the `baseos-1032-doca350` image, and finalize v4+ masks it anyway. The failing item is a separate health check, not service monitoring. Escalate — engineering decides whether to install `cuda-dcgm` (1.3a) or exclude the health check for the category. |
| Network boot tries a BlueField-3 port first (`UEFI PXEv4 (MAC:DC73…)` at the top of the boot menu) | Seen on `sn267548730002`. Boot-order / option-ROM change needs sign-off — escalate, don't change it on the floor. |
| A handed-off node is reinstalled | The node-installer rewrites `/etc/systemd/resolved.conf` on every install, so `handoff`'s DNS fix is lost. Re-run `handoff` (it is idempotent) or escalate. |
| BMC login is still the default `root` / `0penBmc` | Anyone on the BMC network can mount an ISO (virtual media) and boot a node from it. Security owner to decide — don't change BMC settings on the floor. |

**⚠️ Leftover category `installmode=FULL` reinstalls a whole rack on a plain power cycle — not just an explicit trigger. `pxelabel=localdrive` gives NO protection against this.** Confirmed 2026-09-30: a rack08 category still set to `installmode=FULL` from the original build pass (SOP §3) reinstalled 15/18 nodes from nothing more than a **plain AC power off/on** — no `pxe_rack_provision.sh` call, no manual PXE override, no explicit trigger of any kind. `pxelabel=localdrive` was set on every node at the time and made no difference at all. Check and verify:
```bash
cmsh -c "device foreach -g <group> (get installmode)"          # per-node override, if any
cmsh -c "category use <category-name>; get installmode"        # the real default most nodes inherit
```
**If a category shows `FULL` after Section 4 verification has passed, reset it** (to `AUTO`, `NOSYNC`, or whatever your intended steady-state behavior is) **before the rack is power-cycled again for any reason** — including a routine AC power event, not just a deliberate reinstall command. Do not treat `pxelabel=localdrive` as protection here; it has no observed effect on this behavior. See Engineering Manual §6.6 for the full investigation, including the earlier (wrong) `pxelabel`-based theory this superseded. **Recurred 2026-11-12 on `maxQ-1032-doca350`** — operators were unplugging the provisioning cable before reboots to avoid it. Don't: reset `installmode` (Section 3 step 5). Unplugging leaves the node without an address on older finalize versions (see Section 7).

## 7. Known-Acceptable (do not re-investigate)

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
| Provisioning cable plugged in after the node booted | Finalize v5+: `link-watch` runs `ifup` and restarts `cmd`; node is `UP` within ~15–45 s. Check `journalctl -t link-watch`. On a node **without** it: run `ifup enP5p9s0` then `systemctl restart cmd` on the node (from the BMC console). |
| Node `[ DOWN ], pingable` right after its cable was moved or re-plugged | Normal for up to ~30 s on v7 while `link-watch` restarts `cmd`. If it persists, check `journalctl -t link-watch`, then escalate. |
| `link-watch` logs `cmd restart pending ... 'master' not reachable` | Expected when the cable is on a non-BCM network (e.g. office); it restarts `cmd` once back on BCM. |
| Need to `ifdown` the provisioning NIC on purpose | Run `systemctl stop link-watch` first — otherwise it brings the NIC back up within ~15–30 s. |
| `/etc/netplan/50-cloud-init.yaml` on a node; `Dropped protocol specifier '.dhcp'` or `ifup: waiting for lock` in the journal | Harmless. Nodes use BCM's ifupdown config; the netplan file is inert. |
| `enx<MAC>` interface down with no IP; PXE/HTTP boot entries for that MAC | The BMC's virtual USB network link — not a real network. Don't pick those entries in the boot menu. |

---

## 8. Escalation

Anything not covered, or an unresolved ⚠️ STOP point → contact engineering before continuing. A wrong guess here goes onto 18 nodes at once.
