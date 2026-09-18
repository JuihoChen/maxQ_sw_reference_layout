# GB300 NVL L10 — Session Summary / Handoff Notes

**Date:** 2026-08-24 (updated — originally 2026-08-20)
**Scope:** 1.0.6 reference layout kernel upgrade, DOCA compatibility testing, field-upgrade staging, BCM provisioning prep

---

## 1. Current Validated State — `maxQ106`

| Item | Value | Status |
|---|---|---|
| Kernel | `6.17.0-1014-nvidia-64k` | ✅ Held, running, checklist-confirmed |
| Kernel packages held | `linux-image/modules/headers-6.17.0-1014-nvidia-64k` + `linux-nvidia-6.17-headers-6.17.0-1014` | ✅ All 4 confirmed `hi` in dpkg |
| `unattended-upgrades` | Disabled (service + timers + periodic config) | ✅ Confirmed inactive |
| DOCA | `3.2.1-044413` | ✅ DKMS clean, functional checks, cold power cycle survived, **real partnerdiag PASS** |
| DOCA 3.4.1 | Staged, not yet tested on maxQ106 | ⏸ **Open — see Section 4** |
| Root LV | Grown from 100GB → ~891GB (100% of VG, ext4 online resize) | ✅ Done — no LVM snapshot headroom left as a result |
| `mst` boot persistence | No native systemd service found; gap confirmed via cold power cycle | ⏸ Deprioritized — not required for partnerdiag/factory workflow (customer boots own OS) |
| `sw_checklist.sh` | Fixed — was checking hold status against wrong (generic HWE metapackage) package names, silently reporting `[MISSING]` on correctly-held exact-pinned kernels | ✅ Fixed, backup kept as `sw_checklist.sh.bak` |
| NVIDIA driver version in checklist | Shows `[CHECK]` consistently | ⏸ Not investigated — deferred per user, may be same "script targets wrong release" class of bug |
| BCM software image `baseos-1014-doca321` | Built from `maxQ106`'s validated `1014`+DOCA 3.2.1 state | ✅ Builds successfully under both `--dgx-type dgx_gb200` and `dgx_gb300` (see 6l/6m) — currently built under `gb300`; which is *correct* for real hardware still open with NV |

---

## 2. Key Findings This Session

### Kernel candidate testing (target: dual-compatible with DOCA 3.2.1 *and* 2.0.0-era DOCA)

| Kernel | DOCA 3.2.1 | DOCA 3.4.1 | Notes |
|---|---|---|---|
| `6.14.0-1015` | Previously validated (pre-session baseline) | Not tested | Documented in Table 11 as LTS floor for CX8; NOT the same as "6.8.0-1047" literal LTS build named in Table 11 — team's own already-passed validated kernel |
| `6.17.0-1014` | ✅ **Full validation incl. real partnerdiag PASS** | ⏸ **Not yet tested** | Originally flagged by NV as having a CPU stream-score bug — **later determined by team to be a false alarm / not customer-relevant**, since reference layout is factory/pass-criteria only; customer boots their own OS |
| `6.17.0-1016` | N/A | N/A | **Does not exist** in Ubuntu archive (`linux-signed-nvidia-6.17` pool jumps 1014→1018). Root cause of initial confusion — likely a mis-transcribed number from NV. |
| `6.17.0-1018` | ❌ Build failure | Not tested | `mlnx-ofed-kernel` (`25.10.OFED.25.10.1.7.1.409.1`) fails to compile against kernel's `net/tls.h` — signature mismatch on `tls_offload_rx_resync_async_request_end/start` (`struct sock *` vs `struct tls_offload_resync_async *`), `-Werror` makes it fatal |
| `6.17.0-1029` | ❌ Identical build failure to 1018 | ✅ Builds clean (DKMS-level only) | Confirms failure is DOCA-3.2.1/25.10-source-specific, not general to the 6.17 kernel line — 3.4.1 source already accounts for the newer `tls.h` signature |

**Conclusion:** `6.17.0-1014` is the only kernel build found that satisfies DOCA 3.2.1 (fully proven via partnerdiag). Whether it also satisfies DOCA 3.4.1 is the one major open question — see Section 4.

### Tooling bugs found and fixed
- `sw_checklist.sh` hold-detection logic (see Section 1)
- `doca-kernel-support` initially failed with cryptic "could not determine kernel version" — root cause was missing build toolchain (`gcc`, `dkms`, `make`, `build-essential`) on the fresh test box, not a real kernel-source problem. Once installed, the tool worked correctly and successfully surfaced the real `tls.h` incompatibility.
- partnerdiag CLI argument parsing failure — traced to smart-dash/smart-quote corruption from copy-pasting commands out of a Word document. **Any future partnerdiag commands sourced from Word docs/tickets/emails should be retyped, not pasted, or sanity-checked with `cat -A` first.**

---

## 3. Artifacts Staged (not installed) on `maxQ106`

Location: `/root/staging/2.0.0/`

| File | Purpose |
|---|---|
| `doca-host_3.4.1-010000-26.04-ubuntu2404_arm64.deb` | DOCA 3.4.1 repo-add package (2.0.0-era) |
| `NVIDIA-Linux-aarch64-580.173.02.run` | GPU driver, 2.0.0RC4 target version |
| `nvidia-imex-aarch64-580.173.02.run` | IMEX, matching driver version |
| `kernel-1029/` (4 `.deb`s + `notes.txt`) | Contingency kernel — confirmed compiles DOCA 3.4.1, confirmed **incompatible** with DOCA 3.2.1. Staged in case field-upgrade path ends up requiring a kernel bump alongside the DOCA bump. |

Backup discussed but **status of actual execution on maxQ106 was never confirmed during this session** — worth verifying whether an off-box tarball backup was actually taken before further changes, given LV is at 0 free space (no local snapshot option).

---

## 4. Open Items (priority order)

1. **`6.17.0-1014` + DOCA `3.4.1` compatibility — untested.** This is the one piece still needed to fully confirm `1014` as the dual-compatible field-upgrade kernel. DOCA 3.4.1 package already staged; next step is install + DKMS verification + real partnerdiag run, same rigor as the 3.2.1 validation.
2. **`--dgx-type dgx_gb200` vs `dgx_gb300` for the BCM image build — both confirmed to build successfully; correctness for real hardware still open.** See Section 6l/6m for the full evidence, including a host-level `/dev` incident that was initially mistaken for a `dgx_gb300`-specific defect. Blocks category/node assignment on `baseos-1014-doca321` until NV confirms which is correct for GB300 NVL hardware.
2. **NV escalation report** — drafted (see Section 5), needs updating with:
   - CPU stream-score reframed as "internally assessed as not customer-relevant" rather than a hard blocker, pending NV's own confirmation
   - `1014` + DOCA 3.4.1 result once tested
   - Still needs the four original open questions answered (1016 nonexistence, patched-source availability for 1018/1029, CPU-score fix timeline, long-term kernel target for 2.0.0 path)
   - **Not yet sent.**
3. **BCM provisioning of the rack (18× L10)** — image build ✅ done and verified reproducible (Section 6f/6g); category/node assignment and actual rack provisioning **not yet started**. See Section 6 "EXACT RESUME POINT."
4. **`l10-upgrade.sh` field script** — built, versioned, see Section 5. CONFIG block currently targets `1014` + DOCA `3.4.1`/driver `580.173.02` (2.0.0-era) for Step 2 — **will need adjustment once the 1014+3.4.1 test outcome and NV's response are known.**
5. **Cascade/orchestration layer for 144 nodes / 8 racks** — design discussed (canary-first rollout, centralized artifact staging, per-node idempotent agent + separate orchestrator), but **blocked on team's own topology discussion** (direct SSH vs. jump-host-per-rack vs. multi-hop through switches) and inventory format. Not yet built.

---

## 5. Deliverables Produced

- **`NV-kernel-doca-compat-report.md`** — escalation report draft for NV, covering the 1016 nonexistence finding and the 1018/1029 `tls.h` build failure. **Needs updating (see Open Item 2) before sending.**
- **`l10-upgrade.sh`** (current version: **0.1.1**) — single-node, 3-step gated/idempotent field upgrade script:
  - Step 1: kernel exact-pin swap, hold, DKMS verify (self-terminates on reboot; must be manually re-invoked with same command afterward — Option A, no auto-resume)
  - Step 2: DOCA + GPU driver + IMEX install, DKMS/functional verify
  - Step 3: BF3/CX8 firmware flash (requires full power cycle to activate, not just reboot; manual `--post-power-cycle-verify` re-invocation)
  - Config-driven (kernel/DOCA/driver versions all in one editable block, not hardcoded through the script)
  - Versioned (`SCRIPT_VERSION`, stamped into logs and `status.json`)
  - Firmware tool invocations (`bfup`, `mlxfwmanager`) are **unverified placeholders** — confirm against real `--help` output before trusting on hardware
  - Kept as single file (team preference over 3-file split)

---

## 6. BCM Provisioning — Image build: ✅ DONE (reproducible, clean run confirmed 2026-08-24). Node provisioning: not started.

**Goal:** Provision one rack (18× L10) via BCM with the validated `1014` + DOCA `3.2.1` reference layout, then run **L11** (rack/fabric-level) partnerdiag.

**Status as of 2026-08-24:** the `baseos-1014-doca321` software image has now been built successfully **from scratch, twice** — once via the incremental `-d` resume path (6a–6f below), and once via a full `cmsh remove` + `rm -rf` + fresh `-a <archive>` from-archive rebuild (6g) to validate the whole process is reproducible for the remaining 7 racks. Both runs hit the same known, already-fixed issues (fabricmanager finalize, see 6d) and no new issues except the mount-cleanup gotcha in 6h. The image-build portion of this section can now be treated as a stable runbook rather than active debugging — see 6g/6h for the from-archive procedure and the one new gotcha found.

**Key correction made this session:** BCM's documented image format is `.tar.gz`, **not** `.sqsh`/squashfs as originally assumed. Confirmed via NVIDIA's official BCM/BaseOS documentation.

**Confirmed BCM environment:**
- Head node ("N/B") is **x86_64**, BCM 11, managing an **aarch64** compute rack (mixed-architecture setup). GB300 image builds run under **QEMU user-mode emulation** (`cm-qemu-user-static`) — this is why some steps (package installs, DKMS builds) are dramatically slower than pure-file-I/O steps like archive unpack/validate.
- `cm-create-image -h` on this exact BCM 11 install confirms `--dgx-type` includes **`dgx_gb300`**, not just `dgx_gb200` (screenshot-confirmed). Still using `dgx_gb200` per NV's original verbal recommendation — discrepancy not resolved with NV, see open items.

**Phase A (base BCM platform bootstrap) — COMPLETE, confirmed via `cmsh -c "softwareimage; list"`:**
```bash
wget -c https://support2.brightcomputing.com/pre-built-images/11.25.08/aarch64/bcmn-ubuntu2404-11.0-rc.tar.gz
wget -c https://support2.brightcomputing.com/pre-built-images/11.25.08/aarch64/bcm-cm-shared-ubuntu2404-11.0-rc.tar.gz
wget -c https://support2.brightcomputing.com/pre-built-images/11.25.08/aarch64/bcni-ubuntu2404-11.0-rc.tar.gz
mkdir -p /cm/images/default-image-ubuntu2404-aarch64 /cm/shared-ubuntu2404-aarch64/ /cm/node-installer-ubuntu2404-aarch64
tar zxvf bcmn-ubuntu2404-11.0-rc.tar.gz -C /cm/images/default-image-ubuntu2404-aarch64
tar zxvf bcm-cm-shared-ubuntu2404-11.0-rc.tar.gz -C /cm/shared-ubuntu2404-aarch64/
tar zxvf bcni-ubuntu2404-11.0-rc.tar.gz -C /cm/node-installer-ubuntu2404-aarch64
cm-image --verbose create all --arch aarch64 --distro ubuntu2404 --add-only
cm-image --verbose create all --arch aarch64 --distro ubuntu2404 --add-archos
```
Confirmed result: `default-image-ubuntu2404-aarch64` registered, kernel `6.8.0-51-generic-64k`, category `default-ubuntu2404-aarch64` created, `0` nodes assigned (expected, nothing assigned yet). Unrelated pre-existing `default-image` (x86_64) shows `144` nodes — a **different, pre-existing fleet on this head node**, not related to the GB300 rack work.

### Phase B — capturing and importing `maxQ106` as a custom image. Multiple bugs hit and fixed in sequence:

**6a. tar capture bug — FIXED, archive confirmed good and already used successfully.**
Original command used absolute-path excludes (`--exclude=/proc`) with `-C / .`, which stores paths as relative (`./proc`) — excludes never matched, first archive pulled in live mutating `/proc`/`/sys`, corrupted, deleted. **Working, confirmed-good command (already run, archive exists and was used for the imports below):**
```bash
sudo mkdir -p /root/bcm-image-export
sudo tar --numeric-owner --xattrs --acls -czpf /root/bcm-image-export/maxQ106-1014-doca321-baseos.tgz \
  --exclude='./proc' --exclude='./sys' --exclude='./dev' --exclude='./run' \
  --exclude='./tmp' --exclude='./mnt' --exclude='./media' --exclude='./lost+found' \
  --exclude='./root/bcm-image-export' \
  -C / .
```
Verify (must return nothing): `tar -tzf ... | grep -E "^\./(sys|proc|dev|run)/" | head`

**6b. `cm-create-image` long-flag parsing bug — FIXED, use short flags.**
First command actually run (long-flag form):
```bash
cm-create-image --fromarchive maxQ106-1014-doca321-baseos.tgz \
  --dgx-type dgx_gb200 \
  --no-cm-cuda-repo \
  --name baseos-1014-doca321
```
This threw `error: argument positional: not allowed with argument -a/--fromarchive`. Fixed by switching to short flags: `-a <archive>`, `-n <name>` (same `--dgx-type`/`--no-cm-cuda-repo` long forms are fine, only `--fromarchive`/`--name` were the problem):
```bash
cm-create-image -a maxQ106-1014-doca321-baseos.tgz --dgx-type dgx_gb200 --no-cm-cuda-repo -n baseos-1014-doca321
```

**6c. Discovered `-s` flag — IMPORTANT, always use it for this use case.**
First real attempt (no `-s`) triggered BCM installing its own ~500-package default baseline on top of the already-complete imported tarball, including an irrelevant second kernel (`6.8.0-106-generic-64k`) and hours of DKMS rebuilding under QEMU. Confirmed via NVIDIA forum post: **`-s` skips installing distribution packages when possible** — always use it when importing an already-validated complete image like this one. That first attempt was **interrupted (Ctrl+C) and abandoned on purpose** once this was understood (safe to interrupt only because the intent was full restart, not resume).

**6d. `nvidia-fabricmanager` finalize failure — FIXED.**
Second attempt (with `-s`) failed at "Finalizing image services": `Failed to disable unit, unit nvidia-fabricmanager.service does not exist.` Root cause: `--dgx-type dgx_gb200`'s finalize step unconditionally runs `systemctl disable nvidia-fabricmanager`, but the package was never installed in the source tarball — Fabric Manager runs on the NVSwitch tray at L10, not the compute host (confirmed via `sw_checklist.sh` all session). **Important: user correctly identified this is NOT a gb200-vs-gb300 issue — GB200 has the same off-host FM architecture at L10, so this failure is unrelated to the open dgx-type question.** Fix:
```bash
cm-chroot-sw-img /cm/images/baseos-1014-doca321   # NOT bare chroot - see note below
apt-get install -y nvidia-fabricmanager-580        # matches installed driver 580.126.20
systemctl disable nvidia-fabricmanager             # confirmed succeeded, now shows "disabled"
exit
```
**Note:** always use `cm-chroot-sw-img`, not bare `chroot` — bare chroot doesn't mount `/proc`/`/sys`/`/dev`, producing a wall of misleading warnings including a false "Pending kernel upgrade to 6.8.0-106-generic" (that's just the chroot leaking the **head node's own** x86_64 kernel identity via `uname -r`, nothing to do with the image).

**6e. Duplicate CUDA repo conflict — FIX IDENTIFIED, NOT YET CONFIRMED RUN.**
Resume attempt (`cm-create-image -d /cm/images/baseos-1014-doca321 -n baseos-1014-doca321`) failed at "Validating repo configuration":
```
E: Conflicting values set for option Signed-By regarding source .../sbsa/ /:
   /usr/share/keyrings/cm-cuda-archive-keyring.gpg != /usr/share/keyrings/cuda-archive-keyring.gpg
```
Root cause: two `.list` files declare the same CUDA SBSA URL with two different (both real, both present on disk) keyrings:
- `/etc/apt/sources.list.d/cuda-ubuntu2404-sbsa.list` — original from `maxQ106`, uses `cuda-archive-keyring.gpg` — **KEEP**
- `/etc/apt/sources.list.d/cm-cuda-ubuntu2404-sbsa.list` — **BCM-injected duplicate**, uses `cm-cuda-archive-keyring.gpg` — **REMOVE**

(Ruled out during investigation: not leftover SIGKILL damage from the abandoned 6c attempt — `dpkg --configure -a` ran clean with no output before this error appeared. Not a missing-file issue — `cm-cuda-archive-keyring.gpg` genuinely exists, timestamped from this session.)

**Fix given to user, command not yet confirmed executed:**
```bash
cm-chroot-sw-img /cm/images/baseos-1014-doca321
rm /etc/apt/sources.list.d/cm-cuda-ubuntu2404-sbsa.list
apt list --installed 2>&1 | head -5    # should run clean now, no Signed-By error
exit
```

### 6f. Original resume point — ✅ COMPLETED

1. ✅ 6e fix (removed duplicate `cm-cuda-ubuntu2404-sbsa.list`) run and confirmed.
2. ✅ Re-ran `cm-create-image -d /cm/images/baseos-1014-doca321 -n baseos-1014-doca321 -s --no-cm-cuda-repo` — completed with all stages `[OK]`, including "Adding/Updating software image" (the stage that previously failed on the repo conflict).
3. ✅ All pending verification done:
   - `apt autoremove -y` run — cleared the orphaned `6.14.0-1015` companion packages (`linux-nvidia-6.14-headers/tools-6.14.0-1015`, `linux-tools-6.14.0-1015-nvidia-64k`) plus unrelated auto-installed cruft (bpftrace/bpfcc/libclang/python3-twisted stack, `ubuntu-kernel-accessories`). Flag if you specifically wanted `bpftrace`/`bpfcc` tools kept on the base image for diagnostics — they're gone now.
   - `dpkg -l | grep -E "^[hi]i.*linux-(image|modules)"` inside `cm-chroot-sw-img` — confirmed **only** `6.17.0-1014-nvidia-64k` image/modules present, both `hi`. No stray `6.8.0-106-generic-64k`.
   - `ls -la /boot/vmlinuz-6.17* /boot/initrd.img-6.17*` inside the chroot — both present, correctly named.
   - **Note on the image's own `/boot/grub/grub.cfg` (checked from the head node, not the chroot):** it does NOT contain a real `linux ...` boot line or kernel `menuentry` — only a `UEFI Firmware Settings` stub. **This is expected, not a defect.** BCM node-installer regenerates the actual bootloader config on each node's own local disk during provisioning (real hardware, real `/proc`/`/dev`), not from this file. The `dpkg`/`vmlinuz`/`initrd` checks above are the meaningful validation of kernel state inside the image; the image-tree `grub.cfg` is not.
   - Registration confirmed via `cmsh -c "softwareimage; list"` — `baseos-1014-doca321` present alongside `default-image` and `default-image-ubuntu2404-aarch64`.
4. No new errors surfaced during this pass.

### 6g. Full from-archive rebuild — reproducibility check, ✅ PASSED (2026-08-24)

To confirm the whole image-build process is repeatable for the remaining 7 racks (not just resumable from a half-built state), did a full teardown and from-archive rebuild rather than another `-d` resume:

```bash
cmsh -c "softwareimage; remove baseos-1014-doca321; commit"
rm -rf /cm/images/baseos-1014-doca321

cm-create-image -a /root/bcm-image-export/maxQ106-1014-doca321-baseos.tgz \
  -n baseos-1014-doca321 \
  --dgx-type dgx_gb200 \
  -s \
  --no-cm-cuda-repo
```

