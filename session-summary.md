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

Image build is stable and reproducible (6f + 6g confirm it two different ways), though 6i found it's costing ~8.5 hours per build, dominated by a redundant DKMS/OFED cycle against an irrelevant kernel. 6k confirms DOCA/driver/IMEX are untouched and correct. **6l/6m: both `dgx_gb200` and `dgx_gb300` are now confirmed to build successfully — the production-named `baseos-1014-doca321` was most recently rebuilt with `--dgx-type dgx_gb300`, after a host-level `/dev` incident (6m) was resolved via reboot.** Which flag is *correct* for real GB300 NVL hardware is still open with NV; viability is not. Next:
1. **Verify, don't assume:** check whether `baseos-1014-doca321`'s current build already has the fabricmanager mask override baked in (`ls -la /etc/systemd/system/nvidia-fabricmanager.service` inside `cm-chroot-sw-img` — expect `-> /dev/null`; see 6k). If present, no further action needed on this point. If absent, apply the manual install-and-mask fix (8.3) and re-commit via `-d` before assigning this image to a category.
2. **Escalate to NV** per 6l's updated question — which of `gb200`/`gb300` is correct for GB300 NVL, and whether `maxQ106`'s original validation ever went through this flag at all. Do not provision the 18-node rack until this is answered, given the risk is now a silent wrong-parameter choice (e.g. IOMMU/PCIe/NVLink topology), not a build failure.
3. Optional, recommended: run the `gb200` vs `gb300` diff described in 6l (kernel params + package list) to have concrete data ready for NV, and/or for your own judgment call if NV's answer is delayed.
4. Optional but recommended before repeating x7: check `/var/log/apt/history.log` and `/var/log/apt/term.log` inside the image (`cm-chroot-sw-img`) on the next build to nail down the exact mechanism by which the `6.8.0-106` packages vanish from `dpkg -l` despite being explicitly installed twice (see 6i) — needed for a precise NV/BCM support write-up, not needed to proceed with provisioning.
5. Before any future rack build, if "Validating repo configuration" fails again, check the head node's own `/dev` (6m) before assuming it's a repo or `--dgx-type` problem — this failure signature now has two known, unrelated causes.
6. Assign category to `baseos-1014-doca321` (once steps 1–2 are resolved).
7. Assign the 18 nodes in the target rack to that category.
8. Provision the rack, watching for the per-node identity question below (machine-id/SSH host keys/hostname) since it hasn't been confirmed to auto-resolve yet.
9. Run L11 (rack/fabric-level) partnerdiag once provisioned.
10. If any NEW error appears at any step, apply the same pattern used throughout Section 6: get the exact line from `/var/log/cm-create-image-baseos-1014-doca321.log` (or the equivalent node-installer log once past image-build) — don't guess from a truncated on-screen `[FAILED]` message. Remember "Finalizing cluster services" failures may be non-fatal (6j) while "Finalizing image services" failures are not (6d).
11. Resolve the still-open items below in parallel.

### Still-open, non-blocking items
- Per-node identity regeneration (machine-id, SSH host keys, hostname) across the 18 nodes — not yet confirmed how/whether BCM's node-installer handles this automatically. Check "Assigning Images to Nodes and Post Installation Configurations" doc section.
- Whether an off-box backup of `maxQ106`'s pre-BCM-capture state exists — still never explicitly confirmed this session.
- **`6.8.0-106-generic-64k` build-time cost (6i)** — reproduces reliably (hit in both the incremental and from-archive builds) and costs real wall-clock time (~8.5hr total build observed) via redundant DKMS/OFED cycles against a kernel that's discarded either way. Exact disposal mechanism unconfirmed (see 6i); worth an NV/BCM support report regardless, given it'll recur on all 7 remaining racks unless addressed.
- **Root cause of the 6m `devtmpfs` incident** — head node recovered via reboot, but why it happened was never established. Worth a proper post-incident review with whoever else has admin/on-call ownership of this system, separate from the rack-build work.

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
  --dgx-type dgx_gb200 \
  -s \
  --no-cm-cuda-repo
```

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

### 8.7 Verify before trusting the image

```bash
cm-chroot-sw-img /cm/images/<image-name>

# Kernel state — expect ONLY the target kernel, no stray 6.8.0-106-generic-64k
dpkg -l | grep -E "^[hi]i.*linux-(image|modules|headers)"
ls -la /boot/vmlinuz* /boot/initrd*

# DOCA/driver/IMEX integrity — expect Installed == Candidate, no unexpected upgrades
dkms status
apt-cache policy doca-host mlnx-ofed-kernel nvidia-imex-580

# fabricmanager — expect masked, not just disabled
systemctl status nvidia-fabricmanager

exit
```

```bash
cmsh -c "softwareimage; list"    # confirm image registered with correct kernel version and path
```

Do **not** treat `/cm/images/<image-name>/boot/grub/grub.cfg` (checked from the head node) as a validation signal either way — BCM's node-installer regenerates real bootloader config on each node's own disk during provisioning; this file is not authoritative (see 6f).

### 8.8 Known-acceptable states (don't re-debug these on future racks)

| Symptom | Verdict |
|---|---|
| `cm-create-image` build takes several hours, mostly "stuck" on "Installing CM packages" | Expected — DKMS/OFED build against throwaway `6.8.0-106` kernel (6i). Not a hang. |
| Image's own `/boot/grub/grub.cfg` has no real kernel `menuentry` | Expected — node-installer doesn't use this file (6f). |
| `Setting up`/`Removing` never logged for `linux-image/modules/tools-6.8.0-106*`, yet `dpkg -l` shows them absent afterward | Reproduces reliably; end state confirmed correct even though exact log mechanism is unresolved (6i). Not a blocker. |
| `Finalizing cluster services` logs a `systemctl disable <service>` failure (e.g. bind9) for a service that was never installed | Non-fatal, build continues (6j) — different from the fabricmanager case in `Finalizing image services`, which **is** fatal (6d). |
| `nvidia-fabricmanager-580` version doesn't match the DKMS-built driver version | Irrelevant — package is masked and never runs on the compute host; real FM runs off-host on the NVSwitch tray (6d/6k). |
| `cm-chroot-sw-img` reports `dev`/`proc`/`sys`/`run`/`run/systemd/resolve/resolv.conf`/`dev/pts` "already mounted" on entry | Expected if step 8.4 wasn't run after the previous session — run it, don't ignore the warning (6h). |
| `Validating repo configuration` fails with `Failure getting installed package list` / `Failed to install packages`, **regardless of `--dgx-type`** | Check the head node's own `ls -la /dev/null` first (6m) before assuming a repo conflict (6e) — this exact on-screen failure has two known, unrelated root causes and doesn't distinguish them. If `/dev` is missing core nodes, that's a host-level incident, not fixable by changing `cm-create-image` flags. |