Result: hit the **same, already-diagnosed** fabricmanager finalize failure from 6d (expected — that failure is inherent to `--dgx-type dgx_gb200`'s finalize step against a source tarball that never had `nvidia-fabricmanager` installed, not something the `-s`/repo fixes touch). Fixed the same way as 6d:

```bash
cm-chroot-sw-img /cm/images/baseos-1014-doca321
chmod 1777 /tmp && rm -rf /tmp/*
apt-get update && apt-get install -y nvidia-fabricmanager-580
systemctl disable nvidia-fabricmanager
exit
```

`chmod 1777 /tmp && rm -rf /tmp/*` was needed this time before `apt-get` would run cleanly — worth including as a standard step in the fabricmanager fix going forward, not just a one-off.

**On `uname -r` returning `6.8.0-106-generic` inside the chroot:** this is expected and *not* a sign the wrong kernel is installed — `uname -r` inside any chroot (bare or `cm-chroot-sw-img`) reports the **host kernel's** identity, since chroot changes the filesystem root, not the running kernel. Only `dpkg -l`, `/boot` contents, and (post-provisioning) the node's own `uname -r` are meaningful checks. Re-noting this because it's a recurring "looks alarming, isn't" trap — same root cause as the false "pending kernel upgrade to 6.8.0-106-generic" warning documented in 6d.

Followed with the same `apt-get autoremove -y` cleanup and `dpkg`/`vmlinuz`/`initrd` verification as 6f — all clean, identical results to the `-d` resume path.

### 6h. New gotcha found: `cm-chroot-sw-img` does not fully unmount on exit

After `exit`ing the chroot in 6g, `dev`, `proc`, `sys`, and `tmpfs` mounts for `/run` and `/run/systemd/resolve/resolv.conf` were all still present and needed manual `umount -l` calls, one at a time, before the image directory was actually clean.

**Confirmed recurring, not a one-off:** happened again on a later check — same set of mounts, plus `dev/pts`, which wasn't in the original list. Full mount set observed across both incidents: `dev/pts`, `dev`, `proc`, `sys`, `run/systemd/resolve/resolv.conf`, `run`.

**Why this matters:** running `cm-create-image -d ...` (or any host-side operation on the image directory) while bind mounts from a prior `cm-chroot-sw-img` session are still active risks either capturing live chroot-session mutations of `/proc`/`/sys`/`/run` into the image, or a "device busy" failure mid-build — same failure family as the original archive-corruption bug in the top of Section 6 (unescaped `/proc`/`/sys` in the tar capture), just at the chroot-teardown stage instead of the tar-capture stage.

**Canonical fix — ordered teardown script (deepest mount first, so `dev` isn't busy when unmounting):**
```bash
#!/bin/bash
# unmount-bcm-image.sh <image-name>
# Run after every `exit` from cm-chroot-sw-img, before any further
# cm-create-image or host-side operation on the same image directory.
IMG="/cm/images/$1"
for m in dev/pts dev proc sys run/systemd/resolve/resolv.conf run; do
  umount -l "$IMG/$m" 2>/dev/null
done
grep "$IMG/" /proc/mounts   # should return nothing; investigate with lsof +D "$IMG" if anything's still listed
```

**New standing rule, added to the runbook:** after every `exit` from `cm-chroot-sw-img`, run `unmount-bcm-image.sh <image-name>` before running any further `cm-create-image` command against that image. This has now shown up on two separate chroot sessions (6g rebuild, and a later standalone check) with a consistent mount set each time, so treat it as a permanent step in the image-build procedure for all remaining racks, not a one-off cleanup.

### 6i. Investigation: irrelevant `6.8.0-106-generic-64k` kernel pulled in during "Installing CM packages" — root cause of the multi-hour build time

This traces back to the very first symptom reported in this thread ("Installing CM packages... takes a very long time"). Full investigation via `/var/log/cm-create-image-baseos-1014-doca321.log` (4459 lines, confirmed complete — `mtime` matches the run's final commit timestamp, `tail` shows a clean finish through "Adding/Updating software image" → "Software image commit attempt 0" → "Cleaning up," ruling out a truncated/stale log).

**Confirmed facts:**
- The "Installing CM packages" stage's `apt-get install` command explicitly names `linux-headers-6.8.0-106-generic-64k`, `linux-modules-6.8.0-106-generic-64k`, `linux-image-6.8.0-106-generic-64k`, `linux-tools-6.8.0-106`, `linux-tools-6.8.0-106-generic-64k` in its argument list (not pulled in as a transitive dependency) — this happened **twice** in this build, at `10:30:02` and again at `13:41:08`, each installing the same ~500-package CM baseline.
- **`-s --no-cm-cuda-repo` do not prevent this.** This is a materially different finding than 6c, which attributed the earlier no-`-s` stray-kernel problem to BCM's default distribution-package sync. This package list comes from a different stage ("Installing CM packages," not distribution baseline sync), and `-s` doesn't cover it.
- Both times, once `linux-headers-6.8.0-106-generic-64k` finished configuring, it auto-triggered a DKMS build cycle (`iser`, `isert`, `kernel-mft-dkms`, `knem`, `mlnx-ofed-kernel`) against that throwaway kernel. `iser`/`isert` fail fast ("Bad return status"); `mlnx-ofed-kernel` is a large, slow build under QEMU emulation — this is almost certainly where most of the ~8.5-hour total build time went (first apt-get at 10:30:02, final commit at 17:36:51).
- **Despite being explicitly installed twice, none of `linux-image-6.8.0-106-generic-64k` / `linux-modules-6.8.0-106-generic-64k` / `linux-tools-6.8.0-106*` ever appear in a `Setting up`, `Removing`, or `Purging` line anywhere in the complete log** — only `linux-headers-6.8.0-106*` got a `Setting up` line, both times. Yet the final, verified `dpkg -l` (per 6f) shows **zero trace** of any `6.8.0-106` package, not even as a removed/`rc` remnant.
- **Mechanism for that disappearance is still not conclusively identified.** Leading candidate: every `apt-get install` in this log runs with `--setenv=DEFER_CONFIG=yes`, suggesting some deferred-configuration policy for kernel-class packages that this custom log doesn't fully narrate. This log (a `cm-create-image`-level wrapper log) isn't the authoritative dpkg transaction record — **`/var/log/apt/history.log` and `/var/log/apt/term.log` inside the image** (via `cm-chroot-sw-img`) would be, and weren't checked this session. Worth pulling on the next build if the mechanism needs to be nailed down for the NV/BCM write-up rather than just observed as a (so far reliable) end state.

**Operational impact for the remaining 7 racks:** if this reproduces on every from-scratch build, each image build could cost most of a day, dominated by two redundant DKMS/OFED build cycles against a kernel that's discarded either way. Worth raising with NV/BCM support as an inefficiency in `--dgx-type dgx_gb200`'s "Installing CM packages" package list, separately from the already-known fabricmanager finalize issue.

### 6j. `Finalizing cluster services` — bind9 disable failure, non-fatal (different behavior than the 6d fabricmanager case)

Same failure *shape* as 6d (`systemctl disable <service>` failing with `unit ... does not exist`, because the service was never installed in the source tarball) — this time for `bind9` during "Finalizing cluster services":

```
Failed to disable unit, unit bind9.service does not exist.
Container baseos-1014-doca321 failed with error code 1.
```

**Key difference from 6d: this did NOT abort the build.** The log shows `cm-create-image` logged the error and continued immediately to the next step (`Turning off service: slapd`, which also isn't installed but presumably doesn't hit the same failure), then proceeded through cert copy and final commit without issue. This means "Finalizing image services" (where the fabricmanager failure lived) and "Finalizing cluster services" (where this bind9 failure lives) have **different fatality behavior** — only the former needs the manual `cm-chroot-sw-img` intervention from 6d. Worth keeping this distinction explicit in the runbook so a future bind9-style message during "Finalizing cluster services" isn't mistaken for a blocker requiring the same fix.

### 6k. Package-integrity check — DOCA/driver/IMEX confirmed untouched by `cm-create-image` (✅ resolved, one false alarm corrected)

Direct question worth asking before provisioning: does any part of the `cm-create-image` build process (6g/6i's `6.8.0-106` activity, CM package install, etc.) touch the validated DOCA 3.2.1 stack itself? Checked via `cm-chroot-sw-img`:

- `dkms status | grep 6.17.0-1014` — full validated module stack present and correctly built against the right kernel: `nvidia/580.126.20`, `mlnx-ofed-kernel`, `knem`, `kernel-mft-dkms`, `iser`/`isert`/`srp`, `xpmem`, all `installed`. Confirms the `6.8.0-106` DKMS activity in 6i was genuinely isolated to its own kernel tree, as expected (DKMS keys module builds by kernel version).
- `dpkg -l | grep -iE "doca|mlnx-ofed|..."` — every `doca-*` package matches the validated baseline exactly: `doca-host 3.2.1-044413-25.10-ubuntu2404`, `doca-runtime 3.2.1-044413`, `mlnx-ofed-kernel-dkms 25.10.OFED.25.10.1.7.1.409.1-1`.
- `apt-cache policy doca-host` — **`Installed == Candidate`**, confirms apt has nothing newer queued and the "Installing CM packages" stage did not silently upgrade it.
- `apt-cache policy nvidia-imex-580` — **not installed** (`Installed: (none)`). Correct and expected: the `580.173.02` IMEX build is staged for the separate 2.0.0/DOCA-3.4.1 field-upgrade path (Section 3), not part of this image's validated 3.2.1 baseline. Its absence here is right, not a gap.

**One false alarm raised and corrected during this check:** `nvidia-fabricmanager-580` showed `580.173.02` installed, vs. the DKMS-built driver at `580.126.20` — flagged initially as a blocking version mismatch. **Corrected:** per 6d, `nvidia-fabricmanager-580` exists in this image *only* to satisfy `--dgx-type dgx_gb200`'s finalize step (`systemctl disable nvidia-fabricmanager`) — real Fabric Manager for this architecture runs off-host on the NVSwitch tray at L10, never on the compute node. The package is installed, immediately disabled, and never runs — so its version relative to the driver is irrelevant. No fix needed. Worth keeping this reasoning explicit in the runbook so the same false alarm isn't re-raised on the remaining 7 racks.

**Conclusion: `cm-create-image` has not modified DOCA 3.2.1, the driver, or IMEX in any way that matters.** The only things it touched were the throwaway `6.8.0-106` kernel (6i, cosmetic/isolated) and the disabled, never-run `nvidia-fabricmanager-580` package (this section, harmless). Validated stack is intact — clear to proceed to category/node assignment.

**Follow-up: `mask`, don't remove, `nvidia-fabricmanager` — new standing step for this and all 7 remaining racks. UPDATE (2026-08-25): source archive now bakes this in directly; per-build manual fix is no longer needed when building from the updated archive.**

Tempting to purge the package entirely now that the image is built, to prevent an operator from mistakenly starting it on a compute node (a real risk, since other DGX-class topologies *do* run FM on the host, so the habit isn't unreasonable). **Don't** — `--dgx-type dgx_gb200`/`dgx_gb300`'s finalize step unconditionally runs `systemctl disable nvidia-fabricmanager` on *every* `cm-create-image` build. Removing the package would reproduce the exact 6d failure (`disable` erroring on a nonexistent unit, which — unlike the 6j bind9 case — is fatal to that finalize stage) on the very next resume, **unless** a masked-unit override is present regardless of package state (see below).

Correct fix: `mask` instead of just `disable`. Masking symlinks the unit to `/dev/null`, blocking even a manual `systemctl start` with a clear "unit is masked" error — a much stronger and clearer guard against accidental use than plain `disable` (which only prevents auto-start at boot, not a manual one).

**Discovered this session: the mask override alone (`/etc/systemd/system/nvidia-fabricmanager.service -> /dev/null`) is sufficient to satisfy the finalize step, even without `nvidia-fabricmanager-580` installed as a package at all.** `systemctl disable` treats a masked unit as "existing" because the `/etc` override is itself a real unit reference — so once this symlink is present in the source archive, `cm-create-image`'s finalize step succeeds without ever needing the 6d install-then-mask chroot fix. Confirmed via a re-tar of the reference layout that included this override (baked in from earlier live troubleshooting on the reference host, per this session's history) — the subsequent build completed "Finalizing image services" cleanly with no `nvidia-fabricmanager` failure or manual intervention at all.

**Caveat, worth keeping in mind:** in the confirmed case, `dpkg -l nvidia-fabricmanager-580` still shows `un` (completely unknown to dpkg) even though the mask override and the real (unused) unit file from `/lib/systemd/system/` are both present on disk. This is a bookkeeping mismatch, not a functional problem — the override is a real symlink and blocks starting the service regardless of what dpkg's database says. But it means **`dpkg -l` is not a reliable way to verify this fix is in place** for future builds; check the filesystem directly instead:

```bash
cm-chroot-sw-img /cm/images/<image-name>
ls -la /etc/systemd/system/nvidia-fabricmanager.service
# expect: lrwxrwxrwx ... nvidia-fabricmanager.service -> /dev/null
exit
```

(`systemctl status` cannot be used for this check from inside `cm-chroot-sw-img` — it fails with `Host is down` / "System has not been booted with systemd as init system," since the chroot has no running PID 1/D-Bus. Use the filesystem check above instead.)

**Updated standing step for the remaining 7 racks:** if building from the **updated** reference archive (the one that already contains this masked override — confirm which `.tgz` path is current, since the original, unmodified archive does **not** have this and would still need the manual 6d/8.3 fix), the fabricmanager finalize step should succeed without intervention — verify via the `ls -la` check above rather than assuming, and fall back to the manual install-and-mask fix (8.3) if the override isn't present in whichever archive is actually in use.

### EXACT RESUME POINT — start here in the next session

Image build is stable and reproducible (6f + 6g confirm it two different ways), though 6i found it's costing ~8.5 hours per build, dominated by a redundant DKMS/OFED cycle against an irrelevant kernel. 6k confirms DOCA/driver/IMEX are untouched and correct. **6l/6m: both `dgx_gb200` and `dgx_gb300` are now confirmed to build successfully — the production-named `baseos-1014-doca321` was most recently rebuilt with `--dgx-type dgx_gb300`, after a host-level `/dev` incident (6m) was resolved via reboot.** Which flag is *correct* for real GB300 NVL hardware is still open with NV; viability is not. Next, grouped by phase:

**Phase 1 — Blocking verification & escalation (resolve before touching category/nodes):**
1. **Verify, don't assume:** check whether `baseos-1014-doca321`'s current build already has the fabricmanager mask override baked in (`ls -la /etc/systemd/system/nvidia-fabricmanager.service` inside `cm-chroot-sw-img` — expect `-> /dev/null`; see 6k). If present, no further action needed on this point. If absent, apply the manual install-and-mask fix (8.3) and re-commit via `-d` before assigning this image to a category.
2. **Escalate to NV** per 6l's updated question — which of `gb200`/`gb300` is correct for GB300 NVL, and whether `maxQ106`'s original validation ever went through this flag at all. Do not provision the 18-node rack until this is answered, given the risk is now a silent wrong-parameter choice (e.g. IOMMU/PCIe/NVLink topology), not a build failure.

**Phase 2 — Pending image-level fixes (resolve/apply before assigning nodes, not after):**
3. **✅ Resolved 2026-09-04:** the `hosts.suffix`/`#HOSTNAME#` approach was confirmed non-functional; a working finalize-script fix (v3) is validated across a full 18-node rack01 redeploy — see 6n/8.9. **Still open:** confirm this actually fixes `BF3PcieInterfaceTraffic` partnerdiag (never independently verified), and decide whether to bake the finalize-script assignment into the `maxQ106` reference build.
4. **The `nsswitch.conf` SSSD-hang fix (6o/8.8) is confirmed to regress `cmsupport` account resolution** (real-node evidence, `rack01node18`, 2026-09-08) — needs a revised remediation (tune SSSD timeout/negative-cache instead of `files`-only, or explicitly allow-list only the accounts that don't need LDAP) before being applied to any further racks or baked into `maxQ106`. Do not treat 8.8 as done.
5. Decide and apply a fix for the `/swap.img` sparse-file inflation (6p) — either fix the tar sparseness (archive-creation side or `cm-create-image --tar-options`) or simply exclude `swap.img` from the image via `-o`/`--exclude-from`. Costs ~8GB per image otherwise, multiplied across 8 racks.

**Phase 3 — Optional diagnostics (nice-to-have, not blocking provisioning):**
6. Optional, recommended: run the `gb200` vs `gb300` diff described in 6l (kernel params + package list) to have concrete data ready for NV, and/or for your own judgment call if NV's answer is delayed.
7. Optional but recommended before repeating x7: check `/var/log/apt/history.log` and `/var/log/apt/term.log` inside the image (`cm-chroot-sw-img`) on the next build to nail down the exact mechanism by which the `6.8.0-106` packages vanish from `dpkg -l` despite being explicitly installed twice (see 6i) — needed for a precise NV/BCM support write-up, not needed to proceed with provisioning.
8. Before any future rack build, if "Validating repo configuration" fails again, check the head node's own `/dev` (6m) before assuming it's a repo or `--dgx-type` problem — this failure signature now has two known, unrelated causes.

**Phase 4 — Actual provisioning (once Phases 1–2 are resolved):**
9. Assign category to `baseos-1014-doca321`.
10. Assign the 18 nodes in the target rack to that category.
11. Provision the rack, watching for the per-node identity question below (machine-id/SSH host keys/hostname) since it hasn't been confirmed to auto-resolve yet.
12. Run L11 (rack/fabric-level) partnerdiag once provisioned.
13. If any NEW error appears at any step, apply the same pattern used throughout Section 6: get the exact line from `/var/log/cm-create-image-baseos-1014-doca321.log` (or the equivalent node-installer log once past image-build) — don't guess from a truncated on-screen `[FAILED]` message. Remember "Finalizing cluster services" failures may be non-fatal (6j) while "Finalizing image services" failures are not (6d).

**Phase 5:**
14. Resolve the still-open items below in parallel.

### Still-open, non-blocking items
- **`ntp` health check FAIL — root cause confirmed, fix drafted, not yet applied or validated.** `chrony` missing from the image entirely; category `timeservers` field does not drive persistent sync. See 8.12. **Confirmed at fleet scale (2026-09-08):** all 18 `rack01`/`maxQ-1014-doca321` nodes show `health check failed` in `cmsh device list` — consistent with this and the `ldap` regression below being the cause, not isolated to the single-node spot-checks. For contrast, all 18 `rack08`/`baseos-1029-doca341` nodes (separate image, chrony fix already applied there per `gb300_l10_build_log.md` §26) show clean `[UP]` with no failure flag — same head node, same day, only difference being the chrony/nsswitch fixes' presence.
- **`ldap` health check FAIL (`cmsupport` user) — ✅ CONFIRMED as a direct regression from 8.8's `nsswitch.conf` local-only fix (2026-09-08).** Reproduced on `rack01node18`, running the correct image (`baseos-1014-doca321`/`maxQ106`, with 8.8 actually applied — confirmed via `latesthealthdata`), so this is real evidence, not the earlier confounded observation on `rack08node18` (which turned out to be a different node, on a different image entirely, checked mid-`cm-create-image`-write on an unrelated build — that result should be disregarded). `id: 'cmsupport': no such user` reproduces exactly as suspected: `cmsupport` apparently must resolve via LDAP, and 8.8's `files`-only override for `passwd`/`group`/`netgroup` blocks that lookup entirely. **This means 8.8's trade-off is not safe as currently written — needs a fix that stops the SSSD/LDAP hang (6o) without breaking accounts, like `cmsupport`, that genuinely require LDAP resolution.** Candidate directions to investigate next session: (a) keep `sssd` in `nsswitch.conf` but tune SSSD's own negative-cache/timeout settings so unknown-UID lookups fail fast instead of hanging, rather than removing LDAP from the chain entirely; (b) explicitly allow-list `cmsupport` (and any other required service accounts) to resolve locally via `/etc/passwd` while leaving `nsswitch.conf` otherwise pointed at SSSD for everything else. Do not consider 8.8 closed/final until one of these is validated — reverting to the pre-8.8 `nsswitch.conf` isn't safe either, since 6o's hang was independently reproduced and confirmed on real hardware.
- **`gpu_health_nvlink` FAIL (all 4 GPUs) and `gpu_health_overall` FAIL on `rack01node18` (2026-09-08) — expected, not a bug.** Info: `Fabric State is In Progress (2). Ensure that the FabricManager is...`. Confirmed benign: this is the expected pre-GFM-configuration state for this GB300 NVL topology (real Fabric Manager runs off-host on the NVSwitch tray per 6k, not on the compute node) — will clear once GFM is configured on the NVSwitches. **Corroborating evidence:** `rack08` (different image/rack — `baseos-1029-doca341`, not `maxQ106`, so not a same-image comparison, but same underlying fabric-state mechanism) shows no `gpu_health_nvlink` FAIL, consistent with rack08's NVSwitches already having GFM configured while rack01's do not yet. Supports fabric state being a rack-infrastructure/GFM-configuration property, not something tied to the compute-node image. No fix needed on the compute-image side; re-check `rack01` after NVSwitch GFM configuration to confirm it clears as expected, but not a blocker for anything upstream of that step.
- **`gpu_health_overall` FAIL despite all per-GPU sub-checks PASS** on `rack01node01` — cause unknown, not yet investigated.
- Per-node identity regeneration (machine-id, SSH host keys, hostname) across the 18 nodes — not yet confirmed how/whether BCM's node-installer handles this automatically. Check "Assigning Images to Nodes and Post Installation Configurations" doc section.
- Whether an off-box backup of `maxQ106`'s pre-BCM-capture state exists — still never explicitly confirmed this session.
- **Bake missing `/etc/network/interfaces.d/`, `/etc/ntpsec/` directories, and the `nsswitch.conf` SSSD-hang fix (6o) into `maxQ106` before the next re-tar (8.7/6o).** Currently only patched live on `baseos-1014-doca321`'s extracted image directory — won't survive a fresh `-a` rebuild and hasn't been applied to any of the other 7 racks' future images. Same category of fix as the fabricmanager mask override (6k) — do all of these in one pass on the reference host, not repeated per rack.
- **`/swap.img` inflated from 8.0K (sparse) to 8.0GB (fully allocated) during image capture (6p)** — confirmed via direct `du`/`ls -lsh`/`--apparent-size` measurement, root cause (tar sparseness lost somewhere in the archive-creation or extraction path) suspected but not pinned down. No fix applied yet; decide between fixing tar sparseness (`--tar-options --sparse`) vs. simply excluding `swap.img` from the image (`-o`/`--exclude-from`). Costs ~8GB per image, multiplied across all 8 racks if left unaddressed.
- **`6.8.0-106-generic-64k` build-time cost (6i)** — reproduces reliably (hit in both the incremental and from-archive builds) and costs real wall-clock time (~8.5hr total build observed) via redundant DKMS/OFED cycles against a kernel that's discarded either way. Exact disposal mechanism unconfirmed (see 6i); worth an NV/BCM support report regardless, given it'll recur on all 7 remaining racks unless addressed.
- **Root cause of the 6m `devtmpfs` incident** — head node recovered via reboot, but why it happened was never established. Worth a proper post-incident review with whoever else has admin/on-call ownership of this system, separate from the rack-build work.
- **`BF3PcieInterfaceTraffic` partnerdiag fix (6n/8.9) — delivery mechanism resolved and validated (18-node rack01 redeploy), but the underlying fix theory itself still unconfirmed.** Re-run partnerdiag on a rack01 node to confirm this actually resolves the failure before treating the original problem as closed.

### 6l. `--dgx-type dgx_gb200` vs `dgx_gb300` — ✅ both build successfully; question reframed from "which works" to "which is correct"

Originally re-flagged as a blocking open question after `cm-create-image --help` showed `dgx_gb300` is a valid, available option whose description ("obtain proper kernel parameters") suggested it may be the more correct choice for this documented GB300 NVL hardware, versus the `dgx_gb200` used in every build so far per earlier NV verbal guidance.

**What happened next, and the correction to make here:** an attempt to build with `dgx_gb300` failed at "Validating repo configuration" (`Failure getting installed package list` / `Failed to install packages`). This was initially investigated as a possible `gb300`-specific defect — but a subsequent `gb200` build, run purely as a control, **failed identically**, which redirected the investigation to the head node itself. Root cause turned out to be host-level: the head node's `devtmpfs` (`/dev`) had lost most of its standard character device nodes (`/dev/null`, `/dev/zero`, `/dev/random`, `/dev/urandom`, `/dev/tty`, `/dev/console`, `/dev/full`, and `/dev/nvme0`), which broke `apt-get`/package operations inside every `systemd-nspawn` container regardless of `--dgx-type`. Full incident writeup in **6m**. Once the head node was rebooted and confirmed healthy, **`dgx_gb300` built successfully end-to-end, all stages `[OK]`**, registered correctly in `cmsh -c "softwareimage; list"` with the expected kernel version.

**Net effect: both `dgx_gb200` and `dgx_gb300` are confirmed to build successfully in this environment.** Neither was ever actually broken — the entire back-and-forth on this point traces to the 6m incident, not to either flag. This means the earlier "gb300 doesn't work, stick with gb200 out of necessity" conclusion was wrong, and should not be carried forward or cited.

**Still open, now cleanly scoped:** which is *correct* for GB300 NVL hardware — this is a real, unresolved question, not settled by either flag simply working. The `--help` text's kernel-parameter framing and the documented GB300 NVL target hardware still argue for at least seriously considering `gb300`; NV's earlier verbal guidance for `gb200` still stands as the only real-hardware-tested precedent (via `maxQ106`'s partnerdiag `PASS`) — **but it was never confirmed whether `maxQ106`'s own build/validation history ever went through `cm-create-image`'s `--dgx-type` flag at all**, which would mean that precedent doesn't actually validate the flag choice either. Worth clarifying with NV as part of the same escalation.

**Recommended path, updated:**
1. **Escalate to NV** with the sharper, now fully-evidenced question:
   > "`cm-create-image`'s `--dgx-type` help states it's used to 'obtain proper kernel parameters,' and `dgx_gb300` is a valid choice in our BCM version — we've now confirmed both `dgx_gb200` and `dgx_gb300` build successfully in our environment. Given our target hardware is GB300 NVL, which is correct? Separately: did `maxQ106`'s original reference build/validation ever go through this flag, and if so, which value?"
2. **Do not assign nodes to either image until this is answered.** A successful build is necessary but not sufficient — the risk now is a *silent* wrong choice (e.g. subtly wrong IOMMU/PCIe/NVLink boot parameters for real GB300 topology) rather than a build failure, which is harder to catch and worth NV's explicit confirmation before 18 nodes are provisioned on it.
3. **Concrete comparison, now possible since both build:** diff the two images' kernel parameter / GRUB config and package selection directly, as originally planned in the prior version of this section:
   ```bash
   diff <(cm-chroot-sw-img /cm/images/baseos-1014-doca321 dpkg -l) \
        <(cm-chroot-sw-img /cm/images/baseos-1014-doca321-gb300test dpkg -l)
   diff <(cm-chroot-sw-img /cm/images/baseos-1014-doca321 cat /etc/default/grub) \
        <(cm-chroot-sw-img /cm/images/baseos-1014-doca321-gb300test cat /etc/default/grub)
   ```
   (Note: as of this writing, the production-named `baseos-1014-doca321` was rebuilt **with `--dgx-type dgx_gb300`**, not `gb200` — see the note in 6m/resume point. If a `gb200` comparison image is still needed, it will need to be rebuilt under a separate test name first.)

**Status:** open on *correctness*, not blocking on *viability*. Both flags work; don't let that be mistaken for the question being resolved.

### 6m. Incident: head-node `devtmpfs` lost core device nodes mid-session — resolved via reboot, root cause NOT confirmed

**Timeline:** first surfaced as a `cm-create-image` failure (`Validating repo configuration` → `Failure getting installed package list`) on a `dgx_gb300` build. Investigated initially as a possible dgx-type-specific defect; a `dgx_gb200` control build failed identically, which correctly redirected the investigation away from `--dgx-type` and toward the host. Log showed the real, consistent error underneath the generic on-screen message:
```
/dev/null is not a char or block device, cannot copy.
```
Direct host checks confirmed `/dev/null` itself was missing (`No such file or directory`) — not just wrong-typed — and a wider sweep found `/dev/zero`, `/dev/random`, `/dev/urandom`, `/dev/tty`, `/dev/console`, `/dev/full`, and `/dev/nvme0` **all** missing as well. `/dev` was correctly mounted as `devtmpfs` and `systemd-udevd` was reported active/healthy throughout — `mount -o remount /dev` and `udevadm trigger && udevadm settle` both failed to repopulate the missing nodes, which is not normal degraded behavior for a live devtmpfs.

Manually recreating each node with `mknod` (using standard major/minor numbers) worked as an immediate stopgap and briefly restored basic function, but was explicitly treated as incomplete — `mknod` only covers well-known standard nodes, not hardware-specific ones (e.g. whatever was backing `/dev/nvme0`), so an unknown amount of `/dev` could still have been affected beyond what was manually checked.

**Resolution: a full reboot of the head node.** Post-reboot, all standard device nodes were confirmed present, and the next `cm-create-image` build (the `dgx_gb300` build referenced in 6l) completed successfully end-to-end.

**Root cause: not established.** Notable but unconfirmed candidates considered during the incident:
- Possible connection to this session's own repeated `cm-chroot-sw-img` mount-cleanup work (6h/8.4) — those commands were only ever meant to target `/cm/images/<image-name>/dev` etc., but the *possibility* that a mistyped or malformed unmount at some point during this long session affected the host's real `/dev` (rather than just the image directory's bind-mounted copy) was raised and never definitively ruled out or confirmed.
- Independently-logged `dmesg` warnings around the same period (`xfs_reclaim_worker`/`xlog_ioend_work` "hogged CPU," `perf: interrupt took too long`) suggest the head node may have been under real filesystem/scheduling stress in the surrounding timeframe, though no direct causal link to the devtmpfs depopulation was established.
- Continuous `dhclient: send_packet: No such device or address` errors were present throughout the incident window and are very likely a downstream symptom of the same broken `/dev` (network device access failing without a functioning `/dev`), not a separate, independent problem.

**This should not be treated as fully closed.** The system is confirmed working again, but *why* a live, actively-managed `devtmpfs` lost the bulk of its standard nodes — with `udevadm` unable to repopulate them, requiring a full reboot to restore — was never explained. Given this head node manages 144 other production nodes, this is worth a proper post-incident review (system logs from the actual incident window, correlated against exact command history) outside the scope of continued rack-build work, ideally with whoever else has admin/on-call responsibility for this system.

**Practical implications for the remaining 7 racks:**
- Don't assume `--dgx-type` (either value) is the cause of a "Validating repo configuration" failure again without first checking `ls -la /dev/null` (or the same wider sweep) on the head node directly — this failure signature is now known to have at least two unrelated possible causes (the 6e repo-conflict class, and this devtmpfs class), and the on-screen message doesn't distinguish them.
- If any future rack build hits this same failure signature, check the host's `/dev` **before** re-running any chroot-cleanup or `cm-create-image` commands, given the (unconfirmed but not ruled out) possibility that mount-cleanup activity is implicated.

### 6n. ✅ RESOLVED: `/etc/hosts` `127.0.1.1 <hostname>` fix for `BF3PcieInterfaceTraffic` partnerdiag failure (2026-09-04)

Originally raised as a candidate remedy for a `BF3PcieInterfaceTraffic` partnerdiag test failure on nodes provisioned from `baseos-1014-doca321`. The original candidate command:
```bash
echo "127.0.1.1   #HOSTNAME#" > /cm/images/baseos-1014-doca321/etc/hosts.suffix
```
was never applied and is now confirmed **not a real BCM mechanism** — see resolution below. Both open questions flagged at the time this was first raised turned out to be justified, not just theoretical caution:

**Confirmed: `hosts.suffix` does nothing.** Node-installer's own log (`/var/log/node-installer`) shows it generates `/etc/hosts` internally from its own template + device database at two points during provisioning (`/tmp/hosts` early, then `/localdisk/etc/hosts` later) — with no log line anywhere indicating it reads or merges any `.suffix` companion file. The file would sync onto disk via the image rsync step, then simply sit there unused, never referenced by anything. Also confirmed `#HOSTNAME#` is not a real BCM macro — moot, since the merge mechanism it depended on doesn't exist either.

**Actual working fix — three iterations, real root cause found on the second:**

- **v1** (`echo "127.0.1.1 $(hostname)" >> /etc/hosts`, delivered as a BCM category finalize script): ran successfully every time (confirmed via node-installer log: `Finalize script:finalize-hosts-127: appended 127.0.1.1 rack08node18 to /etc/hosts`), but the appended line never survived to the booted node. **Root cause confirmed directly from BCM's own shipped example** (`/cm/local/apps/cmd/etc/htdocs/scripts/finalize/log_available_environment_variables.sh`), which states outright in its header comment: *"The root / of the running node is always mounted on /localdisk"* during the finalize stage. v1 wrote to the ramdisk's own throwaway `/etc/hosts`, not the target node's persisted file at `/localdisk/etc/hosts` — a chroot/path mismatch, not a race condition or a cmd-overwrite as first suspected.
- **v2** (self-healing systemd `.path` unit watching `/etc/hosts` for changes, re-applying the entry on every trigger, installed via the finalize script): built as a workaround that sidesteps the path-mismatch question entirely by running post-boot, on the real filesystem, regardless of when/how cmd or node-installer touch the file. Sound in principle, tested logically, but ultimately not needed once the actual root cause was found — not deployed to the category.
- **v3** (shipped fix): writes directly to `/localdisk/etc/hosts` instead of `/etc/hosts`, fixing the root cause directly rather than working around it. Saved as a real on-disk reference copy at `/cm/local/apps/cmd/etc/htdocs/scripts/finalize/finalize-hosts-127-v3.sh` (alongside BCM's own shipped finalize examples — confirmed this is a real, cmsh-tab-completion-recognized directory, not an assumption), and applied to `category[maxQ-1014-doca321]` via `set finalizescript finalize-hosts-127-v3.sh` (cmsh reads the file directly by name from that directory — cleaner than the interactive editor-paste method used for v1/v2, confirmed working).

**Validated 2026-09-04 on a full rack01 redeploy (18× L10 nodes)**, not just a single retest:
```
rack01node01: 127.0.1.1   rack01node01
rack01node02: 127.0.1.1   rack01node02
rack01node09: 127.0.1.1   rack01node09
rack01node18: 127.0.1.1   rack01node18
```
Each node correctly shows its own hostname — no cross-contamination, no leftover `#HOSTNAME#` literal, no missing entries across a spot-check of 4 of 18 nodes.

**Still open, not yet closed out:** whether this actually makes `BF3PcieInterfaceTraffic` partnerdiag pass has **not yet been re-run and confirmed** on a node with this fix applied. The `/etc/hosts`-content theory for that failure was never independently verified — only assumed from how the original fix was framed when first proposed. Re-run partnerdiag on at least one of the rack01 nodes and confirm pass before treating the *original problem* (not just the delivery mechanism) as closed.

**Also open:** per the original archive-vs-live-directory caveat, this fix currently lives only in `category[maxQ-1014-doca321]`'s finalize script — confirm whether it needs to be reflected in the `maxQ106`/reference-image build process (§8) so it's not lost on a future image rebuild that doesn't go through this specific category.


### 6o. `ls -l`/`id` hangs on non-existent UIDs — SSSD/LDAP lookup timeout, fixed via `nsswitch.conf` — ✅ real-node reproduction and fix confirmed

**Symptom:** commands resolving a UID/GID not present locally (e.g. `id <uid>`, `ls -l` on files owned by an unmapped UID) hang for an extended period rather than failing fast. Root cause: `/etc/nsswitch.conf`'s default `passwd`/`group`/`netgroup` lines fall through to SSSD, which in turn attempts an LDAP lookup for the unknown ID and blocks until that lookup times out, rather than returning "unknown" immediately.

**Fix, applied on `maxQ106`:**

```bash
cm-chroot-sw-img /cm/images/baseos-1014-doca321
sed -i 's/passwd:.*/passwd:     files/' /etc/nsswitch.conf
sed -i 's/group:.*/group:      files/' /etc/nsswitch.conf
sed -i 's/netgroup:.*/netgroup:   files/' /etc/nsswitch.conf
exit
```

**Important trade-off, worth confirming is actually intended before this goes into all 8 racks' images:** this doesn't just fix the hang — it **disables SSSD/LDAP-based identity resolution on the node entirely**, falling back to local (`files`-based, i.e. `/etc/passwd`/`/etc/group`) account resolution only. Correct if these compute nodes are only ever accessed via local accounts (which is typical for BCM-managed compute nodes, where identity/auth is usually handled at the head-node/login-node layer rather than per-compute-node). Would be a real regression if any operator workflow depends on LDAP/AD-resolved accounts working directly on the compute nodes themselves. **Confirm this assumption holds for this cluster's actual access model before treating this as fully settled** — the *mechanism* is now proven real-world; the *access-model trade-off* is not yet confirmed intended.

**✅ Real-node confirmation (supersedes the earlier chroot-only verification concern):** the exact symptom this section describes was independently reproduced on a real, PXE-provisioned node — `ls`/`ll` on `/home/SIT/nvdiag/629-24059-0000-FLD-60002-rev3` took noticeably longer than expected to return, consistent with per-file SSSD/LDAP owner-name lookups accumulating across the directory's contents. **Confirmed resolved after the `nsswitch.conf` fix above was applied.** This closes the gap flagged below (the original chroot-based `id`/`sed` check couldn't prove the fix worked against a live SSSD daemon) — it's now been proven against a real hang on real hardware, not just a file edit inside a chroot.

**Cross-reference, 2026-09-08: this hang does NOT reproduce on `baseos-1029-doca341` (`rack08node01`)**, despite `maxQ-1029-doca341` using the **same finalizescript** as `maxQ-1014-doca321` (confirmed separately — `/etc/hosts` on that node already correctly shows `127.0.1.1 rack08node01` via §8.9's finalize script). `time id 9999` / `time getent passwd 9999` both returned in ~1-4ms with correct "no such user" results — no delay at all. **Stronger, real-world confirmation of the same thing:** `/home/SIT/nvdiag/` on this node contains a file/directory pair (`629-24059-0000-FLD-60002-rev3`) owned by UID `604` — not a valid account on this system (resolves neither locally nor via LDAP). **Correction:** this content is not part of the `baseos-1029-doca341` image itself — confirmed via `ll /cm/images/baseos-1029-doca341/home/SIT/nvdiag/` on the head node, which shows only `629-24059-0000-FLD-60004-rev23` (owned `root:root`); the `60002-rev3` pair (owned `cmsupport:pega`, dated `Jun 29`) was evidently copied onto `rack08node01` manually, post-provisioning, likely by whoever's doing diag work on that node. The UID-`604`-doesn't-resolve fact and the no-hang observation on it both still stand as real, independent evidence — just via manually-placed content, not something the image itself ships with. Since the finalizescript (and whatever it configures) is shared between the two categories but the hang itself doesn't reproduce, the root cause is likely specific to `baseos-1014-doca321`'s actual image content (SSSD version/config or some cached state baked into that particular tarball) rather than anything the finalizescript sets up. Worth diffing the two images' SSSD packages/config directly next session — this may be a narrower bug than originally assumed, which also raises the question of why it's present in one image and not the other despite the shared finalize logic.

> ⚠️ **Recommended test UID: use `9999`, not `604`, if re-verifying this in the future.** UIDs in roughly the 100–999 range are conventionally reserved for system/service accounts, so a value like `604` risks *coincidentally* being a real, locally-resolvable UID on some systems — a poor choice for a "prove this ID is definitely unresolvable" test. A clearly-out-of-range value like `9999` is the safer convention for this kind of check:
> ```bash
> time id 9999
> time getent passwd 9999
> ```

**General caution for future verification of similar fixes, still worth keeping in mind:** don't trust a check run only inside `cm-chroot-sw-img` as proof a fix works — SSSD isn't an active running daemon inside a chroot (no live network/service context), so a fast result there only confirms a config file was edited, not that the real-world symptom is gone. Real verification needs a booted node with the relevant service actually running, as was ultimately done here.

**Same archive-vs-live-directory caveat as every other fix in this section:** this was applied via `cm-chroot-sw-img` directly against `/cm/images/baseos-1014-doca321` — per the pattern established in 6d/6g, `nsswitch.conf` (like the rest of the base distribution) reverts to Ubuntu's shipped default if the node/image is ever rebuilt from a fresh, unmodified `-a` extraction of `maxQ106-1014-doca321-baseos.tgz`. **To survive future re-tars and apply automatically to the remaining 7 racks, this same `sed` fix needs to be run once on `maxQ106` itself before the next archive capture** — same standing reminder as the fabricmanager mask (6k) and the missing `interfaces.d`/`ntpsec` directories (8.7). Worth doing all three in the same pass the next time `maxQ106` is re-tar'd, rather than three separate capture cycles.

### 6p. `/swap.img` sparse file inflated from 8.0K to 8.0GB during image capture — confirmed root cause, fix not yet applied

**Found via a `du -shc /*` comparison between `maxQ106` (29G total) and the built image `baseos-1014-doca321` (36G total) — the ~7G gap traces almost entirely to one file.**

On `maxQ106`:
```
8.0K -rw------- 1 root root 8.0G Jun 29 12:20 /swap.img
```
`ls -lsh` (`8.0K` actual disk blocks vs `8.0G` logical size) and `du --apparent-size` (reads `8.0G`, matching normal `du`'s `8.0K` only if sparse) **confirm `/swap.img` is a sparse file** on the source — a conventional way to create a swap file, where the filesystem allocates real disk blocks lazily as pages actually get written to swap, not upfront. On `maxQ106` it's essentially untouched (all logical zero-holes, ~8KB of real content).

Inside `/cm/images/baseos-1014-doca321/swap.img`, `du` reports a full, non-sparse **8.0GB** — meaning the archive-capture and/or `cm-create-image` extraction process **materialized every logical hole into real, physically-written zero bytes**, turning an 8KB-on-disk file into a genuinely 8GB-on-disk file. This is the single largest contributor to the size difference between the two `du` outputs — confirmed, not just theorized.

**Why this matters, beyond wasted disk space:**
- At 18 nodes/rack × 8 racks, an extra ~8GB of dead weight per image build (and per resulting PXE image sync to each node, if node-installer transfers this file) is a real, multiplied cost — both in `/cm/images` storage on the head node and in per-node provisioning time/network transfer.
- More importantly: **a compute node's swap should typically be created/sized by the node-installer itself at provisioning time**, not shipped pre-baked inside the image. A stale, image-baked 8GB swap file could be redundant with, or conflict with, whatever BCM's own per-node swap configuration does — worth confirming this file is even supposed to be part of the captured image at all, separate from the size-inflation problem.

**Root cause, not yet fully pinned down but strongly suspected:** `tar` does not preserve sparseness on extraction unless invoked with a sparse-aware flag (commonly `--sparse`/`-S` for GNU tar). If the archive itself was captured without sparse-preserving options (`tar -S` on creation) and/or `cm-create-image`'s internal extraction doesn't pass an equivalent flag on unpack, a sparse file crossing that round-trip predictably inflates to its full logical size. `cm-create-image --help` exposes a `--tar-options ...` flag specifically for passing extra options to the extraction step — worth checking whether `--sparse` needs to be added there, or whether the fix actually belongs on the archive-creation side (on `maxQ106`, whatever process built `maxQ106-1014-doca321-baseos.tgz` in the first place).

**Status: root cause confirmed via direct measurement. Fix not yet identified or applied.** Next steps:
```bash
# Check whether the archive itself already lost sparseness (would mean the fix belongs
# at archive-creation time on maxQ106, not at cm-create-image's extraction step)
tar -tvf /root/pre-built-images/maxQ106-1014-doca321-baseos.tgz swap.img
du -h --apparent-size <(tar -xOf /root/pre-built-images/maxQ106-1014-doca321-baseos.tgz swap.img) 2>/dev/null

# If cm-create-image's own extraction is the culprit, --tar-options may be the fix on the next build:
cm-create-image -a ... --tar-options --sparse ...
```
Simplest possible interim workaround, independent of root-causing the tar behavior: just exclude `/swap.img` from the image entirely via `-o <exclude-file>`/rsync-format exclude pattern (per `cm-create-image --help`'s `-o`/`--exclude-from` flag), since swap is arguably not something that belongs in a captured golden image regardless of the sparse-file issue — worth deciding which approach is preferred before the next build.

---

## 7. Scaling Context (for future sessions)

- Eventual target: **8 racks × 18 nodes = 144 nodes total**, deployed via a "cascade thru layers of switches" topology — exact network topology (flat vs. per-rack jump host vs. multi-hop) **not yet determined**, pending discussion with user's diag team.
- Team preference: **plain bash scripts, not Ansible** — despite `maxQ106` already having `.ansible/`/`hosts.ini`/`CX8_BF3_config.yml` present (used for BF3/CX8 config, not adopted for this upgrade workflow by team preference).
- Proposed (not yet built) orchestration design: separate `node-agent.sh` (the current `l10-upgrade.sh`) + a `cascade-orchestrator.sh` doing canary-first rollout (1 node → gate → 1 per rack → gate → remaining fleet), concurrency-throttled SSH, centralized result aggregation. **Blocked on topology info from team.**

---

## 8. SOP — BCM Software Image Build (for the remaining 7 racks)

Consolidated, ordered command sequence distilled from Section 6's debugging (6a–6k). Run this straight through for each new rack's image build rather than re-deriving it from the narrative sections above.

### 8.1 Teardown any prior attempt (if rebuilding, not first build)

```bash
cmsh -c "softwareimage; remove <image-name>; commit"
rm -rf /cm/images/<image-name>
```

### 8.2 Build from archive

```bash
cm-create-image -a /root/bcm-image-export/<source-archive>.tgz \
  -n <image-name> \
  --dgx-type dgx_gb300 \
  -s \
  --no-cm-cuda-repo
```

**⚠️ Caveat added 2026-09-08, not yet resolved — verify before relying on this step as written for the next rack build.** `--no-cm-cuda-repo` was correct when this SOP was written (successful `baseos-1014-doca321` build, 2026-08-24), but a separate, parallel image build (`baseos-1029-doca341`, same head node, same `UBUNTU2404-dist-extrapackages.xml` package list) run today needed the CUDA network repo *enabled* to successfully install the `nvidia-open-580`/`nvidia-imex`/`nvidia-kernel-common-580`/etc. entries from that same file — without it, those packages come back "Unable to locate package" and are silently skipped rather than failing the build.

**Working hypothesis, not confirmed:** `maxQ106`'s validated driver (`580.126.20`, DOCA 3.2.1) is already present in the source tarball via the original `.run`-installer bring-up — this build step was very likely trying to additionally install `580.173.02` (the next-gen, 2.0.0-era driver from §3's staged artifacts) as an "extra" package, unrelated to the image's actual working driver. If that install silently failed in the original August build too, it wouldn't have caused a visible problem, since the image never depended on it succeeding — but this has **not** been confirmed against the original build log, which wasn't available to check this session.

**Before the next rack build, verify directly rather than assuming either way:**
```bash
cm-chroot-sw-img /cm/images/<image-name>
apt-cache policy nvidia-open-580 nvidia-imex nvidia-kernel-common-580
dpkg -l | grep -E "nvidia-open-580|nvidia-imex|nvidia-kernel-common-580"
exit
```
If none of these are installed and that's expected (because `580.126.20` is the intended driver and `580.173.02` genuinely isn't needed yet), `--no-cm-cuda-repo` is fine as-is — no change needed. If any of the 2.0.0-era `.run`-staged driver components are actually expected to come from this apt-based step (rather than purely from the staged `.run` files in §3), the flag needs to be dropped, matching what today's `baseos-1029-doca341` build required — see the parallel `gb300_l10_build_log.md` §25b for the version-pinning issues that come with turning the repo back on (unpinned installs there drifted to `580.178.04` instead of the intended `580.173.02`).


⚠️ **`--dgx-type dgx_gb300` shown here as the current default for copy-paste, matching what `baseos-1014-doca321` was most recently built with — but this is not yet NV-confirmed as correct for this hardware (see 6l).** Double-check 6l/Section 4 item 2 before running this on a new rack in case NV's answer has landed since this doc was last updated; if NV instead confirms `dgx_gb200`, update this value accordingly before building the remaining racks.

Expect this to take up to ~8.5 hours end-to-end (6i) — dominated by two redundant DKMS/OFED build cycles against an irrelevant `6.8.0-106-generic-64k` kernel that "Installing CM packages" installs by name regardless of `-s`. This is currently accepted as a known, reproducible cost, not a failure — do not interrupt the build on this basis. If a real NV/BCM support report is wanted, check `/var/log/apt/history.log` inside the image afterward (6i) to pin the exact package-disposal mechanism first.

### 8.3 Fix: fabricmanager finalize failure (check archive first — may already be resolved)

**Check before doing anything:** if using the updated reference archive (confirm which `.tgz` path is current — the masked-override fix may already be baked in, see 6k), verify first:

```bash
cm-chroot-sw-img /cm/images/<image-name>
ls -la /etc/systemd/system/nvidia-fabricmanager.service
exit
```

If that shows `... -> /dev/null`, the finalize step will succeed on its own — skip the rest of this step. (Don't rely on `dpkg -l nvidia-fabricmanager-580` to check this — it may show `un`/not-installed even when the mask override is correctly in place; see 6k.)

**If the override is absent** (i.e. building from the original, unmodified archive), the finalize step will fail as in 6d — apply the manual fix:

```bash
cm-chroot-sw-img /cm/images/<image-name>
chmod 1777 /tmp && rm -rf /tmp/*
apt-get update && apt-get install -y nvidia-fabricmanager-580
systemctl mask nvidia-fabricmanager      # NOT just disable — see 6k. NEVER purge this package.
ls -la /etc/systemd/system/nvidia-fabricmanager.service   # confirm -> /dev/null (systemctl status won't work in this chroot — no PID 1/D-Bus)
exit
```

### 8.4 Clean up chroot mounts (mandatory before any further host-side command)

```bash
for m in dev/pts dev proc sys run/systemd/resolve/resolv.conf run; do
  umount -l "/cm/images/<image-name>/$m" 2>/dev/null
done
grep "/cm/images/<image-name>/" /proc/mounts   # must return nothing before proceeding
```

### 8.5 Cosmetic cleanup (optional, safe)

```bash
cm-chroot-sw-img /cm/images/<image-name>
apt-get autoremove -y                                    # clears orphaned prior-kernel companion packages
rm -f /boot/initrd.img-6.8.0-106-generic 2>/dev/null      # if present — stray, unbootable, harmless (see 6h/6i investigation)
exit
```

Repeat step 8.4 (mount cleanup) again after this chroot session too.

### 8.6 Commit the finalized image

```bash
cm-create-image -d /cm/images/<image-name> -n <image-name> -s --no-cm-cuda-repo
```

### 8.7 Pre-provisioning check: missing config directories (`interfaces.d/`, `ntpsec/`)

**New finding (rack00, first real PXE/node-installer run against `baseos-1014-doca321`):** the node-installer's `open()` calls for generating per-node config — the network interface file (`interfaces.d/ifcfg-<iface>`) and NTP config (`ntpsec/ntp.conf`) — fail with a fatal error if their **target directories** don't exist inside the image, even though the files themselves are meant to be generated fresh per node. This is a directory-existence problem, not a missing-package problem — confirmed by checking directly inside the image:

```bash
cm-chroot-sw-img /cm/images/<image-name>
ls -la /etc/network/interfaces.d/ 2>&1
ls -la /etc/ntpsec/ 2>&1
exit
```

If either reports "No such file or directory," create them before the first PXE boot against this image:

```bash
mkdir -p /cm/images/<image-name>/etc/network/interfaces.d
mkdir -p /cm/images/<image-name>/etc/ntpsec
```

**Known limitation of this fix as written:** applied directly to the live `/cm/images/<image-name>` directory, so it survives future `-d` resumes against this same directory but **will not survive a fresh `-a` rebuild from the source archive** — it isn't baked into the `.tgz`. Until/unless this is fixed at the archive level (same pattern as the fabricmanager masked-override fix in 6k), re-apply this `mkdir -p` step after any full from-archive rebuild, and check for it explicitly on each of the remaining 7 racks rather than assuming a prior rack's fix carried over.

**Root cause, not yet fully confirmed:** most likely these directories are normally created as a side effect of installing whatever package owns them (e.g. `ntpsec`'s own package normally creates `/etc/ntpsec/` even before its config is populated) — and something in the "Installing CM packages" stage's package exclusion logic (per the `extradist: Added ... to exclude dist list` lines seen in 6i's log investigation) may be stripping that package, or installing it in a way that skips directory creation. Worth confirming with `dpkg -L ntpsec 2>/dev/null | grep /etc/ntpsec` inside the chroot if a permanent, archive-level fix is pursued later — not required to unblock provisioning now.

After creating the directories, reboot the affected node via IPMI/PXE to re-trigger provisioning — the installer should now write both config files without the fatal error. **Confirm this actually completes cleanly before treating it as resolved** — check the node's post-boot status in `cmsh`/Base View and, if possible, confirm the two generated files exist on the node itself (`ifcfg-<iface>` under `interfaces.d/`, populated `ntp.conf` under `ntpsec/`), rather than assuming success from the reboot alone.

**⚠️ Reminder — bake this into the reference archive (`maxQ106`), same precedent as the fabricmanager mask (6k):** the `mkdir -p` above only fixes the current, already-extracted `/cm/images/<image-name>` directory. It will not survive a fresh `-a` rebuild from `maxQ106-1014-doca321-baseos.tgz`, and it does nothing at all for the other 7 racks' images until each one is separately patched or rebuilt from a corrected archive. **Before the next re-tar of `maxQ106`, add these two directories directly on the reference host itself:**

```bash
# run on maxQ106, before capturing/re-taring the reference layout
sudo mkdir -p /etc/network/interfaces.d
sudo mkdir -p /etc/ntpsec
```

Once captured into the archive this way, every future `-a` build (this rack's next rebuild and all 7 remaining racks) gets these directories automatically, with no per-image manual step needed — exactly how the fabricmanager masked-unit override became permanent once it was captured into the archive rather than reapplied via chroot on every build. Track this alongside the fabricmanager fix as one of the standing "things the next `maxQ106` re-tar should include."

### 8.8 — REMOVED FROM SOP: `nsswitch.conf` SSSD-hang fix (was here, confirmed regression, do not apply)

**This step is intentionally no longer part of the SOP.** The `files`-only `nsswitch.conf` override previously documented here was confirmed (2026-09-08, `rack01node18`, real-node `latesthealthdata`) to break `cmsupport` account resolution — `ldap` health check fails with `id: 'cmsupport': no such user`. Do not apply the old `sed` fix to any further racks, and do not bake it into `maxQ106`.

The underlying problem it was trying to solve (`ls -l`/`id` hanging on unresolvable UIDs due to SSSD/LDAP lookup timeout) is real and independently confirmed on real hardware — see 6o for the full symptom writeup. A revised fix (tuning SSSD's negative-cache/timeout instead of removing LDAP from the chain, or explicitly allow-listing only the accounts that genuinely don't need LDAP) still needs to be designed and validated before anything is added back here. Track status in the "Still-open, non-blocking items" list, not as an SOP step, until a non-regressing fix exists.

### 8.9 ✅ RESOLVED: `127.0.1.1 <hostname>` fix for `BF3PcieInterfaceTraffic` partnerdiag failure — SOP step (2026-09-04)

The original candidate (`echo "127.0.1.1   #HOSTNAME#" > /cm/images/<image-name>/etc/hosts.suffix`) is **confirmed not a real BCM mechanism** — node-installer never reads or merges a `.suffix` file when generating `/etc/hosts`, and `#HOSTNAME#` is not a real substitution token. Full investigation and root-cause trail in 6n.

**Actual SOP step, verified working on a full 18-node rack01 redeploy:**

1. Save the finalize script at `/cm/local/apps/cmd/etc/htdocs/scripts/finalize/finalize-hosts-127-v3.sh` (this is a real, cmsh-recognized directory for authored finalize/initialize scripts, confirmed alongside BCM's own shipped examples — `ls` it to confirm before assuming the path on a different cluster/BCM version).
2. Apply it to the target category:
   ```
   cmsh
   % category use <category-name>
   % set finalizescript finalize-hosts-127-v3.sh
   % commit
   ```
3. The script itself writes to `/localdisk/etc/hosts` (not `/etc/hosts`) — this is the critical detail. Per BCM's own shipped `log_available_environment_variables.sh` example: *"The root / of the running node is always mounted on /localdisk"* during the finalize stage, so anything writing to `/etc/hosts` at this point hits the ramdisk's throwaway copy, not the file that survives onto the booted node. This was the actual root cause of the original fix never taking effect on the first working attempt (v1) — confirmed directly via node-installer log showing the script reporting success while the target node's booted `/etc/hosts` never showed the entry.

**Verified 2026-09-04**, all spot-checked nodes on a fresh rack01 (18× L10) redeploy show their own correct `127.0.1.1 <hostname>` entry, no cross-contamination between nodes.

**Still not confirmed:** whether this actually resolves `BF3PcieInterfaceTraffic` partnerdiag — the `/etc/hosts`-content theory for that failure has never been independently verified, only assumed from how the fix was originally framed. **Re-run partnerdiag on a rack01 node with this fix applied before treating the original problem as closed, not just the delivery mechanism.**

**Same archive-baking reminder as 8.7:** if partnerdiag confirms this actually fixes the failure, bake the finalize-script assignment into the `maxQ106` reference build process so it's automatic for all remaining racks, rather than a manual per-category `cmsh` step applied ad hoc.


### 8.10 Fix: `Missing device. Node Installer will halt.` (`missing device assert`) — category `disksetup` was unset

**Symptom, confirmed via node-installer console screenshot:**
```
Finished setting up the network.
Installmode is: FULL
Setting up environment for initialize scripts.
Fetching RAID setup.
Fetching disks setup.
Creating new disk layout.
Missing device.  Node Installer will halt.
More details are in the log file.

There was a fatal problem. This node can not be installed
until the problem is corrected.
You can switch to a shell using Alt << F2-F12.

The error was: missing device assert
```
Halts during the "Fetching disks setup" / "Creating new disk layout" stage — **before** node-installer ever gets to checking partition sizes, so this is not a disk-capacity issue despite the superficially similar "disk" framing. It's node-installer failing to resolve a target block device to partition at all.

**Fix: set (or re-confirm) the category's `disksetup` property** with a valid disk-setup XML:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<diskSetup>
    <device>
        <blockdev>/dev/nvme0n1</blockdev>
        <partition id="efi" partitiontype="esp">
            <size>100M</size>
            <type>linux</type>
            <filesystem>fat</filesystem>
            <mountPoint>/boot/efi</mountPoint>
            <mountOptions>defaults,noatime,nodiratime</mountOptions>
        </partition>
        <partition id="boot1">
            <size>4G</size>
            <type>linux</type>
            <filesystem>ext2</filesystem>
            <mountPoint>/boot</mountPoint>
            <mountOptions>defaults,noatime,nodiratime</mountOptions>
        </partition>
        <partition id="slash1">
            <size>max</size>
            <type>linux</type>
            <filesystem>ext4</filesystem>
            <mountPoint>/</mountPoint>
            <mountOptions>defaults,noatime,nodiratime</mountOptions>
        </partition>
    </device>
</diskSetup>
```
Same three-partition layout already validated against `carlonext`'s live disk (efi/boot/root, no swap defined — consistent with the swap-removal decision in the earlier disk-cleanup pass). Apply via `cmsh` (exact set syntax not yet confirmed against a file-based method the way `finalizescript`'s directory-file lookup was — likely requires editing via the interactive `set disksetup` editor, or loading one of the shipped templates from `/cm/local/apps/cmd/etc/htdocs/disk-setup/` if one matches):
```
cmsh
% category use maxQ-1014-doca321
% set disksetup
```
(paste the XML above, save, exit)
```
% commit
```

**Root cause: not fully confirmed, but strongly suspected to be an unset/empty `disksetup` property, not a content problem.** The XML applied is byte-for-byte identical to what was already reviewed and validated for this same category earlier in this session — so this almost certainly wasn't a wrong-`blockdev`-name or wrong-partition-scheme fix. The more likely explanation: the category's `disksetup` was empty/unset at the time of the halt (node-installer had nothing to target a device with, hence "missing device assert"), and simply setting *any* valid layout — even one identical to what had been reviewed before — gave it something to work from for the first time. **Not independently confirmed** — would need the pre-fix `get disksetup` output (empty vs. populated) to know for certain, which wasn't captured before the change was made.

**Validated:** confirmed working after this was applied and rack01 (18× L10 nodes) was redeployed — no further "missing device assert" halts observed on that run. Not confirmed whether this reproduces/was present on rack08 as well, or whether rack08 has its own independent history with this setting.

**Before repeating on rack08 or any further rack:** confirm this category's `disksetup` is populated (`cmsh -c "category use <category>; get disksetup"`) as a pre-provisioning check, the same way 8.7's missing-directories check and 8.3's fabricmanager-mask check are done before assigning nodes — add this to the pre-flight checklist for all remaining racks rather than only discovering it via a live halt during provisioning.


### 8.11 Verify before trusting the image

```bash
cm-chroot-sw-img /cm/images/<image-name>

# Kernel state — expect ONLY the target kernel, no stray 6.8.0-106-generic-64k
dpkg -l | grep -E "^[hi]i.*linux-(image|modules|headers)"
ls -la /boot/vmlinuz* /boot/initrd*

# DOCA/driver/IMEX integrity — expect Installed == Candidate, no unexpected upgrades
dkms status
apt-cache policy doca-host mlnx-ofed-kernel nvidia-imex-580

# fabricmanager — check the masked-override symlink directly; systemctl status
# does NOT work inside cm-chroot-sw-img (no PID 1/D-Bus, see 6k)
ls -la /etc/systemd/system/nvidia-fabricmanager.service   # expect -> /dev/null

# config directories that must exist before first PXE boot (8.7)
ls -la /etc/network/interfaces.d/ /etc/ntpsec/

# nsswitch.conf — confirm the SSSD-hang override from the old 8.8 is NOT present
# (that fix was removed from the SOP — confirmed regression, see 8.8/6o).
# Expect the default Ubuntu/SSSD-backed lines here, NOT 'files' on all three.
grep -E "^(passwd|group|netgroup):" /etc/nsswitch.conf

# chrony (8.13) — expect installed, enabled, not systemd-timesyncd
dpkg -l | grep -i -E "^ii\s+(ntp|chrony)"
systemctl is-enabled chrony
systemctl is-enabled systemd-timesyncd   # expect 'not-found' or 'masked', not 'enabled'

exit
```

```bash
cmsh -c "softwareimage; list"    # confirm image registered with correct kernel version and path
```

Do **not** treat `/cm/images/<image-name>/boot/grub/grub.cfg` (checked from the head node) as a validation signal either way — BCM's node-installer regenerates real bootloader config on each node's own disk during provisioning; this file is not authoritative (see 6f).

### 8.12 Known-acceptable states (don't re-debug these on future racks)

| Symptom | Verdict |
|---|---|
| `cm-create-image` build takes several hours, mostly "stuck" on "Installing CM packages" | Expected — DKMS/OFED build against throwaway `6.8.0-106` kernel (6i). Not a hang. |
| Image's own `/boot/grub/grub.cfg` has no real kernel `menuentry` | Expected — node-installer doesn't use this file (6f). |
| `Setting up`/`Removing` never logged for `linux-image/modules/tools-6.8.0-106*`, yet `dpkg -l` shows them absent afterward | Reproduces reliably; end state confirmed correct even though exact log mechanism is unresolved (6i). Not a blocker. |
| `Finalizing cluster services` logs a `systemctl disable <service>` failure (e.g. bind9) for a service that was never installed | Non-fatal, build continues (6j) — different from the fabricmanager case in `Finalizing image services`, which **is** fatal (6d). |
| `nvidia-fabricmanager-580` version doesn't match the DKMS-built driver version | Irrelevant — package is masked and never runs on the compute host; real FM runs off-host on the NVSwitch tray (6d/6k). |
| `cm-chroot-sw-img` reports `dev`/`proc`/`sys`/`run`/`run/systemd/resolve/resolv.conf`/`dev/pts` "already mounted" on entry | Expected if step 8.4 wasn't run after the previous session — run it, don't ignore the warning (6h). |
| Per-session `/var/tmp/<random>` tmpfs (apt scratch dir) still mounted after chroot exit, `umount` reports "target is busy" | Same category as the row above — exit doesn't always fully unmount. Check `fuser -vm <path>` before forcing; low-risk to leave if nothing obviously wrong holds it, doesn't affect image content (2026-09-08). |
| A provisioned node's `/home` contains files/dirs not present in the source image on the head node | Not a provisioning bug — `excludelistupdate` includes `/home/*` for these categories, so update-style (non-`FULL`) installs deliberately never touch `/home`, leaving whatever was already there from a prior provisioning cycle untouched. Confirmed via `cmsh -c "category use <category>; get excludelistupdate"` (2026-09-08). Don't use `/home` contents on a live node as evidence of what the current image ships — check the image directly on the head node instead. |
| `Validating repo configuration` fails with `Failure getting installed package list` / `Failed to install packages`, **regardless of `--dgx-type`** | Check the head node's own `ls -la /dev/null` first (6m) before assuming a repo conflict (6e) — this exact on-screen failure has two known, unrelated root causes and doesn't distinguish them. If `/dev` is missing core nodes, that's a host-level incident, not fixable by changing `cm-create-image` flags. |
| PXE node-installer fails fatally trying to write `interfaces.d/ifcfg-<iface>` or `ntpsec/ntp.conf` during first boot against a new image | Not a package or `ifupdown`/Netplan problem — the target directories (`/etc/network/interfaces.d/`, `/etc/ntpsec/`) don't exist in the image. Fix at the image level per 8.7, not on the node. Doesn't survive a fresh `-a` rebuild — check for it on every rack, not just the first. |
| PXE node-installer halts with `Missing device. Node Installer will halt.` / `The error was: missing device assert` during "Fetching disks setup" | Not a disk-capacity problem — happens before partition sizes are even checked. Category `disksetup` likely unset. Fix per 8.10; add a pre-flight `get disksetup` check for every remaining rack. |

### 8.13 Fix: `ntp` health check FAIL — `chrony` not installed on the image

**Root cause, confirmed on `rack01node01`:** `dpkg -l | grep -i -E "^ii\s+(ntp|chrony)"` returns nothing — neither package is present on the image at all. `systemd-timesyncd` IS installed but ships `disabled` (matches the pattern already seen with `shorewall`/`shorewall6`/`auditd` being explicitly disabled during finalize — looks like the same class of intentional image hardening, just missing a replacement time-sync mechanism).

**Also confirmed: setting the category's `timeservers` field does NOT wire up persistent time sync.** `journalctl -u systemd-timesyncd` showed zero entries after setting `timeservers 10.141.255.254` and a full reinstall — the field appears to only feed node-installer's one-shot provisioning-time sync (`ntpd -c /tmp/ntp.conf -q -g`, visible in the node-installer log), not any persistent post-boot service. Do not rely on this field alone for ongoing clock sync.

**Health check specifically greps for `ntpd`/`chronyd` by process name** (`"ntpd or chronyd process is not running"`) — `systemd-timesyncd`, even if manually enabled, is very unlikely to satisfy this check. `chrony` is the correct target, not `timesyncd`.

**Fix — same `cm-chroot-sw-img` pattern as 8.3, apply once to the reference image, not per-node:**

```bash
cm-chroot-sw-img /cm/images/<image-name>
apt-get update && apt-get install -y chrony
systemctl disable systemd-timesyncd
systemctl mask systemd-timesyncd
systemctl enable chrony
```

Then point chrony at the head node as the internal time source — edit `/etc/chrony/chrony.conf` inside the chroot, replacing the default `pool ntp.ubuntu.com` / `pool 2.ubuntu.pool.ntp.org` lines with:
```
server 10.141.255.254 iburst
```
(confirmed reachable from `rack01node01` — `ping 10.141.255.254` succeeds with ~0.6-1.7ms latency; also confirmed this node DOES have outbound internet reachability via `ping 8.8.8.8`, which was unexpected — worth deciding deliberately whether internal-only or a public pool as fallback is the intended design, rather than defaulting to whatever chrony ships with)

```bash
exit
```

Then run 8.4 (mount cleanup — mandatory), optionally 8.5, then 8.6 to commit.

**Not yet validated end-to-end** — this is a drafted fix based on confirmed root-cause findings (missing package, `timeservers` field's actual scope, health check's exact wording), not yet applied to the image or re-tested via a fresh reinstall + `latesthealthdata`. **Before treating this as resolved:**
1. Apply to `<image-name>` via the steps above.
2. Reinstall `rack01node01` (`set installmode FULL` at the device level, as done for the disk-setup/finalize-script tests, then `ssh rack01node01 reboot`).
3. Confirm: `dpkg -l | grep chrony`, `systemctl status chrony`, `chronyc sources` (should show `10.141.255.254` reachable/synced).
4. Confirm the health check itself flips to PASS: `cmsh -c "device use rack01node01; latesthealthdata"`.
5. Same archive-baking reminder as every other 8.x fix: apply once on the reference image before the next re-tar, not per-rack.

**Still open, unrelated to this fix, surfaced by the same health-check run:**
- `ldap` FAIL (`id: 'cmsupport': no such user`) — **confirmed** direct regression from the old 8.8 `nsswitch.conf` fix (now removed from the SOP — see 8.8 and "Still-open, non-blocking items" for full detail and candidate revised fixes). Not an open question anymore; a non-regressing replacement fix is what's still needed.
- `gpu_health_overall` FAIL despite all four per-GPU sub-checks (`gpu0`-`gpu3`) showing PASS — cause not yet identified, worth pulling the detailed reason via cmsh rather than assuming it's transient.


---

## 9. Addendum — `baseos-1032-doca341` build session (2026-09-16)

**Context:** first production run of the SOP in Section 8 against a new reference archive, `maxQ20GA-1032-doca341-baseos.tgz` (kernel `6.17.0-1032-nvidia-64k`, DOCA `3.4.1-010000`) — the first DOCA 3.4.1-line archive to go through this SOP for real, as opposed to the 3.2.1-line `maxQ106` archive Section 8 was originally written against. Findings below are new information this archive surfaced; where they contradict or add nuance to Section 6/8, this section is authoritative until merged back.

**Path correction:** reference archives on this head node live at `/root/pre-built-images/`, not `/root/bcm-image-export/` as Section 6 assumed. Confirm actual path per-site before following Section 6/8 literally.

### 9a. Duplicate CUDA repo conflict — confirmed reproducible on this archive, and confirmed NOT fixable by chroot edit alone

Building `baseos-1032-doca341` **without** `--no-cm-cuda-repo` fails at "Validating repo configuration" → `Failure getting installed package list`, identically to the `6e` finding on `maxQ106`/`1014`-doca321: `cm-cuda-ubuntu2404-sbsa.list` and `cuda-ubuntu2404-sbsa.list` both present, `Signed-By` conflict on the same CUDA sbsa URL.

**Confirmed reproducible** across two independent from-archive builds (including a full teardown + `rm -rf` + fresh `-a`), not a one-off.

**New finding, not previously documented:** removing the duplicate `.list` file via `cm-chroot-sw-img` and then resuming with `cm-create-image -d ...` did **not** survive — the build failed at the identical "Validating repo configuration" step again on resume. `apt list --installed` was confirmed clean (no `Signed-By` error) immediately before the resume, so the file was correctly removed; something in the resume path (most likely "Copying cm repo files," which is confirmed to run again on `-d` resume — see 6h/8.6 for the general pattern of this stage re-running) appears to re-inject the BCM `cm-cuda-...` file before validation runs. **Not root-caused — worth confirming directly next session** (diff `/etc/apt/sources.list.d/` immediately before and after a `-d` resume's "Copying cm repo files" stage to catch it in the act).

**Working fix for this archive:** build with `--no-cm-cuda-repo` from the start rather than removing-and-resuming. Confirmed to avoid the conflict entirely (see 9b) — the CUDA sbsa repo itself remains enabled and functional (`apt-cache policy` still shows real candidates from `developer.download.nvidia.com`), only the conflicting BCM-injected duplicate is avoided.

**Open question:** whether `--no-cm-cuda-repo` is *why* the duplicate is never injected (i.e. it's the correct standing fix), or whether it's coincidental and the real fix is elsewhere (e.g. a "Copying cm repo files" bug that only manifests when the CUDA network repo is otherwise enabled). Treat `--no-cm-cuda-repo` as the working answer for this archive until proven otherwise, but don't assume it explains the mechanism.

### 9b. `--no-cm-cuda-repo` validated as safe for this archive — driver ships pre-baked, not via apt

Per the `6l`/8.2 caveat (this flag previously caused `nvidia-open-580`/`nvidia-imex`/`nvidia-kernel-common-580` to be silently skipped on a *different* build), this was checked directly rather than assumed:

```bash
cm-chroot-sw-img /cm/images/baseos-1032-doca341
apt-cache policy nvidia-open-580 nvidia-imex nvidia-kernel-common-580   # all "Installed: (none)" — expected here
dkms status                                                              # nvidia/580.173.10 installed, full OFED stack installed, against 6.17.0-1032
dpkg -l | grep -iE "nvidia|doca-host|mlnx-ofed"                          # doca-host 3.4.1-010000 present
exit
```

**Result: benign.** The working driver (`580.173.10`) and full DOCA 3.4.1 stack are already present and correctly built via DKMS against the image's actual kernel — the archive ships its own driver, matching the pattern already established for `maxQ106`. The apt packages showing "not installed" is expected here, not the silent-skip failure. **Lesson for future archives: `apt-cache policy` alone cannot distinguish "flag skipped something needed" from "driver was never meant to come from here" — always cross-check with `dkms status` + `dpkg -l` for the actual driver/DOCA packages before trusting either flag setting on a new archive.**

**Cosmetic-only finding:** the `xpmem` package version string read `2604.0.2-1.kver.6.17.0-1029-nvidia-64k` — referencing kernel `1029`, not this image's actual `1032`. `dkms status` confirmed the real module is correctly built against `1032`; this is stale package-naming metadata only, same category as the known `nvidia-fabricmanager` version-string mismatch in `6k`. Not a defect, not investigated further.

### 9c. Fabric Manager mask — already baked into this archive

```bash
ls -la /etc/systemd/system/nvidia-fabricmanager.service
# -> /dev/null, dated Sep 14 15:41
```
Confirmed already present without any manual chroot intervention — this archive's source tarball already carries the masked-unit override, same as the updated `maxQ106` archive per `6k`'s "UPDATE 2026-08-25" note. No action needed for this or future builds from this same archive.

`nvidia-fabricmanager` itself shows as **installed** (`hi`, version `580.173.10-1ubuntu1`) despite being masked — consistent with `6k`'s finding that the package can be present and masked simultaneously with no functional issue; don't treat the installed-and-masked combination as contradictory.

### 9d. New evidence for the open `dgx_gb200` vs `dgx_gb300` question

Near the end of a successful `dgx_gb300` build, this non-fatal warning appeared:
```
running command: '.../bcm-dgx-software-image-kernel-param-syncer --dgx-platform dgx_gb300 --show-only ...'
E | Unable to determine the correct method for collecting kernel parameters. Exiting!
```
This did not fail the build (logged as an error, build proceeded to `[OK]`). Notable because this tool's job — "obtain proper kernel parameters" — is exactly what `--dgx-type`'s own `--help` text says the flag controls. This is new, direct evidence relevant to the still-open `6l` question (which `--dgx-type` value is actually correct for GB300 NVL hardware) and should be included in the NV escalation report (Section 5) alongside the existing open questions. Does not resolve the question on its own — worth asking NV specifically why this tool can't determine a method under `dgx_gb300`.

### 9e. Session outcome

`baseos-1032-doca341` built successfully end-to-end with `--dgx-type dgx_gb300 -s --no-cm-cuda-repo`. Bind9/slapd non-fatal finalize messages reproduced as expected (`6j` pattern), no new variant. Image not yet assigned to a category or provisioned to nodes as of this writing — Section 2 (SOP) pre-provisioning checks are the next step.

**Still open / carried forward, not resolved by this session:**
- Section 9a's resume-doesn't-stick mechanism (why "Copying cm repo files" appears to re-add the duplicate on `-d` resume).
- Whether `--no-cm-cuda-repo` is required by mechanism or coincidence for this archive.
- The `dgx_gb200`/`dgx_gb300` correctness question — now has one more data point (9d), still not NV-confirmed.
- Section 4's Phase 1/2 blocking items (ntp/chrony, ldap/nsswitch regression, swap.img) — not touched this session, still open exactly as documented there.

### 9f. SOP correction: `-d` commit step is not part of the standard path

Re-reviewing the successful `baseos-1032-doca341` build log (9e): `cm-create-image -a ... -s --no-cm-cuda-repo` completed **all** stages through "Adding/Updating software image" in a single invocation — no chroot session, no `-d` resume was used or needed. The SOP's Section 1.4 (`cm-create-image -d ... -n ... -s ...`) had been written as an unconditional standard step, inherited from the `maxQ106` narrative in Section 6 where a `-d` resume genuinely was needed (after the 6d/6e manual chroot fixes). That precondition no longer applies now that the standard `--no-cm-cuda-repo` path avoids those fixes entirely (9a/9b).

**Correction:** treat `-d` commit as conditional, not routine — only needed if a chroot session actually modified the image (a fix was applied). Running it unconditionally on an already-complete image re-triggers "Installing CM packages" and the rest of the pipeline for no reason, costing time and risking hitting a new problem on an image that was already good. The verification chroot session (dkms status / dpkg checks, no writes) does **not** require a commit afterward — only the mandatory mount cleanup (`umount -l` loop), since it did open `/dev`/`/proc`/`/sys` bind mounts even though it made no changes.

### 9g. Pre-provisioning check 2.1 — already satisfied on this archive

`/etc/network/interfaces.d/` and `/etc/ntpsec/` are both already present (empty, dated Aug 26 18:06) on `baseos-1032-doca341` — no `mkdir -p` fix needed for this archive, unlike the original `maxQ106`/`1014`-doca321 archive where 6/8.7 found them missing. Consistent with 9c/9f: `maxQ20GA`-line archives appear to have several of the manual `maxQ106`-era fixes already baked in upstream. Don't assume this holds for a future archive without checking — verify per-archive as the SOP's Section 2.1 already directs.

### 9h. SOP gap: category creation was never a documented step

Reached Section 2 (pre-provisioning checks) for `baseos-1032-doca341` and found no BCM category exists yet for this rack/archive line — Section 2's `cmsh -c "category use <category-name>; get ..."` checks all assume the category is already there, true for the original `maxQ106`/`maxQ-1014-doca321` work but never explicit as a prerequisite. Added as new Section 2.0 to the SOP (`cmsh` → `category` → `add <category-name>` → `commit`).

**Follow-on for this rack:** since the category is new, Section 2.1–2.3 won't be "verify existing config" checks — `disksetup` and `finalizescript` will need to be set for the first time, not confirmed. Expect this on any brand-new category, not just this one. Category name used for this rack: **[fill in once chosen]**.

### 9i. Category setup — cloned from `maxQ-1029-doca341`, not built from scratch

For `baseos-1032-doca341`, cloned the existing `maxQ-1029-doca341` category rather than building a new one from blank (see 9h) — faster and avoids retyping the validated `disksetup` XML:

```bash
cmsh
% category
% clone maxQ-1029-doca341 maxQ-1032-doca341
% commit
% category use maxQ-1032-doca341
% set softwareimage baseos-1032-doca341
% commit
```

**Confirmed via `get disksetup` / `get finalizescript` / `get softwareimage` after cloning:**
- `disksetup` carried over correctly — same validated 3-partition layout (`efi`/`boot1`/`slash1` on `/dev/nvme0n1`) already in use on `maxQ-1029-doca341` and `maxQ-1014-doca321`.
- `finalizescript` carried over correctly — the v3 hostname fix (writes to `/localdisk/etc/hosts`, matches `CMD_HOSTNAME`/`hostname` fallback, idempotent). Confirms the v3 script is now standard practice across at least two categories, not a one-off applied only to `maxQ-1014-doca321`.
- `softwareimage` correctly repointed to `baseos-1032-doca341` after the explicit `set` — cloning does **not** auto-update this, has to be set manually per new image.

**Note for the SOP:** cloning an existing, known-good category (rather than Section 2.0's blank `add`) is the preferred path whenever a suitable source category already exists — only `softwareimage` needs changing afterward. Blank `add` + manual `disksetup`/`finalizescript` should be reserved for the first-ever category on a cluster with no prior validated example to clone from.

Category name for this rack, for reference: **`maxQ-1032-doca341`**.

### 9j. Image verification (Section 4 checklist) — confirmed clean on `baseos-1032-doca341`, one known issue reconfirmed

Ran the full post-build verification checklist against the image directly (before node provisioning):
- Kernel: only `6.17.0-1032-nvidia-64k` present (`hi`), no stray kernel — clean.
- `/boot/vmlinuz`/`initrd` present and correctly linked.
- `dkms status`: `nvidia/580.173.10` + full OFED/mlnx stack, all `installed` against `6.17.0-1032-nvidia-64k` — matches 9b.
- Fabric Manager: `-> /dev/null`, confirmed masked — matches 9c.
- `/etc/network/interfaces.d/` and `/etc/ntpsec/` present — matches 9g.
- `dpkg -l | grep -i -E "^ii\s+(ntp|chrony)"` → **empty**. Confirms the known `ntp` health-check issue (Section 4/5 of the SOP, originally found on `maxQ106`/`1014`-doca321) also applies to this archive — chrony is missing here too, not just on the older image. **Do not apply the drafted-but-unvalidated chrony fix to this image ad hoc** — same escalate-don't-patch guidance as the original finding applies here.

**Conclusion:** image validated and ready for node assignment, with the pre-existing `ntp` health-check failure expected to reproduce on this rack's nodes post-provisioning — not a new issue, no action needed beyond what's already tracked.

### 9k. `systemd-timesyncd` pre-disabled by default — confirmed on this archive too

Applying the chrony fix (Section 5 known issue) to `baseos-1032-doca341`, `systemd-timesyncd` was found already `disabled` via `systemctl is-enabled systemd-timesyncd`, **before** any explicit `disable`/`mask` command was run and independent of the `chrony` install. Confirms this is not a `chrony`-install side effect but the same pre-disabled default already documented in §8.13 for the `1014`/DOCA-3.2.1 image — part of the same intentional-hardening pattern (`shorewall`/`auditd` also pre-disabled), just without a working time-sync replacement baked in. Consistent across at least two archive lines now.

Explicit `disable`/`mask` commands were still run regardless, to make the end state certain rather than relying on this default holding on a future archive.

### 9l. `/tmp` permissions issue is general to this chroot, not fabricmanager-specific

The known `chmod 1777 /tmp && rm -rf /tmp/*` prerequisite (originally documented only in the fabricmanager fix, 6d/6g) was also required before `apt-get install -y chrony` would run cleanly on `baseos-1032-doca341` — same `Couldn't create temporary file /tmp/apt.conf.XXXXXX for passing config to apt-key` error. **Correction to the standing knowledge:** this is not a fabricmanager-specific workaround — it's a precondition for *any* `apt-get` operation inside `cm-chroot-sw-img` on this image (and likely any image with the same `/tmp` permission state). Treat `chmod 1777 /tmp && rm -rf /tmp/*` as a standard first step before *any* apt-get inside a chroot session on this archive line, not just when installing `nvidia-fabricmanager-580`.

### 9m. Chrony install findings on `baseos-1032-doca341`

**`apt-get install chrony` fully removed `systemd-timesyncd` as a package**, not just left it disabled — apt resolved it as a conflicting package and removed it outright during the chrony install. Different from the pre-disabled-but-present state seen in 8.13's original finding on the `1014`/DOCA-3.2.1 image. Functionally equivalent end state (timesyncd gone/masked either way) — `systemctl mask systemd-timesyncd` run afterward still succeeded and created the `-> /dev/null` symlink even with the package already removed. Worth noting for future archives: don't assume the package will still be present after installing chrony.

**"Pending kernel upgrade!" false-alarm reproduced during this install** — apt's post-install scan reported running kernel `6.8.0-106-generic` vs. expected `6.17.0-1032-nvidia-64k`. Same known non-issue as 6d/6g: this is the **head node's** kernel identity leaking through `uname -r` inside any chroot, unrelated to the image's actual kernel (already independently confirmed correct via `dpkg -l`/`dkms status`). Confirms this false alarm isn't specific to the fabricmanager install — it fires on any package operation that triggers a kernel-scan hook inside `cm-chroot-sw-img`.

**New mount-cleanup gotcha: `exit` did not auto-unmount this session** — every prior `cm-chroot-sw-img` session in this build printed `unmounted ...` lines automatically on `exit`; this one did not. A `mount | grep <image-name>` check from the head node afterward found two mounts the standard 1.3/8.4 cleanup loop doesn't cover:
- `var/tmp/<random>` tmpfs — already a known-acceptable leftover (8.12), low risk.
- **`sys/firmware/efi/efivars` (`efivarfs`), nested under `/sys`** — not previously documented anywhere in this SOP/log. Needs to be unmounted **before** `/sys` itself in the cleanup sequence, or the `/sys` unmount may not fully release.

**Updated standing mount-cleanup sequence, going forward:**
```bash
umount -l /cm/images/<image-name>/sys/firmware/efi/efivars
umount -l /cm/images/<image-name>/var/tmp/* 2>/dev/null
for m in dev/pts dev proc sys run/systemd/resolve/resolv.conf run; do
  umount -l "/cm/images/<image-name>/$m" 2>/dev/null
done
mount | grep <image-name>   # var/tmp entry may still linger (known-acceptable); nothing else should
```
Root cause of why `exit`'s auto-unmount didn't fire this time is not established — possibly related to the nested `efivarfs` mount blocking the normal teardown order. Worth watching whether this recurs on the next chroot session against this same image, or only happened once.

**Cleanup confirmed successful (2026-09-16):** after running the updated sequence in 9m (efivarfs → var/tmp → standard loop), `mount | grep baseos-1032-doca341` returned completely empty — no lingering mounts at all, including the var/tmp scratch entry that's normally expected to persist. Sequence works as written; promote it to the SOP's standard mount-cleanup step.

### 9n. `rack08` explicitly re-provisioned from `maxQ-1029-doca341` to `maxQ-1032-doca341`

**Confirmed via `cmsh -c "device; list"` before any change was made:** all 18 `rack08node01`–`rack08node18` were live and `[UP]` under category `maxQ-1029-doca341` at the time this decision was made (all showing `health check failed`, consistent with the already-tracked known issues — not a new problem introduced by this decision).

**Explicit instruction received to re-provision this same physical rack onto `maxQ-1032-doca341`** — this is a deliberate reuse of already-in-service hardware for the new DOCA 3.4.1/kernel-1032 image, not a fresh/unused rack. Recorded here for traceability given the operational significance (18 previously-running nodes taken down and reinstalled).

**Nodegroup created for this purpose:**
```
nodegroup clone rack01group → rack08group
set nodes rack08node01..rack08node18
commit
```

**Category reassignment:**
```
device foreach -g rack08group (set category maxQ-1032-doca341)
commit
```
Category change alone does not reboot/reinstall nodes — `installmode FULL` + a reboot (IPMI/PXE) is still required to actually trigger reinstallation. Not yet executed as of this log entry.

### 9o. `installmode FULL` confirmed inherited from category, no per-device override needed

`cmsh -c "category use maxQ-1032-doca341; get installmode"` → `FULL`, carried over correctly from the `maxQ-1029-doca341` clone (9i). Nodes in `rack08group` will pick this up automatically on next boot — no need to set `installmode` per-device, consistent with the "verify what a clone actually carried over" pattern already established for `disksetup`/`finalizescript`.

Category reassignment for `rack08group` → `maxQ-1032-doca341` committed successfully (9n); all 18 nodes flagged `restart required (category)`, still up on their prior install, awaiting reboot to trigger reinstall.

### 9p. New: peer-provisioning role setup for `rack08node01` (not previously documented anywhere in this SOP/log)

For this rack's rollout, `rack08node01` was designated as a local provisioning source for the other 17 nodes in `rack08group`, to test/use peer-to-peer image transfer instead of every node pulling from the head node directly.

**Role name confirmed via `roles; assign` (no argument) → usage list:** `provisioning` (not `provisioningnode` or similar — confirmed against this BCM version's actual command help rather than assumed).

**Assign:**
```bash
cmsh
% device use rack08node01
% roles
% assign provisioning
% commit
```
First commit succeeded but warned: `The provisioning role does not contain any images.` — expected, role has no scope configured yet at this point.

**Scope the role — properties confirmed via `set` (no argument) → parameter list:** `localimages`, `sharedimages`, `allimages`, `categories`, `nodegroups`, `racks`, etc.
```bash
% set localimages baseos-1032-doca341
% set categories maxQ-1032-doca341
% commit
```
**Confirmed via `roles; use provisioning; show` afterward:** `Local images: baseos-1032-doca341`, `Categories: maxQ-1032-doca341` — correctly scoped to only this rack's new image/category, not left as `allimages`.

**Important sequencing constraint, not yet executed as of this log entry:** `rack08node01` does not yet have `baseos-1032-doca341` actually installed on itself — none of the 18 nodes have been rebooted onto it yet. A `provisioning` role serving an image the node doesn't locally have yet has nothing to serve. Correct order for this exercise:
1. Reboot `rack08node01` alone first — it installs from the head node (only provisioning source available at that point).
2. Confirm `rack08node01` comes up healthy on `baseos-1032-doca341`.
3. Reboot the remaining 17 `rack08group` nodes — they should now be able to peer off `rack08node01` per the role config above, instead of all 17 pulling from the head node simultaneously.

Not yet validated whether peer-to-peer selection actually happens automatically once the role is set (vs. requiring additional config elsewhere, e.g. network/category-level provisioning-source preference) — worth confirming once node 2+ actually starts provisioning, by checking which source IP their node-installer logs show pulling the image from.

### 9q. Redfish PXE boot-source override for `rack08node01` — 1G port identified, one-shot only (hard constraint)

**BMC:** `10.141.8.101` (Redfish, NVIDIA OEM BMC — `CARLO_NEXT-T1`, `System_0` is the correct `ComputerSystem` resource; `HGX_Baseboard_0` is a separate, non-bootable baseboard endpoint — don't confuse the two).

**1G port confirmed via boot-option enumeration, matched against user-supplied MAC:** `48:21:0B:88:08:8D` → `Boot0002` (`UEFI PXEv4 (MAC:48210B88088D)`). A second MAC, `1ECCEB9AB272`, also appears in the boot options (Boot0004–0007) routed through a `USB(...)` device path in `UefiDevicePath` — pattern suggestive of a USB-attached/BMC-shared virtual NIC rather than a physical DPU port, but **not independently confirmed** which physical adapter (BF3 vs. onboard LOM vs. BMC-shared) either MAC actually belongs to. `EthernetInterfaces` and `NetworkAdapters` Redfish collections both returned `ResourceNotFound` on this BMC — not exposed, couldn't cross-check that way.

**BCM's own interface record for this node is unhelpful for this purpose:** `cmsh -c "device use rack08node01; interfaces; use enP5p9s0; show"` shows `MAC 00:00:00:00:00:00` — BCM does not have the real MAC recorded for the provisioning interface (likely populated at first successful DHCP/PXE, not before). Cannot cross-check the 1G-port identification against BCM's own record for this reason.

**User's real-world operational experience:** boot takes ~3 extra minutes when the 1G port isn't explicitly prioritized, attributed to BF3 being attempted first. Not yet reconciled precisely against the Redfish `BootOrder` evidence, which shows local disk (`Boot000C`)/NVMe (`Boot0001`) ranked *before any* PXE entry, and `Boot0002` (1G, `48210B88088D`) ranked before the `1ECCEB9AB272` entries. Plausible the delay is from local-boot-device attempts rather than BF3-before-1G specifically — not confirmed either way. **Action item for next session: watch the console/node-installer log timing during the actual override boot to determine the real cause of the delay, rather than assuming.**

**Command used — explicitly one-shot, `BootOrder` itself never modified:**
```bash
curl -k -u root:0penBmc -X PATCH \
  -H "Content-Type: application/json" \
  -d '{"Boot": {"BootSourceOverrideEnabled": "Once", "BootSourceOverrideTarget": "Pxe"}}' \
  https://10.141.8.101/redfish/v1/Systems/System_0
```
**Hard constraint, explicitly required by the user: this override must never be made persistent.** `BootSourceOverrideEnabled: "Once"` is required — `"Continuous"` must not be used for this purpose. `BootSourceOverrideTarget` on this BMC only supports the generic `Pxe` value (enum: `None/Pxe/Hdd/Cd/BiosSetup/Usb` — no `UefiTarget`/`BootNext`-style specific-entry targeting), so which exact PXE NIC it resolves to is inferred from `BootOrder` position, not explicitly forced. If this BMC's firmware ever needs the boot order changed to reliably land on the 1G port, that would be a **persistent** `BootOrder` change — explicitly out of scope for this exercise and would need separate, explicit sign-off before being done, not folded into a "PXE override" request.

### 9r. Redfish one-shot PXE override — confirmed effective; ~3.5 min delay appears to be POST/PXE-boot time, not BF3-vs-1G ordering

**Override consumption confirmed:** `BootSourceOverrideEnabled`/`Target` reverted from `Once`/`Pxe` back to `Disabled`/`None` on its own after the reboot — firmware honored the one-shot override (via `ipmitool -I lanplus ... chassis power cycle`, not a Redfish-native reset action) rather than ignoring it.

**DHCP log for the reboot window (`journalctl -u dhcpd`) shows only one MAC involved — `48:21:0b:88:08:8d`, the confirmed 1G port:**
```
19:21:09  DHCPRELEASE  (from 88:08:8d — OS releasing lease during shutdown, pre-power-cycle)
19:22:58  DHCPDISCOVER (from 88:08:8d — PXE attempt begins)
19:23:02  DHCPOFFER/DHCPREQUEST/DHCPACK (from 88:08:8d — handshake completes in 4s)
19:24:46  [INSTALLING] (node-installer started, per cmsh event log)
```
**No DHCPDISCOVER from any other MAC appears in this window** — no direct evidence the BF3 (or any other NIC) was attempted first. This is real evidence the 1G-priority override worked as intended.

**Timeline breakdown:**
- `19:21:09` → `19:22:58` (~1m49s): pre-PXE POST/firmware init, before any DHCP attempt at all.
- `19:22:58` → `19:24:46` (~1m48s): PXE handshake (fast, ~4s) + TFTP/kernel-initrd download + node-installer startup.
- **Total ~3m37s, matching the user's previously-reported "~3 minutes" experience.**

**Conclusion — tentative, worth confirming on a second boot before treating as settled:** the delay appears to be normal POST + PXE-software-boot time on this hardware platform, **not** evidence of BF3 being attempted before the 1G NIC. If so, the 1G-priority Redfish override, while working exactly as designed, may not actually reduce the ~3-minute figure — that time was likely never attributable to NIC ordering in the first place. **Open item: compare this timing against a boot *without* the override** (letting firmware use its normal `BootOrder`, which already ranks the 1G PXE entry, `Boot0002`, ahead of the other MAC's entries per 9q) to see if the timing is actually any different — if it's the same, the override may be unnecessary for this specific speed goal, though it may still be worth keeping as an explicit, auditable guarantee rather than relying on `BootOrder` position.

### 9s. `pxe_rack_provision.sh` modified — `--node` now accepts a range (N-M)

User-provided script only supported `--node <N>` (a single node) or the whole rack via `--rack`. For this rollout, needed to target `rack08node02` through `rack08node18` specifically — node01 was already handled manually via the Redfish/ipmitool exercise (9q/9r) and shouldn't be re-touched by re-running the whole rack.

**Change:** `--node` now accepts either a single integer (`--node 18`, unchanged/backward-compatible) or a range (`--node 2-18`), validated the same way `--rack` already validates its own `N-M` range (start ≤ end, both within 1..NODE_COUNT). Range/confirmation labels updated accordingly (e.g. `rack08node02-node18`), and the total-node-count math updated to reflect the actual range size rather than assuming 1.

**Verified via `--dry-run`:**
- `--rack 8 --node 1` → still targets only `bmc-rack08node01` (backward compatible).
- `--rack 8 --node 2-18` → correctly targets `bmc-rack08node02` (`10.141.8.102`) through `bmc-rack08node18` (`10.141.8.118`), 17 nodes total, correct BMC IPs per the existing `10.141.<rack>.<100+node>` formula.
- `--rack 8 --node 2-20` → correctly rejected as out-of-range for an 18-node rack, before anything is sent.

**Confirmed the script's default workflow is compatible with the one-shot-only PXE constraint established in 9q:** `ipmitool ... chassis bootdev pxe options=efiboot` (no `options=persistent`) followed by `chassis power cycle` — this sets the next-boot flag for one boot only, consistent with what was manually validated via Redfish on `rack08node01`. No change needed to that part of the script's behavior.

**Operational note, not yet decided:** default `--delay` is `0`, meaning all nodes in a range/rack hit the head node's DHCP/TFTP simultaneously. Given `rack08node01`'s peer-provisioning role (9p) is not yet confirmed to actually get used automatically by BCM's node-installer, running the remaining 17 with `--delay 0` is a real test of whether peering happens under concurrent load — or a staggered `--delay` may be preferred for this first real run. Left as the operator's choice at execution time, not hardcoded into the script.

### 9t. NEW real issue: `cuda-dcgm` service crash loop on `rack08node01` — DCGM daemon package missing from image, not a restart-fixable problem

After `rack08node01` finished provisioning (`INSTALLING` at 19:24:46 → `UP` at 19:40:58), CMDaemon's service monitor reported `cuda-dcgm` and `mst` repeatedly dying and failing to restart every ~30s continuously (19:41:59 onward, still ongoing at 19:46:00+), leading to `ManagedServicesOk` FAIL at 19:48:01.

**Root cause confirmed, not a transient crash:**
```bash
ssh rack08node01 "systemctl list-units --all | grep -iE 'dcgm|mst'"   # → empty, no units exist
ssh rack08node01 "ps aux | grep -iE 'dcgm|mst'"                        # → no processes running
ssh rack08node01 "dpkg -l | grep -iE 'dcgm|mst|mft'"
```
Shows only `cuda-dcgm-libs` (libraries only) installed — **the actual DCGM daemon package is missing entirely.** `apt-cache search datacenter-gpu-manager` confirms the real daemon package (`datacenter-gpu-manager`, or a versioned variant like `datacenter-gpu-manager-4-core`/`-4-cuda13`/etc.) is available in the repo but was never installed on this image. `which nv-hostengine dcgmi` returns nothing — the actual DCGM binaries don't exist on the node.

**`mst` is a different, likely benign case** — MST is traditionally started via the one-shot `mst start` command (loads the kernel module, creates `/dev/mst/*` device nodes) rather than run as a persistent systemd daemon, so `mst.service` never existing may not indicate a real gap the way the DCGM daemon's absence does. Not yet confirmed either way — pending `mst status` output.

**`cmsh -c "category use maxQ-1032-doca341; services; list"` returned empty** — these health-check/service-monitor entries are not coming from category-level service config. Not yet confirmed whether they're defined at the device level instead, or come from some other BCM default/installer mechanism. Pending `device use rack08node01; services; list` output.

**Important side-finding: `ldap` health check showed `PASS` on this node (19:44:14)** — different from the known `ldap`/`nsswitch` regression documented for the older `1014`/DOCA-3.2.1 image (Section 5). Worth confirming this holds on the other nodes too before revising that known-issue entry — could mean the regression is specific to the older image/fix history and doesn't apply to this archive line.

**Also noted: `"Reboot required: Interfaces have been modified"` warning fired immediately post-install (19:41:12)** — not yet investigated, possibly related or unrelated to the service crash loop. Flagged for follow-up.

**Recommendation: do not proceed to the remaining 17 nodes (rack08node02-18) until this is resolved.** Since the missing DCGM daemon package is an image-level gap (Section 1's driver/DOCA verification checked `dkms status`/`doca-host`/`mlnx-ofed` but did not check for the DCGM daemon specifically), all 17 remaining nodes would hit an identical crash loop if provisioned from the same `baseos-1032-doca341` image as-is. Fix path: add the correct `datacenter-gpu-manager-4-*` package to the image (likely via a chroot `apt-get install`, same pattern as the fabricmanager/chrony fixes — mount cleanup required afterward per Section 1.4), then re-verify before resuming rollout to the rest of the rack.

**Operational note:** SSH host-key mismatch warning is expected on every first-connect to a freshly-reinstalled node (host keys regenerate on every reinstall) — not a real security event, but will recur for all 17 remaining nodes. `ssh-keygen -R <hostname>` before each first connect, or bulk-clear `rack08node*` entries from `known_hosts` ahead of time.

**Confirmed:**
- `cmsh -c "device use rack08node01; services; list"` → `cuda-dcgm`, `mst`, `nslcd`, `rshim` — all `Monitored: yes, Autostart: yes`, set at the **device level**, not category level (category's own `services; list` was empty, 9t). Strongly suggests this is BCM's own hardware-profile auto-registration for this DGX-class node type, not manual per-node config — meaning the same four expected services will register identically on all 17 remaining `rack08group` nodes once provisioned.
- `mst status` on the live node: `MST PCI module is not loaded` / `MST PCI configuration module is not loaded` — confirms no mechanism ever ran `mst start` (or equivalent) to load the kernel module, consistent with there being no `mst.service` unit to have done so. Same root pattern as `cuda-dcgm`: BCM expects a running service that has nothing actually providing it on this image.

**Still open:** `nslcd` and `rshim` status not yet checked — `rshim` (BlueField/DPU management) is particularly relevant given this same node (`rack08node01`) also carries the peer-provisioning role from 9p. Pending confirmation of full scope before finalizing the fix plan.

**Scope confirmed: exactly 2 of the 4 device-monitored services are actually broken.**
- `nslcd` — genuinely healthy, running (`active (running)`, real PID, accepting connections).
- `rshim` — genuinely healthy, running (`active (running)`, BlueField SoC driver, successfully attached `rshim0` to `pcie-0016:01:00.2`). Important to have confirmed this specifically since `rack08node01` also carries the peer-provisioning role (9p) — no DPU/BlueField management issue on this node.
- `cuda-dcgm` and `mst` — confirmed broken per 9t, root cause is missing daemon package (`cuda-dcgm`) and un-loaded kernel module with no service to load it (`mst`). **This is an isolated, two-service gap, not a broad image-wide service failure.**

**Side note, not yet investigated further:** `nslcd`'s log (post-reboot) shows `ldap_result() failed: Can't contact LDAP server` and `request denied by validnames option` a few minutes into this boot — worth watching given the already-tracked LDAP-adjacent known issues (Section 5), even though the `ldap` health check itself showed PASS earlier in this same node's lifecycle (19:44:14, pre-this-reboot). Could be timing/transient rather than a regression. Confirmed separately: this reboot did **not** clear the `mst` module-not-loaded state or restart the `cuda-dcgm`/`mst` crash loop — both persisted through the reboot, ruling out "just needed a fresh boot" as an explanation.

### 9u. `cuda-dcgm` root cause fully confirmed — correct package name is `cuda-dcgm`, not a `datacenter-gpu-manager-*` variant

**Cross-check against `rack01node01` (already-live production node, `maxQ-1014-doca321`) disproved the "fleet-wide accepted gap" hypothesis:** `rack01node01` shows `cuda-dcgm: PASS` and `ManagedServicesOk: PASS` — the daemon genuinely works there. This is specific to `baseos-1032-doca341`, not a standing quirk tolerated across the whole fleet.

**Correct package identified by direct comparison:**
```bash
ssh rack01node01 "dpkg -l | grep -iE dcgm"
```
→ `cuda-dcgm` (the actual daemon, not just libs) **and** `cuda-dcgm-nvvs` (NVIDIA Validation Suite) both installed at `1:4.5.2-100153-cm11.0-3e31a09987` — the **exact same version** already present for `cuda-dcgm-libs` on `baseos-1032-doca341`. Confirms the fix is a straightforward "install the missing sibling packages," not a CUDA-version-variant guessing exercise like the earlier `datacenter-gpu-manager-4-*` speculation (9t) — that speculation is now superseded/incorrect, don't use it.

**Fix for the image (not yet executed as of this log entry):**
```bash
cm-chroot-sw-img /cm/images/baseos-1032-doca341
chmod 1777 /tmp && rm -rf /tmp/*
apt-cache policy cuda-dcgm cuda-dcgm-nvvs   # confirm same version as already-installed cuda-dcgm-libs before installing
apt-get install -y cuda-dcgm cuda-dcgm-nvvs
exit
```
Followed by standard mount cleanup (Section 1.4), then separately fixing the already-provisioned `rack08node01` directly via the same `apt-get install` over SSH (image fix alone won't retroactively fix a node already installed from the old image state).

**Still separately open, not resolved by this fix:**
- `mst`: user has no memory of `mst.service` ever being a real systemd unit — worth treating "MST is a one-shot `mst start`, not a persistent service" as the likely correct model rather than assuming a missing package, pending confirmation of how `rack01node01` handles the same BCM `Monitored: yes, Autostart: yes` expectation for `mst` (not yet checked — worth doing the same cross-check used for `cuda-dcgm`).
- `ntp`/chrony: confirmed genuinely synced (`chronyc tracking`: `Leap status: Normal`, tight offsets) but off **public internet** NTP servers (`canonical.com`, `hinet-ip`, etc.), not an internal source — the original plan to point chrony at an internal time server was never completed (no internal address was ever provided). Open decision, not a technical blocker: is public-internet NTP acceptable for this cluster's compute nodes, or should they sync off the head node internally?
- `ldap`/`cmsupport`: `getent passwd cmsupport` succeeding is not conclusive — could be resolving from a local `/etc/passwd` entry rather than real LDAP, while `nslcd`'s own log showed `Can't contact LDAP server` minutes into the same boot. Needs `grep cmsupport /etc/passwd` + `nsswitch.conf` check to determine if `ldap: PASS` is meaningful or masked.

**Recurring operational note:** SSH host-key mismatch warnings appearing even for `rack01node01` (an already-established production node, not freshly reinstalled) suggests `known_hosts` on this head node is generally out of sync across the fleet, not just an artifact of `rack08` reinstalls. Worth a one-time bulk `known_hosts` cleanup for the whole fleet rather than clearing entries one at a time as each is hit.

### 9v. `rack_lifecycle.sh` (uploaded) confirms `cuda-dcgm` fix is a genuine pre-handoff blocker, not just a nice-to-have

New script uploaded, intended for the post-BCM-provisioning handoff/diag/production lifecycle (`status`/`handoff`/`pre-diag`/`post-diag`, `finalize` deliberately unimplemented pending a decision on what "production-ready" means). Directly relevant to the open `cuda-dcgm` finding (9t/9u):

- `do_pre_diag()` explicitly disables `cuda-dcgm.service` before diag testing — confirmed root cause of a prior `SYNC_CLIENT_NOT_REGISTERED` diag failure was DCGM holding `/dev/nvidia*` open and blocking the diag tool's module-unload step. Uses `disable --now`, not just `stop`, specifically because a plain stop doesn't survive a diag-campaign power-cycle.
- `do_post_diag()` restores `cuda-dcgm.service` to whatever active/enabled state `pre-diag` recorded, read back from `/etc/rack-lifecycle-state`.
- `do_status()` reports `cuda-dcgm` active/enabled state as part of its standard health snapshot.

**Conclusion: this tooling assumes `cuda-dcgm.service` is genuinely installed and normally running** — handing off a `rack08` node without the real daemon (9t/9u) means `pre-diag` operates on a service that was never active to begin with, silently changing this rack's behavior relative to every other rack this tooling was built against. **Confirms the `cuda-dcgm`/`cuda-dcgm-nvvs` install fix (9u) should happen before handoff, not just before general use.**

**Separate note: this script has no `mst` handling anywhere** — `mst`'s gap (module needing manual `mst start`, no persistent service backing BCM's `Monitored: yes, Autostart: yes` expectation) is entirely outside this script's scope. Not yet decided whether that's acceptable to hand off as-is or needs to be resolved first, same as `cuda-dcgm` was.

**Also worth noting for clarity, not a contradiction:** `do_handoff()`'s LDAP-decoupling steps (stop/disable `nslcd`, strip `pam_ldap.so`, `nsswitch.conf` → `files`, explicitly preserving `cmsupport` as a local account *first*) are a **deliberate, controlled, by-design step** for racks leaving the BCM network — not the same thing as the earlier-documented *accidental* `nsswitch.conf` regression that broke `cmsupport` (Section 5's known issues, tied to an unrelated fix that shouldn't be reapplied). Don't conflate the two: one is an intentional off-cluster transition step with safeguards built in, the other was a bug.

**Script references `gb300_l10_build_log.md §25d`** for further detail on the DNS/LDAP handoff fix's origin — a different filename than this session's `session-summary.md`. Not available in this session; if it's a real, separate document, worth locating for full context on the handoff fixes' origin story, but not blocking for the immediate `cuda-dcgm`/`mst` decision.

### 9w. `cuda-dcgm` fix confirmed working on live node — was a stale health-check snapshot, not a real failure

Installed `cuda-dcgm` (12.3 MB, daemon only — `cuda-dcgm-nvvs` deferred, see 9x) directly on `rack08node01` via SSH. First `apt-get` attempt stalled indefinitely on the 1.24 GB `cuda-dcgm-nvvs` download (0:00 CPU time after 7+ minutes, no growth in cached `.deb` size) and had to be killed (`kill -9`, plain SSH command — no `-t`/pty needed for killing a *new* remote process, only needed when trying to signal an *already-attached* foreground session). `dpkg --configure -a` confirmed clean after the kill, `cuda-dcgm` alone then installed cleanly from the already-fully-cached `.deb` (matches exact expected size, no re-download).

**Verified immediately after install:**
```bash
systemctl status cuda-dcgm --no-pager -l
```
→ `active (running)`, `nv-hostengine` initialized, listening on port 5555, clean startup log, no errors.

**First `latesthealthdata` check still showed `cuda-dcgm: FAIL`** — but timestamp (58.5s old) aligned almost exactly with the service's own start time, indicating a stale sample caught mid-startup rather than a real persisting failure. **Confirmed via cmsh event log ~2 minutes later:** `The trigger 'Passing health checks' is active because the measurable 'cuda-dcgm' is PASS`. Fix is genuinely working — false alarm was just measurement timing, not a real gap. Worth remembering for future fixes on this SOP: always allow one full health-check cycle to pass before concluding a fix didn't work.

**Still pending:** the corresponding fix has not yet been applied to the **image itself** (`baseos-1032-doca341`) — only to this one already-provisioned live node. Without the image fix, all 17 remaining `rack08group` nodes will still provision with the same gap. Image-level fix (9u) still needs to be run.

**Decision: `cuda-dcgm-nvvs` will NOT be installed** — too large (1.24 GB) for the benefit given it's not required for `ManagedServicesOk`/`cuda-dcgm` health checks or `rack_lifecycle.sh`'s pre-diag/post-diag workflow (both only reference `cuda-dcgm.service`, not `nvvs`). Can be installed later, separately, off-hours or on better bandwidth, if the diag team's validation-suite tooling ends up needing it — not a blocker for this rollout.

**Confirmed via fresh `latesthealthdata` sample:** `cuda-dcgm: PASS`, `ManagedServicesOk` now only lists `mst` — exactly the isolated scope expected. `cuda-dcgm` fix fully validated on the live node.

**Next decision point: apply the same `cuda-dcgm` fix (daemon only, no `nvvs`) to the image itself** (`baseos-1032-doca341`) before provisioning the remaining 17 `rack08group` nodes, so they don't each need this same manual per-node SSH fix after the fact.

### 9x. `mst` confirmed as a pre-existing, fleet-wide condition — NOT related to `--no-cm-cuda-repo` or this build

Direct comparison against `rack01node01` (live production, `maxQ-1014-doca321`, entirely different build history/archive):
```bash
ssh rack01node01 "systemctl list-units --all | grep -i mst"   # → empty, same as rack08node01
ssh rack01node01 "mst status 2>&1"                             # → "MST PCI module is not loaded", identical to rack08node01
cmsh -c "device latesthealthdata rack01node01" | grep -i mst   # → NO OUTPUT AT ALL - mst doesn't appear as a health row here
```

**Confirms:** the `mst` module-not-loaded state is a **pre-existing, fleet-wide condition**, present identically on an already-established production rack built via a completely different image/archive. Not caused by `--no-cm-cuda-repo` (ruled out directly — `rack01node01` never used that flag) and not specific to `baseos-1032-doca341` or `maxQ20GA`. MST is genuinely just never auto-started anywhere in this fleet; `mst start` has always been a manual/one-shot action, consistent with the user's own recollection that there's no memory of `mst.service` ever being a real thing.

**Real remaining discrepancy, not yet explained:** `mst` does NOT appear at all in `rack01node01`'s `latesthealthdata` output, but DOES appear in `rack08node01`'s (`ManagedServicesOk` info column, per device-level `services; list` showing `mst: Monitored=yes, Autostart=yes` at the device level for `rack08node01` — 9t). This means BCM is *watching for* `mst` on `rack08node01` but apparently is not on `rack01node01`, despite the underlying MST state being identical on both. Not yet determined why the device-level service-monitoring list differs between these two nodes — worth checking `cmsh -c "device use rack01node01; services; list"` directly to confirm whether `rack01node01`'s device-level service list simply doesn't include `mst`/`cuda-dcgm` at all (different hardware-profile detection outcome?) versus including it but it happening to report clean for some other reason.

**Working conclusion:** `mst`'s underlying gap is a long-standing, fleet-wide, already-accepted condition — not a blocker introduced by this rollout. The open question is purely about BCM's *monitoring configuration* difference between nodes, not about MST itself needing a new fix. Reasonable to treat as non-blocking for handoff, pending the one remaining monitoring-config check.

**Correction to 9x's open question:** device-level service config is **identical** between `rack01node01` and `rack08node01` — both show `cuda-dcgm`, `mst`, `nslcd`, `rshim` all `Monitored: yes, Autostart: yes`. The earlier hypothesis (different monitoring config between the two nodes) is wrong.

**Actual explanation: timing/freshness, not configuration.** `rack01node01` has been up ~1 week+ (per its `gpu_health_*` timestamps, 9j-era data); whatever `mst died`/restart-attempt cycling happened on its own first boot has long since gone quiet — `ManagedServicesOk`'s `Info` column appears to only surface currently-active fail/retry cycling, not a permanently-settled "never was running, stopped trying to restart it" state. `rack08node01` was provisioned only ~30 minutes prior to this check, so it's still inside that same initial noisy window every node goes through on first boot.

**Final conclusion: this is not "rack08 has a problem rack01 doesn't" — it's the same fleet-wide, pre-existing MST gap at two different points in its own per-node lifecycle.** Expect `mst` to eventually stop appearing in `rack08node01`'s `ManagedServicesOk` info column on its own, without further action, once CMDaemon's retry-cycling for it settles the same way it apparently has on every other already-established node. **Non-blocking for remaining rollout and handoff** — consistent with a long-standing, fleet-wide, already-tolerated condition rather than something introduced by this build.

### 9y. Mechanism clarified: why CMDaemon reports "mst died" with no `mst.service` ever existing

`systemctl status mst` on `rack08node01` confirms directly: `Unit mst.service could not be found.` This is not a contradiction with CMDaemon's repeated "Service mst died"/"was not restarted" messages — it explains them. **CMDaemon's generic service-monitoring feature maps a configured service name directly to `systemctl status <name>.service`** — it does not create or provide the unit itself, it only watches for one that's assumed to already exist (from a package or the image). This is the identical mechanism used for `cuda-dcgm`, `nslcd`, and `rshim` in the same device-level `services` list (9t) — CMDaemon has no special-case logic per service name, it treats all four identically.

Since no node in this fleet (confirmed on both `rack08node01` and `rack01node01`) has ever had a real `mst.service` unit, CMDaemon's periodic check will always report "died"/"could not restart" for it — the wording is CMDaemon's generic language for "expected unit not found or not active," not evidence anything was ever actually running and then crashed. Exactly parallel to the `cuda-dcgm` situation before the real daemon package was installed.

**Open question, not resolvable from this session alone — needs an owner:** why is `mst` in the fleet's expected-services list at all, given no `mst.service` unit has apparently ever existed on any node? Two live possibilities:
1. NVIDIA's reference DGX/GB300 software stack is supposed to ship a real `mst.service` unit (e.g., bundled with `mft`/`mstflint`/`kernel-mft-dkms`), and it's missing from every image built to date — an image-level gap across the entire fleet, not specific to `baseos-1032-doca341`.
2. BCM's own hardware-profile template for this platform has a stale or incorrect default that was never actually correct — `mst` may have always been intended as a manual/one-shot `mst start`, not a persistent service, and the monitoring expectation itself is wrong.

**Recommendation:** flag this to whoever owns BCM's hardware-profile/category defaults for this platform, or NVIDIA support/docs, for a definitive answer — not something to guess at or silently work around per-rack. Does not block this rollout (confirmed fleet-wide, pre-existing, non-functional-impact), but worth resolving at the source rather than accepting indefinitely across every future rack.

### 9z. `pxe_rack_provision.sh` modified again — added `--pxe-method ipmitool|redfish`

Gap identified: the script only ever used `ipmitool ... chassis bootdev pxe options=efiboot` to set the next-boot PXE flag, even though the mechanism actually validated by hand on `rack08node01` (9q/9r) to correctly land on the 1G NIC was the **Redfish** `BootSourceOverride` PATCH, not ipmitool's boot-flags mechanism. These are two different BMC-level mechanisms and were never confirmed equivalent on this hardware — the script's default behavior was carrying an unvalidated assumption forward.

**Change:** added `--pxe-method ipmitool|redfish` (default `ipmitool`, preserving existing behavior/backward compatibility). When `redfish` is selected, PXE-setting goes through a new `set_pxe_flag()` helper that PATCHes `Boot.BootSourceOverrideEnabled=Once` / `BootSourceOverrideTarget=Pxe` against `https://<bmc-ip>/redfish/v1/Systems/${REDFISH_SYSTEM_ID}` — same one-shot-only semantics as the manually-validated approach (never `Continuous`, never touches `BootOrder`).

**New `REDFISH_SYSTEM_ID` variable ("System_0")** — explicitly flagged in comments as confirmed only for this specific BMC/hardware (NVIDIA "CARLO_NEXT-T1", confirmed via a live `/redfish/v1/Systems` enumeration during the rack08node01 exercise), not a safe universal default. Header comment tells the reader exactly how to re-verify it on different hardware before trusting it.

**Validation added:** `--pxe-method redfish` combined with `-power`-only mode is now rejected at argument-parsing time (that mode never sets a PXE flag at all, so the option would silently do nothing) — errors out with a clear message rather than accepting a no-op combination.

**Verified via `--dry-run`:**
- Default (`ipmitool`) behavior unchanged — confirmed identical dry-run output to the pre-change version.
- `--pxe-method redfish --rack 8 --node 1` → correctly shows the `curl -X PATCH .../Systems/System_0` line instead of the ipmitool bootdev line, power-cycle line unchanged.
- `--pxe-method redfish --rack 8 --node 2-18` → correctly composes with the node-range feature (9s), one PATCH line per node with the correct per-node BMC IP substituted.
- `-power cycle --pxe-method redfish --rack 8 --node 1` → correctly rejected before running anything.

**Not yet exercised for real** (only dry-run tested) — first real use of `--pxe-method redfish` through this script should be treated as validation, same caution as the original manual exercise: confirm via DHCP log or console which NIC actually PXE'd, don't assume success from HTTP 2xx alone.

### 9aa. Clarification: `System_0` is not 1G-specific — it's the whole-host resource; NIC selection is a `BootOrder` property, not a resource-ID property

Question raised: is `System_0` itself specific to the 1G RJ45 PXE port (as opposed to BF3)? **No.** `System_0` is the Redfish `ComputerSystem` resource for the entire host — confirmed via the `/redfish/v1/Systems` enumeration (9q), which returned exactly two members: `System_0` (bootable host) and `HGX_Baseboard_0` (separate baseboard-management endpoint, not bootable, not NIC-related). Neither is per-NIC.

The 1G-vs-other-NIC distinction lives entirely inside `System_0`'s own `Boot.BootOrder`/`Boot.BootOptions` data — specifically `Boot0002`, matched to the 1G port's MAC (`48210B88088D`) by direct enumeration. The generic `BootSourceOverrideTarget: "Pxe"` PATCH we use does not target a specific NIC — it resolves to **whichever PXE-capable entry ranks first in that system's `BootOrder`** at the time of the boot. It landed on the 1G port only because `Boot0002` already ranked ahead of the other observed MAC's entries (`1ECCEB9AB272`, Boot0004-0007) in `BootOrder`. If `BootOrder` ever changed (firmware update, BIOS setting, etc.) such that a different NIC's PXE entry ranked first, the identical override — same `System_0`, same PATCH — would resolve there instead.

**Still an open, unconfirmed point, not resolved by this clarification:** whether `1ECCEB9AB272` is actually BF3's host-facing NIC representor was never definitively confirmed (9q noted only that its `UefiDevicePath` routes through a `USB(...)` pattern suggestive of a BMC-shared/virtual NIC, not confirmed either way). Separately, BlueField DPUs commonly run their own independent ARM SoC with a separate boot process (sometimes managed via `rshim` rather than the host's main BMC) — whether that's relevant here, or whether the host-visible NIC representor is what's actually at stake, was never directly investigated. `set_pxe_flag()`'s `redfish` method (9z) is scoped only to the host's own `System_0` boot sequence — it makes no claim about, and has no effect on, BF3's own internal SoC boot process if that's a genuinely separate domain.

### 9ab. Evidence suggests BlueField3's own network ports have no PXE boot-option entry at all — not just deprioritized

Cross-referenced the 11 UEFI boot options (9q) against BF3's actual PCIe address, confirmed via `mst status -v` on `rack08node01`:
```
BlueField3(rev:1)   0016:01:00.0   mlx5_4   net-ibP22s22f0
BlueField3(rev:1)   0016:01:00.1   mlx5_5   net-ibP22s22f1
```
**None of the 11 boot options reference PCI address `0016:01:00.x` in their `UefiDevicePath`.** The PXE/HTTP-capable entries route only through `PciRoot(0x5).../Pci(0x6,0x0)` (MAC `48210B88088D`, confirmed 1G port) or `USB(0x4,0x0)/USB(0x0,0x0)` (MAC `1ECCEB9AB272`, previously flagged as "maybe BF3" but unconfirmed).

**Revised assessment of `1ECCEB9AB272`: likely NOT BF3.** The `USB(...)` device-path pattern is more consistent with a BMC-shared/virtual management NIC than a physical DPU port, and it doesn't match BF3's real PCIe location either. Combined, this is real (though indirect) evidence that **BlueField3's actual network ports (`mlx5_4`/`mlx5_5`) have no UEFI boot-option entry registered at all** on this system — not merely ranked low in `BootOrder`, but absent from the boot-options collection entirely.

**Practical implication:** the generic `Pxe` override (via either `ipmitool bootdev pxe` or the Redfish method in `set_pxe_flag()`) could never have landed on BF3 in the first place, regardless of `BootOrder` ranking — there's no boot option for firmware to select. This changes the earlier framing (9aa) slightly: it's not just "1G currently ranks first," it may be "BF3 was never a candidate at all" for standard UEFI PXE boot on this hardware/firmware configuration.

**Two explicit limits on this conclusion, not yet resolved:**
1. BF3 may have its own separate, independent firmware/boot configuration (checked via `mlxconfig` or similar run against the DPU itself) that wouldn't appear in the host's UEFI boot-options list at all — not checked this session.
2. This is inferred from a PCI-address mismatch, not a direct "PXE: disabled" readout from any tool — worth treating as strong circumstantial evidence, not a confirmed fact, until/unless checked directly against BF3's own config.

**Architectural plausibility check:** consistent with BlueField DPUs typically being used as fabric/RDMA interfaces rather than the host's own provisioning path — matches BCM's own designation of `enP5p9s0`/the 1G port (not any BF3 interface) as the `[prov,dhcp]` provisioning NIC for this node.

### 9ac. Definitive answer: BF3 PXE is not disabled — ports are configured for InfiniBand, not Ethernet

Direct `mlxconfig -d 0016:01:00.0 query` against BF3 itself (via `rshell` on `rack08node01`) settles the question raised in 9ab conclusively:

**PXE is enabled at the device/firmware level:**
```
EXP_ROM_PXE_ENABLE       True(1)
EXP_ROM_UEFI_x86_ENABLE  True(1)
EXP_ROM_UEFI_ARM_ENABLE  True(1)
LEGACY_BOOT_PROTOCOL     PXE(1)
```

**Root cause of no PXE boot-option entry (9ab): link type, not a disabled feature.**
```
LINK_TYPE_P1    IB(1)
LINK_TYPE_P2    IB(1)
```
Both BF3 ports are configured for native InfiniBand, not Ethernet. Standard PXE (the DHCP/TFTP Ethernet-layer protocol BCM's provisioning and the host's UEFI boot-option enumeration both use) requires an Ethernet-mode port — `EXP_ROM_PXE_ENABLE` controls whether the option ROM *would* offer PXE if in Ethernet mode, but does not override the port's actual link-type configuration. A port in native IB mode simply doesn't present as a PXE-capable Ethernet NIC to firmware, so no `Boot000X` entry gets generated for it — consistent with 9ab's finding of no boot option at BF3's PCI address, and now fully explained rather than just inferred.

**Consistent with everything else observed this session:** `mst status -v` interface naming (`net-ibP22s22f0`/`net-ibP22s22f1`, "ib" prefix) already implied IB mode; this is BF3 deliberately configured for its IB fabric role on this GB300 NVL node, not an oversight or misconfiguration.

**Correction to any implication that "BIOS should enable BF3 PXE":** there is no BIOS-level PXE toggle at play here — this is a DPU port link-type configuration (`LINK_TYPE_P1`/`LINK_TYPE_P2`), set via `mlxconfig`, not the host's BIOS/UEFI settings. Changing it to `ETH` would be a real, consequential change to the DPU's data-plane fabric role for this node (not merely a "turn on PXE" toggle) and should not be done without deliberately deciding to trade BF3's IB fabric connectivity for Ethernet/PXE capability on those ports — a decision with real operational impact, not a quick fix.

### 9ad. Root cause identified (strong inference, not fully confirmed): BIOS disables option ROM on all x16 fabric NIC slots by design

`dmidecode -t 9` (System Slot Information) cross-referenced against confirmed PCI domains from `mst status -v`/boot option device paths:

| PCI Domain | dmidecode Designation | Confirmed device |
|---|---|---|
| `0000` | NIC Slot 1 (x16 Gen5) | ConnectX-8 `mlx5_0`/`mlx5_1` |
| `0002` | NIC Slot 2 (x16 Gen5) | ConnectX-8 `mlx5_2`/`mlx5_3` |
| `0005` | NIC Slot 3 (x1 Gen3 — different class) | **1G port** (matches `PciRoot(0x5)` in the confirmed Boot0002 device path) |
| `0010` | NIC Slot 5 (x16 Gen5) | ConnectX-8 `mlx5_4`/`mlx5_5` |
| `0012` | NIC Slot 6 (x16 Gen5) | ConnectX-8 `mlx5_6`/`mlx5_7` |
| `0016` | NIC Slot 7 (x16 Gen5) | **BlueField-3** |
| `0015` | M.2 NVMe Slot 1 | NVMe (matches `PciRoot(0x15)` in Boot0001) |
| `0006` | NIC Slot 4 (x16 Gen5, "Available") | Unpopulated |

**Strong numeric/architectural correlation found:** exactly six `x16 PCI Express 5 x16` "NIC Slot" designations exist (Slots 1,2,4,5,6,7 — domains 0000,0002,0006,0010,0012,0016), and the BIOS `Bios/Attributes` payload shows **exactly six** `DisableOptionROM: true` entries, all on `x16`-width slots specifically: `Socket0Pcie0`, `Socket0Pcie2`, `Socket0Pcie6`, `Socket1Pcie0`, `Socket1Pcie2`, `Socket1Pcie6`. Count and width class both match precisely. Meanwhile the 1G port's slot (NIC Slot 3, domain `0005`) is a different class entirely — `x1 PCI Express 3 x1`, not one of the six flagged x16 slots.

**Working conclusion (strong inference, not a confirmed 1:1 documented mapping):** this platform's BIOS appears to deliberately disable PCIe option-ROM execution on all six large fabric-facing NIC slots (4× ConnectX-8 + 1× BlueField-3, `NIC Slot 4` currently unpopulated) — consistent with these being intended purely as data-plane/fabric interfaces (IB/RoCE, GPU-to-GPU, NVSwitch-adjacent), never as host boot devices — while deliberately leaving option ROM enabled only on the small onboard-style 1G management port (NIC Slot 3), which is the one NIC meant for host provisioning/PXE. This is architecturally coherent, not just a coincidence: it would explain, in one consistent story, both why the 1G port has always been the only PXE-capable option and why converting BF3/CX8 to Ethernet link type (9ac) did not — and structurally could not — produce a new PXE boot option, regardless of link type or `EXP_ROM_PXE_ENABLE` being `True` at the NIC level.

**Explicit limits on this conclusion:**
1. The exact `Socket*Pcie*` attribute → physical "NIC Slot N" mapping is **inferred from matching counts and widths, not confirmed via any documented 1:1 correlation** (e.g., no `dmidecode`/Redfish field directly named both a physical slot and its corresponding BIOS attribute key).
2. **Not recommended to flip any `Socket*Pcie*DisableOptionROM` setting on this live node without confirming the exact mapping first** (OEM platform documentation for "CARLO_NEXT-T1," or direct confirmation from NVIDIA/vendor support) — an incorrect guess could disable option ROM on an unrelated PCIe root port with unknown consequences on live production-track hardware.
3. This finding does not change or roll back the completed link-type change (9ac, confirmed durable at the NIC level) — it only explains why that change alone was never going to be sufficient to produce a PXE boot option for BF3/CX8, given the BIOS-level gate sitting above it.

**Recommendation:** treat enabling BF3/CX8 as PXE-bootable via BIOS option-ROM changes as a separate, higher-risk follow-up requiring vendor/OEM confirmation of the exact slot mapping — not something to attempt via inference on live rack08 hardware mid-rollout. The customer's stated Ethernet-mode requirement (link type) is satisfied and durable; PXE-boot-capability on those same ports is a distinct, unresolved, and higher-risk question.

### 9ae. Versioning added to both scripts

Added `SCRIPT_VERSION`, a header changelog block, and a `--version`/`version` way to print it, to both `pxe_rack_provision.sh` and `rack_lifecycle.sh` — no other functional changes in this pass.

- **`pxe_rack_provision.sh` → 1.2.0.** Changelog documents the three revisions made this session: 1.0.0 (original), 1.1.0 (`--node` range support, 9s), 1.2.0 (`--pxe-method ipmitool|redfish`, 9z). `--version` flag added; also printed in the pre-run summary line so it's visible on every real/dry run, not just when explicitly requested.
- **`rack_lifecycle.sh` → 1.0.0.** No functional changes made yet this session (still matches the originally-uploaded copy) — version/changelog scaffolding only, so future changes to this script have somewhere to record against. `version` subcommand added (consistent with its existing subcommand style, e.g. `rackgroups`), plus `--version` as an alias; both short-circuit before any target-selection logic runs (doesn't require `--ip-range`/`--rackgroup`/etc. just to print a version).

Both verified via `bash -n` (syntax) and direct invocation (`--version`/`version` print correctly; existing dry-run behavior on `pxe_rack_provision.sh` reconfirmed unaffected).

### 9af. Peer-provisioning exercise: definitively did NOT work — role config alone is not sufficient

**Confirmed via `rack08node01`'s own `rsyncd.log`** (BCM's provisioning transport, confirmed rsync-based via the `provisioningtransport` device property seen earlier):
```bash
grep 'Sep 17' /var/log/rsyncd.log | wc -l   # → 0 (not just 0 from other node IPs — zero activity at all today)
ls -la /var/log/rsyncd.log                  # last modified Sep 16 19:40 (rack08node01's own original install, not today)
```
**Zero connections from any of the other 16 `rack08group` nodes** (`10.141.168.103`–`.118`) during the entire `12:40`–`~13:42`+ provisioning window on `2026-09-17`. This is a clean, definitive negative result, not an inconclusive one.

**Conclusion: the `provisioning` role setup from 9p (`assign provisioning`, `set localimages baseos-1032-doca341`, `set categories maxQ-1032-doca341`, confirmed correctly committed via `roles; use provisioning; show`) was never actually engaged by BCM's node-installer for the other 16 nodes.** They provisioned via some other path — almost certainly the default fallback of pulling directly from the head node, same as `rack08node01` itself did originally. **Configuring a node's `provisioning` role scope alone does not make BCM prefer it as a source** — this confirms and closes the open question flagged in 9p ("not yet validated whether peer-to-peer selection actually happens automatically once the role is set").

**Not yet determined: what the missing piece actually is.** Plausible candidates, none confirmed this session:
- A category-level or network-level explicit "preferred provisioning source" setting that needs separate configuration beyond the role itself.
- The `provisioning` role's own `nodegroups`/`racks` properties (left unset in 9p — only `localimages` and `categories` were set) may need to be populated to actually scope *which nodes* should use this source, rather than the role passively existing and hoping the right nodes discover it.
- BCM's provisioning-source selection algorithm may factor in something else entirely (network topology/proximity awareness, load-based selection, an explicit per-category `provisioninginterface` binding) that wasn't investigated.

**Timing context (approximate, not precise per-node data):** batch of 17 started ~12:40; `rack08node02` was already in confirmed steady-state (DCGM connected, monitoring active) by ~13:41–13:42, i.e. roughly 61+ minutes elapsed for at least partial batch completion — notably longer than `rack08node01`'s own solo run (~16 minutes). Consistent with (though not proof of) all 17 nodes contending for the head node directly with no load-spreading from peering. Precise per-node start/end timestamps were not captured this session (nobody was watching the live `cmsh` event stream during this run, unlike the node01 exercise) — for future batches, watch the live stream or tee `pxe_rack_provision.sh`'s own output to get real per-node timing rather than reconstructing after the fact.

**Recommendation:** if peer-provisioning is worth pursuing further, the next step is investigating BCM's actual provisioning-source-selection mechanism (documentation or NVIDIA/Bright Computing support) rather than assuming the role's `localimages`/`categories` properties are sufficient on their own — they clearly are not, based on this direct evidence.

### 9ag. Precise per-node provisioning timing — confirms head-node contention (not peering) caused a bimodal slowdown

Computed from real log timestamps: start = each node's first `DHCPACK` (node-installer's own boot, `journalctl -u dhcpd`), end = each node's second `DHCPACK` (final OS reboot) immediately followed (~30s later) by cmdaemon's `Run special node settings: .../update-node-params.py` line (`/var/log/cmdaemon`, filtered to `Sep 17` — the `10:40:28`-`10:40:38` wave in this same log is unrelated, predates the 12:40 batch start entirely, likely a periodic cron-style task, not investigated further).

**Fast group (9 nodes, 15m53s–27m33s):** node13, node11, node08, node12, node10, node09, node17, node15, node14.
**Slow group (8 nodes, 55m39s–1h01m43s):** node02, node05, node18, node04, node16, node06, node07, node03.

**Total batch wall-clock: 12:44:58 → 13:47:48 = 1h02m50s** for all 17 to complete.

**Key finding: node13 (fastest, 15m53s) is essentially identical to `rack08node01`'s own precisely-measured solo run (16m12s, 9r).** This confirms ~16 minutes is the genuine baseline per-node install time on this hardware/image under no contention. The other 8 nodes took **3.5-4x longer** than that baseline — a clean bimodal split (9 fast / 8 slow), not a smooth distribution, consistent with queuing/contention at a shared resource rather than per-node hardware variance.

**Directly corroborates 9af's negative peering finding rather than sitting separately from it:** since peer-provisioning was confirmed to never engage (zero rsync connections to `rack08node01` from any of the other 16 nodes), all 17 genuinely contended for the head node simultaneously — this timing data quantifies the real cost of that: roughly half the rack paid a 3.5-4x time penalty. If peer-provisioning were made to actually work (the open item from 9af/9p), this contention penalty is the concrete, measured problem it would need to solve.

**Recommendation for future batches of this size:** either get peer-provisioning genuinely working first (see 9af's open questions), or use `pxe_rack_provision.sh --delay <N>` to stagger the batch deliberately, trading a longer *scheduled* rollout for avoiding this unscheduled, uneven 3.5-4x contention penalty on whichever nodes happen to queue behind others.

### 9ah. Root cause of peering failure and the 9/8 timing split — found in the BCM Administrator Manual, not by further trial-and-error

User provided the actual BCM Administrator Manual (PDF, 1090 pages) after several rounds of live-hardware guessing failed to find the real mechanism. Searched directly (§5.2 "Provisioning Nodes") rather than continuing to guess `cmsh` commands blind.

**Key documented facts, verbatim from the manual:**

1. **"The head node also always has a provisioning role"** — `rack08node01`'s role was never a *replacement* for the head node as a source; it was always competing *alongside* the head node's own implicit provisioning role. This reframes the entire exercise: there was never a scenario where "the head node" wasn't a candidate.

2. **Provisioning Node Selection (§5.2.4):** *"When a node requests provisioning, the head node allocates the task to a provisioning node. If there are several provisioning nodes that can provide the image required, then the task is allocated to the provisioning node with the lowest number of already-started provisioning tasks."* — Selection is load-based (task count), not proximity/GNSS/config-scope-based. Our `localimages`/`categories` settings on `rack08node01`'s role only ever controlled *eligibility*, never *preference*.

3. **Eligibility is tracked, not inferred from disk contents:** *"CMDaemon tracks the provisioning nodes role changes, as well as which provisioning nodes have up-to-date images available"* (§5.2.2) — a provisioning node's local files matching the target image by coincidence is **not** the same as CMDaemon's own internal bookkeeping recognizing it as eligible. The canonical path to that recognition is the `updateprovisioners` command (§5.2.4), which runs automatically on role-property changes, or on a request when CMDaemon itself is driving an image change.

4. **Likely actual root cause of zero engagement:** `rack08node01`'s role scope (`localimages`/`categories`) was set (9p) **before** the node had `baseos-1032-doca341` installed on itself at all — `updateprovisioners` ran then, with nothing yet to sync. The node later acquired the image through a **normal client FULL install** (PXE/node-installer), not through the `updateprovisioners` push mechanism. Per the manual's distinction between these two pathways, this plausibly means CMDaemon's internal "has up-to-date images" tracking was **never actually updated** for `rack08node01` after its own install completed — it may have remained perpetually ineligible despite having the correct files on disk, explaining the clean **zero** engagement (9af) rather than a partial/statistical split.

5. **Provisioning Tasks Deferral (§5.2.4), directly explains 9ag's bimodal timing split:** *"A provisioning request is deferred if the head node is not able to immediately allocate a provisioning node for the task. Whenever an ongoing provisioning task has finished, the head node tries to re-allocate deferred requests."* Combined with **`Provisioning Slots` defaulting to 10** per provisioning node (§5.2.1) and **`MaxNumberOfProvisioningThreads` defaulting to 10000** cluster-wide (Appendix C — confirmed NOT the bottleneck, far too high) — if all 17 requests landed on the head node's own implicit provisioning role alone (per point 4), its default 10-slot cap would explain the fast/slow split almost exactly: ~9-10 nodes served immediately, the remainder deferred until a slot freed, closely matching both the group sizes (9 fast / 8 slow) and the ~40-45 minute gap between them.

**Recommended fix for the next batch (not yet applied to this already-completed rollout):**
```bash
# After rack08node01's own install completes and is confirmed healthy,
# BEFORE rebooting the other 17 - forces CMDaemon to explicitly
# re-register the node as having a genuinely up-to-date image:
cmsh -c "softwareimage; updateprovisioners baseos-1032-doca341"

# Also worth checking/raising the head node's own implicit provisioning
# role's Provisioning Slots if it's still at the default 10:
cmsh -c "device use bcm11-headnode; roles; use provisioning; show"
```

**Not yet re-tested this session** — this is a documented, well-supported explanation, not yet re-validated by actually running `updateprovisioners` and re-checking `rack08node01`'s rsync log on a future batch. Treat as the leading hypothesis, confirm with real evidence next time rather than treating as fully closed.

**Broader lesson for this whole investigation:** several rounds of plausible-sounding but wrong guesses (`minimalloadforoffload`'s real meaning turned out to be about keeping provisioning nodes' own cached images in sync, not routing client installs; head-node CPU load was correctly ruled out but for a different reason than assumed) were resolved quickly once the actual manual was searched directly. Worth checking documentation before further trial-and-error on live hardware for BCM-specific mechanisms generally, not just this one.

### 9ai. CONFIRMED: `rack08node01`'s image was never recognized as up-to-date by CMDaemon until `updateprovisioners` was run manually

```
[bcm11-headnode->softwareimage]% updateprovisioners
updateprovisioners [ COMPLETED ]
Thu Sep 17 15:03:13 2026 [notice] bcm11-headnode: Provisioning completed: sent
  bcm11-headnode:/cm/images/baseos-1032-doca341 to rack08node01:/cm/images/baseos-1032-doca341,
  mode UPDATE, dry run = no
```

This confirms 9ah's central hypothesis directly: if CMDaemon had already tracked `rack08node01` as having an up-to-date copy of `baseos-1032-doca341` (which it did, physically, on disk — that's what it had just finished installing as its own OS), this command would have been a no-op. **It explicitly sent/updated the image instead** — proving CMDaemon's own internal "provisioning nodes with up-to-date images" state genuinely did not recognize `rack08node01` as eligible, despite the files being physically correct. The node's own normal client FULL install never satisfied CMDaemon's tracked-eligibility requirement — only an explicit `updateprovisioners` run does that.

**This is now the confirmed root cause of the peering failure (9af), not just a hypothesis.** For the next rack of this kind, running `softwareimage updateprovisioners` (scoped to the target image, or run for all) **after the designated provisioning node's own install completes and before rebooting the rest of the rack** should make it genuinely eligible for selection — closing the loop that caused zero engagement and the resulting 3.5-4x contention penalty on 8 of 17 nodes (9ag).

**Not yet re-validated end-to-end** — this rack's 17 nodes are already provisioned, so there's no further live test to run against them specifically. The confirmed fix should be written into the SOP as a required step before the next new rack/category's rollout, and validated for real on that occasion (checking `rack08node01`'s — or the next rack's provisioning node's — rsync log afterward, same method used to detect the original failure).

### 9aj. `rack_lifecycle.sh` modified — `--with-pre-diag` flag added to `handoff` (1.0.0 -> 1.1.0)

Added an opt-in `--with-pre-diag` flag to the `handoff` subcommand that runs `pre-diag` on each node immediately after `handoff` completes, in the same invocation. Deliberately **not** folded into `handoff` unconditionally — `handoff` (moving off the BCM network) and `pre-diag` (about to run diag tooling, disables `cuda-dcgm`) are different lifecycle moments that don't always happen back-to-back; making `pre-diag` automatic would lose GPU monitoring on any rack that isn't starting diag testing immediately.

**Validated:** rejects `--with-pre-diag` on any subcommand other than `handoff`; dry-run confirms `do_pre_diag` correctly chains after `do_handoff` for each target when the flag is set.

**Separately, an unresolved bug surfaced this session during rack08's real handoff run:** `cmsupport` ended up present in **neither** LDAP-resolvable form nor as a local account on all 18 nodes after handoff (`grep cmsupport /etc/passwd` and `/etc/group` both empty). Initial theory (step 1's DNS edit breaking step 2's `id cmsupport` check) was **disproven** — `getent hosts ldapserver` resolves fine via static `/etc/hosts`-style cluster aliases, independent of the DNS setting that was changed. Root cause not yet found; the console output from the actual `handoff` run (not the dry-run, which doesn't execute anything) would show which branch step 2 took on each node and hasn't been captured/reviewed yet. **Not yet fixed in the script** — needs the real root cause before changing step 2's logic, to avoid guessing a fix for the wrong problem a second time. Immediate mitigation (manually recreating `cmsupport` locally with the known `uid=1000, gid=1000, group=pega` values) was offered but not yet confirmed as executed.

**Correction to 9aj, same session:** user correctly flagged that `handoff`'s changes are one-way — there is no rejoin/finalize path implemented in this script at all, so a node never returns to BCM-managed state on its own or via reboot. This is a materially different kind of permanence than `pre-diag`'s `cuda-dcgm` disable, which **is** reversible afterward via `post-diag` (confirmed this works via local `systemctl` + a local state file only, no BCM/LDAP connectivity required, so it functions fine even on an already-handed-off node). The two actions `--with-pre-diag` compounds have **asymmetric reversibility** — worth being precise about rather than treating them as equivalently "different lifecycle moments."

**Script strengthened accordingly:** `--with-pre-diag` now requires an explicit typed `yes` confirmation (skipped only under `--dry-run`) stating this asymmetry plainly before proceeding, rather than just a passive header comment. Verified: `--dry-run` skips the prompt entirely; rejecting the prompt aborts cleanly (exit 1) before touching any node; accepting proceeds normally to `do_handoff` + `do_pre_diag`.

### 9ak. CONFIRMED: `pre-diag` fix works — CMDaemon-level `monitored: no` stops the silent restart; `failed` state was a benign ExecStop race

Real test on rack08: after applying `services; add cuda-dcgm; set monitored no; set autostart no; commit` via `device foreach -g rack08group (...)` (device-level override, confirmed via `services; list` showing `cuda-dcgm no no` with no bracket prefix — genuine device-level entry, not the implicit `[general]` one), ran `pre-diag --rack 8` for real, waited, and confirmed via `journalctl`: **no new restart occurred** — `Active: inactive (dead)` held after `reset-failed`, unlike every prior attempt where CMDaemon revived it minutes later.

**The `active=failed` state seen in `status` right after `pre-diag` is benign, not a new problem:**
```
nv-hostengine pidfile /var/run/nvhostengine.pid could not be read.
Unable to terminate host engine, it may not be running.
cuda-dcgm.service: Control process exited, code=exited, status=1/FAILURE
```
`systemctl disable --now` kills the main process cleanly first (`ExecStart` shows `status=0/SUCCESS`); the unit's own `ExecStop` script then runs anyway, finds no pidfile (process already gone), exits 1, and systemd reports that as `failed` even though the actual outcome (`nv-hostengine` not running) is exactly correct. `systemctl reset-failed` clears the cosmetic state with no functional effect — confirmed `inactive (dead)` afterward, no auto-clear on its own needed.

**Confirmed complete fix sequence for a real diag campaign, going forward:**
1. `cmsh -c "device foreach -g <nodegroup> (services; add cuda-dcgm; set monitored no; set autostart no; commit)"` — from the head node, **before** `pre-diag`. This is the piece that actually stops CMDaemon reviving the service; without it, `pre-diag`'s systemd-level disable is silently undone within minutes.
2. `bash ./rack_lifecycle.sh pre-diag --rack <N>` (or `--with-pre-diag` combined with `handoff`) — now genuinely durable.
3. After diag testing: `post-diag` restores `cuda-dcgm`'s systemd state; separately, `cmsh -c "device foreach -g <nodegroup> (services; use cuda-dcgm; set monitored yes; set autostart yes; commit)"` (or `services; remove cuda-dcgm; commit` to fall back to the `[general]` default) restores CMDaemon-level monitoring — **not automatic**, must be done separately, easy to forget.

**Script fixes applied (1.1.0 -> 1.2.0):**
- Fixed a real bug in `do_status`: `$(systemctl is-active X 2>/dev/null || echo fallback)` concatenated the command's real stdout (printed even on non-zero exit, e.g. `failed`/`inactive`) with the fallback text, producing garbled multi-line output — exactly what was seen in the `status --rack 8` transcript after `pre-diag`. Fixed via two-step variable capture (`VAR=$(cmd 2>/dev/null); echo "${VAR:-fallback}"`) instead of the `||` chain, for both `nslcd` and `cuda-dcgm` status lines.
- `pre-diag` now runs `systemctl reset-failed cuda-dcgm.service` automatically after disabling it, and prints an inline reminder of the required CMDaemon-level fix (with the exact command), since that fix cannot be run from within this script itself (requires `cmsh` on the head node; this script is designed to run from any jump host).

**Not yet folded into the script directly**: the CMDaemon-level `services` fix itself, since it requires `cmsh`/head-node access this script doesn't assume. Currently a documented manual step (in the script's own inline reminder and here) rather than automated — worth reconsidering if this workflow becomes routine enough to justify breaking the jump-host-portability assumption.

### 9al. `rack_lifecycle.sh` — CMDaemon-level `cuda-dcgm` monitoring disable folded into `handoff` itself (1.2.0, same version — pre-release addition)

Per explicit request: the confirmed fix from 9ak (`cmsh ... services; add cuda-dcgm; set monitored no; set autostart no; commit`) is now run **automatically as part of `handoff`**, not left as a manual step or tied to `--with-pre-diag`. Added `disable_cmdaemon_dcgm_monitoring()`, called once (not per-node) right before the main per-target dispatch loop, only for the `handoff` subcommand.

**Design constraints handled:**
- This command needs `cmsh` on the machine running the script, and operates on the whole target list in one call — a different shape than the rest of the script's per-node SSH loop. Only fires automatically when targets were resolved via `--rack`/`--category` (which already proves `cmsh` is reachable, since that's how those hostnames got resolved). For `--ip-range`/`--rackgroup` targeting, prints a clear manual-fallback command instead of guessing at `cmsh` availability — those paths are typically already-handed-off, IP-addressed racks where `cmsh`/hostname resolution isn't guaranteed anyway.
- Explicitly a **smaller, different, more permanent** action than `pre-diag`: only stops CMDaemon's own monitoring/auto-restart of `cuda-dcgm` — does not stop the service itself. Documented inline (printed at runtime) so this isn't silent, along with the exact reversal command (`services; use cuda-dcgm; set monitored yes; set autostart yes; commit`) — **not** automatically undone by `post-diag`, which only manages the systemd-level state.
- Respects `--dry-run` (prints the command instead of running it).

**Syntax verified against the BCM admin manual before implementing** (given several prior guessed-`cmsh`-syntax failures this session): confirmed comma-separated `foreach -n` lists are valid (`foreach -n node001,node008..node016,node032`, manual example), and confirmed the exact `services; add <name>; set ...` chain pattern is a documented example — with one deliberate deviation: the manual's example issues `commit` as a separate top-level command after the `foreach` block, while this script keeps `commit` inside the parentheses (as we did tonight, and independently confirmed working live via `services; list` afterward) — kept the empirically-validated-on-this-cluster form over the textbook form.

**Tested:** both fallback branches (empty `CATEGORY_TARGETS`, missing `cmsh`) verified correct via isolated logic test — this sandbox has no `cmsh` binary, so the actual `cmsh` invocation branch could not be exercised end-to-end here; its command construction is identical to the already-manually-verified-working command from earlier in this session, just parameterized with the resolved hostname list.

### 9am. Root cause of DNS/cuda-dcgm reversion found: category exclude lists don't cover the files we edit — AND category commits trigger a rack-wide service re-sync

**Confirmed via `excludelistupdate`/`excludelistsyncinstall` comparison against what `handoff`/`pre-diag` actually edit:**
- The exclude list protects `/etc/resolv.conf` — but `handoff` edits **`/etc/systemd/resolved.conf`** (a different file, the resolved daemon's own config containing the `DNS=` line). Not excluded at all — any category sync is free to restore it from the image.
- The exclude list has explicit `/etc/systemd/system/*.wants/<service>.service` entries for many named services (`dhcpd`, `munge`, `slurmd`, etc.) but **no entry for `cuda-dcgm`** — any sync is free to recreate `multi-user.target.wants/cuda-dcgm.service`, silently re-enabling it. This exactly matches the `"Removed .../multi-user.target.wants/cuda-dcgm.service"` line `pre-diag` printed on several nodes earlier in this session.

**Fix applied:** added both missing paths to `excludelistupdate` and `excludelistsyncinstall` at the `maxQ-1032-doca341` category level:
```
- /etc/systemd/resolved.conf
- /etc/systemd/system/*.wants/cuda-dcgm.service
```
Edited via `cmsh`'s interactive editor (`category use maxQ-1032-doca341; set excludelistupdate` — opens `vi`, no non-interactive `append` shortcut exists for this property per the admin manual). Confirmed present in both lists via `get` afterward.

**Major new discovery, bigger than the exclude-list gap itself:** immediately after `commit`-ing this **category-level** change (unrelated to services), CMDaemon fired `Service cuda-dcgm was started` on **all 18 nodes simultaneously** — silently undoing `pre-diag`'s stop across the entire rack as a side effect of an unrelated category commit. `rack08node02` additionally hit `"Service cuda-dcgm was not started (init.d script timeout)"` during this restart storm (later confirmed benign — clean `inactive (dead)` state after a manual `pre-diag` re-run, no orphan process, port 5555 free).

**Operational implication for the SOP, more important than the exclude-list fix itself:** ANY category-level `commit` — not just service-related changes — appears to trigger CMDaemon to re-assert/re-sync service state across the whole category, which can silently re-enable `cuda-dcgm` on nodes that were deliberately stopped for active diag testing. **This means `pre-diag` must be treated as fragile against any subsequent category-level change during a live diag campaign, not a one-time "set and forget" action.** Recommend: avoid category-level `commit`s entirely during an active diag campaign on that category if at all possible; if one is unavoidable, immediately re-run `pre-diag --rack <N>` afterward and verify via `status` before trusting the rack's diag-safe state again.

**Not yet fully explained:** why a category commit re-triggers service state assertion even when the CMDaemon-level `services` override (`monitored: no`, `autostart: no`, confirmed intact via `services; list` earlier) should have suppressed exactly this behavior. Possible explanations not yet tested: the override itself gets briefly reset/reprocessed during a category commit's internal re-sync before being reapplied, or the actual restart trigger is a different mechanism entirely (the periodic sync onto disk restoring the `.wants/` symlink, with systemd's own `multi-user.target` then starting anything newly present there, independent of CMDaemon's `monitored` flag). Worth a longer-window observation test (make an unrelated category commit, immediately check `cuda-dcgm` state on all nodes) to isolate this precisely, rather than treating it as settled.

### 9an. `provisioningslots` raised to 18 made batch provisioning SLOWER, not faster — real head-node bandwidth bottleneck, not a connection-count limit

Following up on 9ag's finding (default `Provisioning Slots: 10` correlating with the 9-fast/8-slow split on rack08's 17-node batch), raised the head node's own implicit `provisioning` role to `provisioningslots 18` (intending to remove the queuing bottleneck entirely) and tested on `rack01`'s 18-node batch (same conditions otherwise: no peer-provisioning node configured, category `maxQ-1032-doca341`).

**Result: batch took ~2h24m total** (`17:47` first `INSTALLING` → `20:07` last `UP`), compared to rack08's ~1h03m for 17 nodes under the old 10-slot cap — **roughly 2.3x slower**, despite removing the concurrency limit that was causing nodes to queue.

**Confirmed via user: `provisioningslots 18` was committed before this batch was triggered** — not a mid-flight change, so the full batch ran under the new setting throughout.

**Conclusion: the head node's real constraint is disk/network transfer bandwidth, not the number of concurrent connections.** The old 10-slot cap wasn't an arbitrary throttle causing unwanted queuing — it was inadvertently protecting per-node transfer speed by limiting how many image transfers competed for the same finite pipe simultaneously. Raising the cap let all 18 nodes contend for that same fixed bandwidth at once; each individual transfer slowed down enough that total wall-clock time got substantially worse, not better. This directly contradicts the intuitive assumption that removing a concurrency cap should only help.

**Action taken: reverted `provisioningslots` back to `10`**:
```bash
cmsh -c "device use bcm11-headnode; roles; use provisioning; set provisioningslots 10; commit"
```

**Not yet empirically tuned to an actual optimum** — `10` is the known-working default, not confirmed as the best value. If this matters for future large batches, worth a controlled test sweeping a few values (e.g. 6, 10, 14) against the same rack size to find the real throughput-optimal concurrency, rather than assuming the original default is precisely correct just because it's better than 18.

**Separately, positive findings from this same rack01 batch, worth noting:**
- `ntp` and `ldap` both showed clean, fast `PASS` on every one of the 18 nodes (seconds to ~2 minutes after `UP`) — a genuine improvement over the persistent issues fought all session on `rack08`'s category/image history. Not yet understood why this category behaves better for these two checks specifically — worth a comparison if it matters later.
- `"Reboot required: Interfaces have been modified"` fired on literally every node in this batch, not just isolated cases — confirms this is a routine, universal post-install artifact (already suspected from a single rack08 occurrence, now confirmed universal) rather than something node-specific or concerning. No observed negative effect on any node's subsequent health.

### 9ao. CORRECTION to 9an: the rack08-vs-rack01 comparison was confounded by different switch hardware

**Important correction:** 9an's conclusion ("raising `provisioningslots` to 18 caused the 2.3x slowdown") compared `rack08`'s batch against `rack01`'s batch as if `provisioningslots` were the only variable — but **`rack01` uses a different physical switch (HPE 5410) than whatever `rack08` is on.** This is a real confound: switch backplane bandwidth, port speed, and buffering behavior could account for some or all of the timing difference, independent of the slot-count change. 9an's finding should be treated as a **plausible but unconfirmed** hypothesis, not a clean result, until re-tested with the switch held constant.

**Corrected experimental plan:** re-test on `rack01` again (same switch, same category/image), this time with `provisioningslots` set to `9`, to isolate the slot-count variable properly against the already-collected `18`-slot rack01 baseline (~2h24m, 9an). This is a genuine same-rack, same-switch A/B comparison, unlike the original rack08-vs-rack01 comparison.

```bash
cmsh -c "device use bcm11-headnode; roles; use provisioning; set provisioningslots 9; commit"
```
Then a fresh full reinstall of all 18 rack01 nodes, timed the same way as before (first `INSTALLING` → last `UP`, per-node via `DHCPACK`/`Run special node settings` if precise per-node timing is wanted again per 9ag's method).

**Once this second data point exists, three-way comparison becomes possible:** rack01 @ 18 slots (~2h24m, confounded baseline) vs. rack01 @ 9 slots (pending) vs. rack08 @ 10 slots on its own switch (~1h03m, different hardware). If rack01 @ 9 slots comes in dramatically faster than rack01 @ 18 slots, that supports 9an's bandwidth-contention theory on this switch specifically. If it's similar to the 18-slot result, the switch hardware itself (or something else about rack01 specifically) is the more likely explanation, and the slot-count theory from 9an would need to be reconsidered.

### 9ap. `provisioningslots 9` — queuing behavior directly observed and confirmed (not just inferred from timing)

Unlike the original `rack08`/10-slot and `rack01`/18-slot batches (where slot-limited queuing was only inferred after the fact from timing gaps), this batch's queuing was directly observed live via `cmsh -c "device; list"` and `device status`:

- **9 nodes actively transferring:** `device status` shows `"provisioning started (FULL), waiting for completion)"`.
- **9 nodes queued:** `device status` shows the distinct, explicit wording `"waiting for FULL provisioning to '/' to start"`.

This is a clean, unambiguous, directly-observed confirmation that `provisioningslots` genuinely gates concurrent transfers at exactly the configured value (9) — not something inferred from a bimodal timing distribution after the fact, as it was for the original `rack08` batch (9ag).

**Correction/clarification carried over from 9ao's confound-flagging:** the earlier `rack01` all-`DOWN` status and `ssh ... uptime` check that triggered a false alarm (suspected category-commit side effect, suspected outage) was resolved as normal batch-in-progress behavior — `rack01node01` had already completed its own install (`uptime`: "up 7 min") while BCM's own per-node status still lagged showing `"waiting for completion"`. No actual incident occurred; the earlier `excludelistupdate`/`excludelistsyncinstall` edit (9am) was confirmed by the user to have happened **before** this test entirely, not concurrently — ruling it out as a contributing cause for this batch specifically.

**Pending:** final batch completion time and per-node timing breakdown for the clean rack01-same-switch, 9-slot vs. 18-slot comparison (9ao's corrected experimental plan). Will follow up once the batch finishes.

### 9aq. Switch hardware, not `provisioningslots`, is the likely real bottleneck — slot count change produced negligible improvement

Completed the corrected same-switch A/B test from 9ao: `rack01` (HPE5410 switch) re-provisioned at `provisioningslots 9`, compared against the prior `rack01`/HPE5410 run at `provisioningslots 18`.

**Results:**
- `rack01` @ 18 slots: `17:43:43` → `20:06:59` = **2h23m16s** (18 nodes)
- `rack01` @ 9 slots: `08:57:06` → `11:15:13` = **2h18m07s** (18 nodes)
- **Halving the slot count saved only ~5 minutes (~3.6%)** — nowhere near proportional to the 2x concurrency reduction. This strongly suggests `provisioningslots` was never the dominant lever on this hardware.

**Compared against `rack08` (switch model "5120" per user, `provisioningslots 10`, 17 nodes): ~1h03m total** — roughly **2.2x faster** than either `rack01`/HPE5410 result, despite a similar node count and a slot setting between the two `rack01` tests. This gap tracks consistently with switch hardware, not with the BCM-side setting tuned across these tests.

**User's hypothesis, well-supported by this data: the HPE5410 switch itself (not `provisioningslots`) is the real bottleneck for `rack01`'s batch-provisioning throughput.** Recommended next diagnostic (not yet run): check actual **negotiated** link speed on the provisioning NIC directly, rather than assuming from switch model/datasheet specs:
```bash
ssh rack01node01 "ethtool enP5p9s0 | grep -i speed"
```
If this shows a lower-than-expected negotiated speed (e.g., falling back to 1G), that alone could explain the gap independent of the switch's rated capability — a cabling, SFP, or autonegotiation issue rather than a switch-capacity ceiling per se. Worth checking before concluding it's a hardware capacity limit rather than a misconfiguration.

**Action recommended: revert `provisioningslots` to `10`** (matching `rack08`'s known-working value) since this data shows it isn't the primary lever for `rack01`'s slowdown — no further slot-tuning experiments are likely to yield meaningful improvement until the actual switch/link-speed question is resolved.

**Positive/neutral finding carried forward from this run too:** the universal `"Reboot required: Interfaces have been modified"` warning on every node (confirmed again, consistent with 9an) continues to show no observed negative impact on node health — same benign pattern as before.

### 9ar. CONFIRMED root cause: `rack01`'s provisioning NIC is negotiating at only 1Gb/s

```bash
ssh rack01node01 "ethtool enP5p9s0 | grep -i speed"
# Speed: 1000Mb/s
```

**This fully explains the ~2.2x+ slowdown versus `rack08`** (9aq) without needing switch-model speculation — a 1G link is a hard bandwidth ceiling for full-image transfers to 18 nodes, regardless of `provisioningslots` tuning. This settles the `provisioningslots`-vs-switch question from 9aq/9ao in favor of the switch/link-speed explanation: the negligible improvement from 18→9 slots (9aq) makes complete sense if the actual constraint is a fixed 1Gb/s pipe rather than a concurrency limit.

**Switch corrected: rack01's switch is model 5140 (HPE), not 5410 as earlier stated** — no switch-side console access available at time of this finding (no password on hand for the `5140`). Diagnosis proceeding from the node side first.

**Immediate follow-up check requested, not yet run:**
```bash
ssh rack01node01 "ethtool enP5p9s0 | grep -iE 'speed|supported link|advertised link'"
```
To determine whether the NIC itself is only capable of 1G (unlikely for this hardware class, but worth confirming) or capable of more and simply negotiated down — which would point at a cable/SFP/port-configuration issue rather than a hardware capability ceiling.

**Also requested, not yet run:** checking the head-node-side interface facing rack01's segment for its own negotiated speed, to determine whether this is a two-sided negotiation problem or isolated to this one link/port.

**Not yet actionable:** no credentials currently available for the `5140` switch itself to check/correct port speed configuration directly. This is the most likely next step once access is available, given a fixed 1G negotiation between two 10G+-capable endpoints commonly indicates a switch port hard-set to 1G, a faulty/mismatched SFP, or an autonegotiation failure that a switch-side port reset/reconfiguration would resolve.

### 9as. CORRECTION to 9ar: the 1G link speed is likely normal/expected for this port, not a rack01-specific problem — premature conclusion

**Retracting 9ar's "CONFIRMED root cause" framing.** Two things missed at the time:

1. **The `ethtool` output itself was internally inconsistent** and should have been a red flag: `Supported link modes: 10baseT/Half 10baseT/Full` (10 **Megabit**) while `Speed: 1000Mb/s` — the reported speed exceeds what the same command claims is supported. This is a known quirk of some onboard/management NIC drivers misreporting supported/advertised fields while `Speed` reflects the real link rate — not something that should have been treated as clean, reliable evidence without noting the inconsistency.

2. **`enP5p9s0` is the identical "1G management/provisioning port" already mapped platform-wide in §9ad** — the single PXE-capable NIC on this hardware design, present identically on every node on every rack (`rack08` included), not something specific to `rack01`. A `1000Mb/s` reading here is very likely this port's normal, full rated speed by design, not a degraded/misconfigured value unique to this rack.

**Corrected reasoning:** since both racks provision over an architecturally identical 1G-capacity port, that fact alone cannot explain why `rack01` (2h18-2h23m) took ~2.2x longer than `rack08` (~1h03m) — a shared, by-design constraint doesn't produce a between-rack difference. The real explanatory variable must be something that actually *differs* between the two setups.

**Corrected next step (requested, not yet run):** check `rack08`'s equivalent reading for direct comparison:
```bash
ssh rack08node01 "ethtool enP5p9s0 | grep -iE 'speed|supported link|advertised link'"
```
- If `rack08` shows the same `1000Mb/s`, this NIC-speed line of investigation is a dead end, and the real difference is more likely switch-side: port-level errors/retransmits, oversubscription ratio on the uplink, or a genuine per-port issue on the `5140` specifically that isn't visible from the node's own `ethtool` output at all.
- If `rack08` shows something different (higher), that would restore the original hypothesis, but on firmer ground than this session's premature conclusion.

**Lesson for the log itself:** a "CONFIRMED" label was applied one step too early in 9ar, based on a single data point without the necessary control comparison (the same reading on the already-fast rack). Worth being more conservative about the word "confirmed" until a genuine A/B point exists, not just a single plausible-looking number.

### 9at. Confirmed: NIC speed is identical on both racks — dead end, real difference must be switch-side

```bash
ssh rack08node01 "ethtool enP5p9s0 | grep -iE 'speed|supported link|advertised link'"
# Supported link modes:   10baseT/Half 10baseT/Full
# Advertised link modes:  10baseT/Half 10baseT/Full
# Speed: 1000Mb/s
```

**Identical to `rack01`'s reading** (same inconsistent 10baseT supported/advertised fields, same 1000Mb/s actual speed). Confirms 9as's correction: this is normal, expected behavior for this platform's onboard management/provisioning NIC on every node, not a `rack01`-specific NIC/negotiation fault. **This line of investigation is closed — dead end.**

**The real explanatory difference between `rack08` (~1h03m/17 nodes) and `rack01` (~2h18-2h23m/18 nodes) must be switch-side**, not node-side, given the node-side NIC configuration is now confirmed identical. Candidate causes for the next session, none yet checked:
- Port-level error counters on the switch ports serving `rack01` (CRC errors, retransmits, collisions) — a marginal cable/SFP/port issue can silently degrade effective throughput well below nominal negotiated speed without showing up in the node's own `ethtool` output.
- Uplink oversubscription ratio — how many 1G access ports share a single uplink on each switch, and that uplink's own capacity; 18 nodes sharing a more oversubscribed uplink on the `5140` vs. `rack08`'s switch could fully explain the gap.
- Switch model/generation differences in backplane capacity, buffering, or QoS/rate-limiting policy.

**Blocked pending `5140` switch credentials** (not available to the user as of this session) — this is the concrete next step once access is available: check per-port error counters and uplink utilization on the `5140` during a live batch, compared against the equivalent view on `rack08`'s switch if accessible.

### 9au. Topology clarified — shared 5140 switch, rack01 direct-attached vs rack08 via aggregation switch (5120); extra hop correlates with BETTER performance, a real and counterintuitive signal

**Confirmed topology, both racks:**
- `rack08`: `bcm head node → 5140 → 5120 → 18 rack08 nodes` (two switch hops)
- `rack01`: `bcm head node → 5140 → 18 rack01 nodes` (nodes attached directly to the 5140; the `5120` is also attached to this same `5140`, serving `rack08`)

**Critical clarification: the `5140` is a single switch shared by both racks** — not two separate units. Any concurrent `rack08`/`rack01` activity would contend for shared resources on this one switch (though no such overlap is currently known to have occurred during either timed test — see 9au's timestamps vs. `rack08` activity, mostly `Sep 17` evening vs. `rack01`'s `Sep 18` morning tests).

**Genuinely counterintuitive finding worth highlighting:** `rack08` has the *additional* switch hop (via `5120`) yet was ~2.2x **faster** than direct-attached `rack01` — the opposite of the naive "more hops = slower" expectation. This is a real signal, not noise, and reframes the investigation:

**Working hypothesis (not yet confirmed, no switch access available):** the `5120` may function as a dedicated aggregation switch, isolating `rack08`'s 18 nodes onto their own local fabric and presenting a single (likely higher-capacity) uplink back to the `5140`. `rack01`'s nodes, being directly attached to the `5140` itself, may instead be contending directly for that switch's own backplane/ASIC capacity alongside everything else connected to it — a structurally different (and potentially worse, if the `5140`'s per-port/backplane capacity is limited) traffic pattern than one aggregated uplink carrying the same total load.

**Concrete checks recommended once `5140` credentials are available, in order of expected diagnostic value:**
1. The `5140→5120` uplink port's own negotiated speed and utilization during a live `rack08` batch — if it's a single higher-speed aggregated link, that would structurally explain the advantage.
2. Per-port error/utilization counters on the specific `5140` ports `rack01`'s 18 nodes are directly attached to, during a live batch.
3. The `5140`'s overall backplane/switching capacity specification, since direct-attached end-host ports and an inter-switch uplink port can behave very differently under sustained load depending on internal switch architecture.

**Status: blocked on `5140` switch credentials**, same as 9at. This is now the clearly-scoped, single next step for the provisioning-throughput investigation — no further profitable action on the BCM/`provisioningslots` side is expected given 9aq/9at/9as/9ar's ruled-out findings.
