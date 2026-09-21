# GB300 NVL L10 — Engineering Reference Manual

**Purpose of this document:** `session-summary.md` is the authoritative running log — chronological, dated, written as findings happened. This document reorganizes the same content **by topic** for reading straight through, so a given subsystem's full story (what it is, what broke, what fixed it, what's still open) is in one place instead of scattered across weeks of dated entries. **Nothing here is simplified or dropped** — where the log recorded a wrong hypothesis and its correction, both are kept, because the wrong turn is often exactly what stops the next person from repeating it. Section numbers below are new and specific to this document; cross-references to the original log use its own section numbers (e.g. "§9ah") so you can go back to the verbatim, timestamped source if needed.

**Scope:** 1.0.6 reference layout kernel upgrade, DOCA compatibility testing, field-upgrade staging, BCM provisioning of GB300 NVL racks (target: 8 racks × 18 nodes = 144 nodes), and the rack handoff/lifecycle process that follows provisioning.

---

## 1. Current Validated State

Two reference images/archives have gone through this pipeline so far:

| Line | Kernel | DOCA | Status |
|---|---|---|---|
| `maxQ106` (`baseos-1014-doca321`) | `6.17.0-1014-nvidia-64k` | `3.2.1-044413` | ✅ Held/pinned, DKMS clean, **real partnerdiag PASS**. First validated reference layout. |
| `maxQ20GA` (`baseos-1032-doca341`) | `6.17.0-1032-nvidia-64k` | `3.4.1-010000` | ✅ Built and provisioned to a full rack (rack08, then rack01). First DOCA-3.4.1-line archive through this pipeline (§9 of the log). |

**`maxQ106` baseline detail:**
- Kernel packages held: `linux-image/modules/headers-6.17.0-1014-nvidia-64k` + `linux-nvidia-6.17-headers-6.17.0-1014` — all 4 confirmed `hi` in dpkg.
- `unattended-upgrades` disabled (service + timers + periodic config), confirmed inactive.
- Root LV grown 100GB → ~891GB (100% of VG, ext4 online resize) — **no LVM snapshot headroom left as a result.**
- `mst` boot persistence: no native systemd service found on this platform at all (this turned out to be universal across the fleet, not a `maxQ106` gap — see §4.8 below). Deprioritized; not required for the partnerdiag/factory workflow since the customer boots their own OS.
- `sw_checklist.sh` was checking hold status against the wrong (generic HWE metapackage) package names, silently reporting `[MISSING]` on correctly-held exact-pinned kernels. Fixed; backup kept as `sw_checklist.sh.bak`.
- NVIDIA driver version field in the checklist shows `[CHECK]` consistently — not investigated, deferred; may be the same "script targets wrong release name" bug class as the fix above.

**Open, not simplification-eligible:** whether `6.17.0-1014` also satisfies DOCA 3.4.1 was never tested — the `maxQ106`/DOCA-3.2.1 combination and the separate `maxQ20GA`/DOCA-3.4.1 combination are two different, independently-validated stacks, not one stack proven against both DOCA versions.

---

## 2. Kernel & DOCA Compatibility

### 2.1 Kernel candidate results (target: dual-compatible with DOCA 3.2.1 *and* 2.0.0-era DOCA)

| Kernel | DOCA 3.2.1 | DOCA 3.4.1 | Notes |
|---|---|---|---|
| `6.14.0-1015` | Previously validated (pre-session baseline) | Not tested | LTS floor for CX8 per Table 11 — not the same kernel as the literal "6.8.0-1047" LTS build also named in Table 11. |
| `6.17.0-1014` | ✅ Full validation incl. real partnerdiag PASS | ⏸ Not tested | Originally flagged by NV as having a CPU stream-score bug — **later determined by the team to be a false alarm / not customer-relevant**, since the reference layout is factory/pass-criteria only and the customer boots their own OS. |
| `6.17.0-1016` | N/A | N/A | **Does not exist** in the Ubuntu archive (`linux-signed-nvidia-6.17` pool jumps 1014→1018 directly). Root cause of an early round of confusion — likely a mis-transcribed number from NV. |
| `6.17.0-1018` | ❌ Build failure | Not tested | `mlnx-ofed-kernel` (`25.10.OFED.25.10.1.7.1.409.1`) fails to compile against this kernel's `net/tls.h` — signature mismatch on `tls_offload_rx_resync_async_request_end/start` (`struct sock *` vs `struct tls_offload_resync_async *`); `-Werror` makes it fatal. |
| `6.17.0-1029` | ❌ Identical build failure to 1018 | ✅ Builds clean (DKMS-level only) | Confirms the failure is specific to DOCA-3.2.1's `25.10` OFED source, not the 6.17 kernel line generally — the 3.4.1 source already accounts for the newer `tls.h` signature. |
| `6.17.0-1032` | Not tested against this line | ✅ Full DKMS install, provisioned to real racks | The `maxQ20GA`-line kernel; ships with driver `580.173.10` and the full OFED/mlnx stack pre-baked into the archive rather than via apt. |

**Conclusion:** `6.17.0-1014` is the only build found that satisfies DOCA 3.2.1 (fully proven via partnerdiag). `6.17.0-1032` is the kernel actually shipped with the DOCA 3.4.1 archive. Whether `1014` *also* satisfies 3.4.1 remains the one still-open cross-compatibility question — see §10 (Open Items).

### 2.2 Tooling bugs found during kernel/DOCA validation
- `sw_checklist.sh` hold-detection logic — see §1.
- `doca-kernel-support` initially failed with a cryptic "could not determine kernel version" error — root cause was a missing build toolchain (`gcc`, `dkms`, `make`, `build-essential`) on the fresh test box, not a real kernel-source problem. Once installed, the tool worked and correctly surfaced the real `tls.h` incompatibility above.
- partnerdiag CLI argument-parsing failures traced to smart-dash/smart-quote corruption from copy-pasting commands out of a Word document. **Standing rule: retype partnerdiag commands sourced from Word docs/tickets/emails, or sanity-check with `cat -A` first — never paste directly.**

---

## 3. BCM Software Image Build

This is the procedure for building a BCM software image (`cm-create-image`) from a validated reference-host tarball, consolidated into one ordered runbook. The bug-by-bug discovery narrative that produced this runbook is in §3.3 below, kept for context and because several of these bugs recur in subtly different forms on new archives.

### 3.1 Environment facts (confirm once per cluster, don't re-derive)
- BCM's documented image format is `.tar.gz` — **not** `.sqsh`/squashfs, despite that being an early assumption. Confirmed via NVIDIA's own BCM/BaseOS documentation.
- Head node ("N/B") is **x86_64**, BCM 11, managing an **aarch64** compute rack — a mixed-architecture setup. GB300 image builds run under **QEMU user-mode emulation** (`cm-qemu-user-static`), which is why some build steps (package installs, DKMS builds) are dramatically slower than pure file-I/O steps like archive unpack/validate.
- `cm-create-image -h` on this BCM 11 install confirms `--dgx-type` includes **`dgx_gb300`**, not just `dgx_gb200`. See §3.5 for the still-open question of which is actually correct for this hardware.
- Reference archive paths: originally assumed `/root/bcm-image-export/`; the `maxQ20GA`/DOCA-3.4.1 line's actual archives live at `/root/pre-built-images/` instead. **Confirm the real path per-archive rather than assuming.**

### 3.2 Build procedure (ordered runbook)

**3.2.1 — Teardown any prior attempt** (skip on a genuinely first build):
```bash
cmsh -c "softwareimage; remove <image-name>; commit"
rm -rf /cm/images/<image-name>
```

**3.2.2 — Build from archive:**
```bash
cm-create-image -a /root/pre-built-images/<source-archive>.tgz \
  -n <image-name> \
  --dgx-type dgx_gb300 \
  -s \
  --no-cm-cuda-repo
```
- `-s` is important: it skips installing BCM's own ~500-package default baseline on top of an already-complete imported tarball. Without it, an early attempt pulled in an irrelevant second kernel (`6.8.0-106-generic-64k`) and hours of unnecessary DKMS rebuilding under QEMU (§3.3.2).
- `--dgx-type dgx_gb300` is shown here as current default, matching the most recent successful production build — **not yet NV-confirmed as correct for this hardware**; see §3.5. If NV confirms `dgx_gb200` instead, use that.
- `--no-cm-cuda-repo`: **verify this is still correct before each new archive**, not just copy-pasted. It was correct for `maxQ106`/`1014`-doca321, but a parallel `baseos-1029-doca341` build on the same head node needed the CUDA network repo *enabled* to pull `nvidia-open-580`/`nvidia-imex`/etc. from the same package list — without it those packages silently show "Unable to locate package" and get skipped rather than failing the build. Before trusting either setting on a new archive:
  ```bash
  cm-chroot-sw-img /cm/images/<image-name>
  apt-cache policy nvidia-open-580 nvidia-imex nvidia-kernel-common-580
  dpkg -l | grep -E "nvidia-open-580|nvidia-imex|nvidia-kernel-common-580"
  exit
  ```
  If none of these are installed and that's expected (the driver you actually want is already baked in via `.run`/DKMS, not apt), `--no-cm-cuda-repo` is fine. `apt-cache policy` alone can't distinguish "flag skipped something needed" from "driver was never meant to come from here" — always cross-check against `dkms status` + `dpkg -l` for the real driver/DOCA packages (this exact ambiguity is what the `maxQ20GA` build hit and resolved benign, §3.3.7).
- Expect this to take up to **~8.5 hours** end-to-end on the older archive line — dominated by a redundant DKMS/OFED build cycle against an irrelevant discarded kernel; see §3.3.2. This is a known, accepted cost, not a hang — do not interrupt on this basis. The newer `maxQ20GA` archive built end-to-end in one shot with no manual intervention needed (§3.3 note on `-d` no longer being routine).

**3.2.3 — Fix: fabricmanager finalize failure** (check first — may already be resolved by the archive):
```bash
cm-chroot-sw-img /cm/images/<image-name>
ls -la /etc/systemd/system/nvidia-fabricmanager.service
exit
```
If this shows `-> /dev/null`, the finalize step will succeed on its own — skip the manual fix below. (Don't trust `dpkg -l nvidia-fabricmanager-580` for this check — it can show `un`/not-installed even when the mask is correctly in place. Confirmed on the `maxQ20GA` archive: package shows `hi`/installed **and** masked simultaneously with no conflict — both states are legitimate.)

If the override is absent (building from an original, unpatched archive):
```bash
cm-chroot-sw-img /cm/images/<image-name>
chmod 1777 /tmp && rm -rf /tmp/*
apt-get update && apt-get install -y nvidia-fabricmanager-580
systemctl mask nvidia-fabricmanager      # NOT just disable — see §3.3.1. NEVER purge this package.
ls -la /etc/systemd/system/nvidia-fabricmanager.service   # confirm -> /dev/null
exit
```
(`systemctl status` doesn't work inside `cm-chroot-sw-img` — no PID 1/D-Bus in the chroot. Use the filesystem symlink check instead.)

**3.2.4 — Clean up chroot mounts** (mandatory before any further host-side command against this image — see §3.3.3 for why):
```bash
umount -l /cm/images/<image-name>/sys/firmware/efi/efivars    # unmount BEFORE /sys itself, see §3.3.3
umount -l /cm/images/<image-name>/var/tmp/* 2>/dev/null
for m in dev/pts dev proc sys run/systemd/resolve/resolv.conf run; do
  umount -l "/cm/images/<image-name>/$m" 2>/dev/null
done
grep "/cm/images/<image-name>/" /proc/mounts   # must return nothing (var/tmp entry may still linger — known-acceptable)
```

**3.2.5 — Cosmetic cleanup (optional, safe):**
```bash
cm-chroot-sw-img /cm/images/<image-name>
apt-get autoremove -y                                    # clears orphaned prior-kernel companion packages
rm -f /boot/initrd.img-6.8.0-106-generic 2>/dev/null      # if present — stray, unbootable, harmless
exit
```
Repeat 3.2.4 (mount cleanup) again after this session too.

**3.2.6 — Commit the finalized image** — **only if a chroot session actually changed something.** A read-only verification chroot (dkms status / dpkg checks, no writes) does not need a commit — only the mandatory mount cleanup, since it still opened bind mounts. Running `-d` unconditionally on an already-good image re-triggers the whole "Installing CM packages" pipeline for no reason and risks hitting a new problem on an image that was already fine (this was over-applied as a routine step early on; corrected once a from-scratch build completed cleanly in a single invocation with no `-d` needed at all):
```bash
cm-create-image -d /cm/images/<image-name> -n <image-name> -s --no-cm-cuda-repo
```

**3.2.7 — Pre-provisioning check: missing config directories.** Node-installer's `open()` calls for per-node network config (`interfaces.d/ifcfg-<iface>`) and NTP config (`ntpsec/ntp.conf`) fail fatally on first PXE boot if the **target directories** don't exist in the image — a directory-existence problem, not a missing-package one:
```bash
cm-chroot-sw-img /cm/images/<image-name>
ls -la /etc/network/interfaces.d/ 2>&1
ls -la /etc/ntpsec/ 2>&1
exit
```
If either is missing:
```bash
mkdir -p /cm/images/<image-name>/etc/network/interfaces.d
mkdir -p /cm/images/<image-name>/etc/ntpsec
```
This fix survives a `-d` resume against the same directory but **not** a fresh `-a` rebuild from the archive — it isn't baked into the `.tgz`. Check explicitly on every new archive rather than assuming a prior archive's fix carried over (on the `maxQ20GA` archive, both directories were already present — apparently baked in upstream — so this check found nothing to do there; don't take that as evidence the check is unnecessary going forward).

**3.2.8 — Pre-provisioning check: category `disksetup`.** Symptom if unset: node-installer halts during "Fetching disks setup" / "Creating new disk layout" with `Missing device. Node Installer will halt. / The error was: missing device assert` — **before** any partition-size check, so despite the "disk" framing this is not a capacity issue; it's node-installer unable to resolve a target block device at all.
```bash
cmsh -c "category use <category-name>; get disksetup"
```
If empty, set the validated layout:
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
Applied via `cmsh`'s interactive `set disksetup` editor (paste, save, exit), then `commit`. No swap partition defined — consistent with the swap-removal decision documented for `/swap.img` (§3.3.8). Root cause of the halt is strongly suspected (not fully confirmed) to be simply an unset/empty `disksetup` property rather than a wrong `blockdev`/scheme — the XML applied was byte-identical to a layout already reviewed earlier. Add a pre-flight `get disksetup` check for every remaining rack rather than discovering this only via a live halt.

**3.2.9 — Category `finalizescript`:** confirm set to the validated hostname-fix script:
```bash
cmsh -c "category use <category-name>; get finalizescript"
# expect: finalize-hosts-127-v3.sh
cmsh -c "category use <category-name>; set finalizescript finalize-hosts-127-v3.sh; commit"
```
Full history and why v1/v2 didn't work is in §4.3.

**3.2.10 — Suppress the `mst` false-positive service monitor** (see §4.8 for why this is a real, permanent, fleet-wide condition and not something to "fix"):
```bash
cmsh
% category use <category-name>
% services
% add mst
% commit
```

**3.2.11 — Verify the image before assigning nodes:**
```bash
cm-chroot-sw-img /cm/images/<image-name>

# Kernel state — expect ONLY the target kernel, no stray 6.8.0-106-generic-64k
dpkg -l | grep -E "^[hi]i.*linux-(image|modules|headers)"
ls -la /boot/vmlinuz* /boot/initrd*

# DOCA/driver/IMEX integrity
dkms status
apt-cache policy doca-host mlnx-ofed-kernel nvidia-imex-580

# fabricmanager mask (systemctl status doesn't work in this chroot)
ls -la /etc/systemd/system/nvidia-fabricmanager.service   # expect -> /dev/null

# config directories (3.2.7)
ls -la /etc/network/interfaces.d/ /etc/ntpsec/

# nsswitch.conf — confirm the removed SSSD-hang fix is NOT present (§4.5)
grep -E "^(passwd|group|netgroup):" /etc/nsswitch.conf     # expect default SSSD-backed lines, not 'files' on all three

# chrony (§4.6)
dpkg -l | grep -i -E "^ii\s+(ntp|chrony)"
systemctl is-enabled chrony
systemctl is-enabled systemd-timesyncd     # expect 'not-found' or 'masked', not 'enabled'

# cuda-dcgm daemon, not just libs (§4.7)
dpkg -l | grep -i "cuda-dcgm "

exit
cmsh -c "softwareimage; list"    # confirm registered with correct kernel version and path
```
Do **not** treat `/cm/images/<image-name>/boot/grub/grub.cfg` (checked from the head node) as a validation signal either way — it never contains a real kernel `menuentry`, only a `UEFI Firmware Settings` stub. This is expected: BCM's node-installer regenerates real bootloader config on each node's own disk during provisioning, using real hardware and real `/proc`/`/dev` — this file is not authoritative.

### 3.3 Known build-time issues, by subsystem

**3.3.1 — Fabric Manager finalize failure.** `--dgx-type dgx_gb200`/`dgx_gb300`'s finalize step unconditionally runs `systemctl disable nvidia-fabricmanager` — but real Fabric Manager for this GB300 NVL architecture runs off-host, on the NVSwitch tray at L10, never on the compute node, so the package was never in the source tarball. **Confirmed not a gb200-vs-gb300 issue** — GB200 has the identical off-host FM architecture at L10. Fix: install the package, then **mask** (not just disable) it — masking blocks even a manual `systemctl start` with a clear "unit is masked" error, a much stronger guard than plain `disable`. Discovered later: **the masked-unit symlink alone satisfies the finalize step, even with the package not installed at all**, because `systemctl disable` treats a masked unit as "existing" via the `/etc` override — so once this override is baked directly into the source archive, the finalize step succeeds with zero manual intervention (confirmed on the `maxQ20GA` archive, §3.2.3). Caveat: `dpkg -l nvidia-fabricmanager-580` can show `un` even when the mask is correctly in place — check the filesystem, not dpkg's database.

**3.3.2 — Stray `6.8.0-106-generic-64k` kernel installed during "Installing CM packages," dominating build time.** Root-caused via `/var/log/cm-create-image-<image>.log`: the "Installing CM packages" stage's `apt-get install` command **explicitly names** `linux-headers/image/modules/tools-6.8.0-106-generic-64k` in its argument list — not a transitive dependency — and this happened **twice** in one build. `-s --no-cm-cuda-repo` do **not** prevent this (this is a materially different finding than the `-s`-fixes-stray-kernel result in 3.2.2's build step — that covers BCM's own distribution-package sync; this is a different stage entirely). Each occurrence auto-triggers a DKMS build cycle (`iser`, `isert`, `kernel-mft-dkms`, `knem`, `mlnx-ofed-kernel`) against the throwaway kernel — `mlnx-ofed-kernel` under QEMU emulation is almost certainly where most of the ~8.5-hour build time goes. **Oddity, not fully explained:** despite being explicitly installed twice, none of the `6.8.0-106*` packages ever get a `Setting up`/`Removing`/`Purging` line in the log, yet the final `dpkg -l` shows zero trace of them, not even as a removed remnant — every `apt-get install` in this log runs with `--setenv=DEFER_CONFIG=yes`, suspected but not confirmed as the mechanism. If a precise NV/BCM support report is ever wanted, `/var/log/apt/history.log` and `/var/log/apt/term.log` **inside the image** (not this wrapper log) would be the authoritative source — never pulled this session. **Operational impact:** if this reproduces on every from-scratch build of this archive line, each image build costs most of a day, multiplied across all 8 racks.

**3.3.3 — `cm-chroot-sw-img` does not fully unmount on exit.** After exiting a chroot session, `dev`, `proc`, `sys`, `dev/pts`, and tmpfs mounts for `/run` and `/run/systemd/resolve/resolv.conf` are commonly still present and need manual `umount -l`. Confirmed recurring across multiple sessions, not a one-off. Running any further host-side `cm-create-image`/image-directory operation while these are still mounted risks either capturing live chroot-session mutations into the image, or a "device busy" failure — same failure family as the archive-corruption bug that this whole precaution traces back to (see below). **A new mount was found later on a different archive:** `sys/firmware/efi/efivars` (efivarfs), nested under `/sys` — must be unmounted **before** `/sys` itself or the `/sys` unmount may not fully release. That same session also saw `exit` fail to auto-unmount anything at all (every prior session had auto-unmounted cleanly on `exit`) — root cause not established, possibly related to the nested efivarfs mount blocking normal teardown order; worth watching whether it recurs. The full, current standing sequence is in §3.2.4 above.

**3.3.4 — Original tar-capture corruption (root cause of the whole mount-cleanup discipline).** The very first archive-capture command used absolute-path excludes (`--exclude=/proc`) with `-C / .`, which stores paths as relative (`./proc`) — the excludes never matched, so the archive pulled in live, mutating `/proc`/`/sys` and was corrupted. Fixed, and the corrected command (already used for the working archives) is:
```bash
sudo mkdir -p /root/bcm-image-export
sudo tar --numeric-owner --xattrs --acls -czpf /root/bcm-image-export/maxQ106-1014-doca321-baseos.tgz \
  --exclude='./proc' --exclude='./sys' --exclude='./dev' --exclude='./run' \
  --exclude='./tmp' --exclude='./mnt' --exclude='./media' --exclude='./lost+found' \
  --exclude='./root/bcm-image-export' \
  -C / .
```
Verify (must return nothing): `tar -tzf ... | grep -E "^\./(sys|proc|dev|run)/" | head`

**3.3.5 — Duplicate CUDA repo conflict (`Signed-By` mismatch).** Building without `--no-cm-cuda-repo` fails at "Validating repo configuration" with:
```
E: Conflicting values set for option Signed-By regarding source .../sbsa/ /:
   /usr/share/keyrings/cm-cuda-archive-keyring.gpg != /usr/share/keyrings/cuda-archive-keyring.gpg
```
Root cause: two `.list` files declare the same CUDA SBSA URL with two different, both-real keyrings — `cuda-ubuntu2404-sbsa.list` (original, from the reference host — **keep**) and `cm-cuda-ubuntu2404-sbsa.list` (BCM-injected duplicate — **remove**). **Confirmed reproducible on a second, independent archive line** (`maxQ20GA`/`1032`), not a one-off. **New finding on that second archive:** removing the duplicate file via chroot and resuming with `-d` did **not** stick — the build failed at the identical step again on resume, even though `apt list --installed` was confirmed clean immediately beforehand. Something in the resume path (most likely "Copying cm repo files," known to re-run on every `-d` resume) appears to re-inject the file before validation runs — **not root-caused**; worth diffing `/etc/apt/sources.list.d/` immediately before/after a `-d` resume's "Copying cm repo files" stage to catch it directly. **Working fix:** build with `--no-cm-cuda-repo` from the start rather than remove-and-resume — confirmed to avoid the conflict entirely, with the CUDA sbsa repo itself remaining enabled/functional (`apt-cache policy` still shows real candidates). **Open:** whether `--no-cm-cuda-repo` is *why* the duplicate is never injected, or coincidental with the real fix lying elsewhere in the "Copying cm repo files" stage — treated as the working answer until proven otherwise.

**3.3.6 — `Finalizing cluster services`: non-fatal service-disable failures (different behavior class than Fabric Manager's).** Same failure *shape* as the Fabric Manager case — `systemctl disable <service>` erroring with `unit ... does not exist` because the service was never installed (seen for `bind9`, presumably `slapd` too) — but during "Finalizing **cluster** services" this does **not** abort the build; `cm-create-image` logs the error and continues straight to the next step and finishes cleanly. **Keep this distinction explicit:** "Finalizing image services" failures (Fabric Manager) are fatal and need manual intervention; "Finalizing cluster services" failures (bind9/slapd) are cosmetic log noise. Don't apply the same fix reflexively to both.

**3.3.7 — Verifying DOCA/driver/IMEX weren't touched by the build.** Direct question worth asking after every build: did any part of `cm-create-image` (the stray-kernel activity, CM package install, etc.) touch the validated driver/DOCA stack? Check via chroot: `dkms status` (confirms the real module stack, keyed correctly by kernel version, isolated from the throwaway kernel's own DKMS activity), `dpkg -l | grep -iE "doca|mlnx-ofed"` against the known-good version strings, and `apt-cache policy doca-host` (**Installed == Candidate** confirms nothing newer got silently queued). On `maxQ106`, this fully confirmed nothing of consequence was touched. On `maxQ20GA`, the apt packages for the newer driver line all showed "not installed," which was correctly recognized as benign (the driver ships pre-baked via DKMS, not via these apt packages) rather than a repeat of the earlier false alarm below — **lesson: `apt-cache policy` alone cannot distinguish "flag skipped something needed" from "this was never meant to come from apt" — always cross-check with `dkms status` + `dpkg -l` for the actual packages.** One false alarm from this class of check, now resolved: `nvidia-fabricmanager-580`'s installed version not matching the DKMS-built driver's version was initially flagged as a blocker — corrected once remembered that the FM package exists here *only* to satisfy the finalize step and is masked/never run, so its version relative to the driver is irrelevant. A second cosmetic finding, not a defect: the `xpmem` package's version *string* on the `maxQ20GA` archive referenced kernel `1029` while the image's actual kernel is `1032` — `dkms status` confirmed the real module was correctly built against `1032`; stale package-naming metadata only.

**3.3.8 — `/swap.img` sparse-file inflation (8KB → 8GB).** Found via `du -shc /*` comparing the reference host (29G total) against the built image (36G total) — the ~7G gap traces almost entirely to one file. On the reference host, `/swap.img` is a normal sparse swap file (`ls -lsh` shows `8.0K` actual vs `8.0G` logical). Inside the built image, `du` reports a **full, non-sparse 8.0GB** — the archive-capture and/or extraction process materialized every logical hole into real written zero bytes. **Root cause suspected, not fully pinned down:** `tar` doesn't preserve sparseness on extraction without a sparse-aware flag; either the archive was captured without `--sparse`, or `cm-create-image`'s extraction doesn't pass an equivalent flag (its `--tar-options` flag may be the fix point). **Status: confirmed, not yet fixed.** At 18 nodes × 8 racks, this is ~8GB of dead weight per image, multiplied across storage and per-node transfer time — beyond the size cost, a compute node's swap is normally supposed to be created by the node-installer at provisioning time, not shipped pre-baked, so this file's presence in the captured image at all is worth questioning separately from the size bug. Two candidate fixes, neither applied yet: fix tar sparseness on capture/extraction (`--sparse`/`--tar-options --sparse`), or simply exclude `/swap.img` from the image via `-o`/`--exclude-from`.

**3.3.9 — `/tmp` permissions precondition for *any* apt-get inside a chroot, not just the Fabric Manager fix.** The `chmod 1777 /tmp && rm -rf /tmp/*` step was originally documented only as a Fabric Manager prerequisite, but was independently required before `apt-get install -y chrony` would run cleanly on the `maxQ20GA` archive too (same `Couldn't create temporary file /tmp/apt.conf.XXXXXX` error). **Correction: treat this as a standard first step before any `apt-get` inside `cm-chroot-sw-img`, not a fabricmanager-specific workaround.**

**3.3.10 — "Pending kernel upgrade to 6.8.0-106-generic" is always a false alarm inside a chroot.** `uname -r` (and anything reading it, like apt's post-install kernel scan) inside **any** chroot — bare or `cm-chroot-sw-img` — reports the **host's own kernel identity**, since chroot changes the filesystem root, not the running kernel. This has fired during the Fabric Manager install, during a resumed build, and during the chrony install — it is general to any package operation inside the chroot that triggers a kernel-scan hook, not tied to any one fix. Never use `uname -r` inside a chroot as a validation signal; use `dpkg -l`, `/boot` contents, and (post-provisioning) the node's own real `uname -r` instead. Relatedly, always use `cm-chroot-sw-img`, never bare `chroot` — bare chroot doesn't mount `/proc`/`/sys`/`/dev` and produces a wall of extra misleading warnings on top of this one.

### 3.4 `dgx_gb200` vs `dgx_gb300` — still open

`cm-create-image --help`'s description of `--dgx-type` ("obtain proper kernel parameters") suggested `dgx_gb300` may be the more correct choice for this documented GB300 NVL hardware, versus the `dgx_gb200` used per NV's original verbal guidance. Investigation history:

- An initial `dgx_gb300` build failure at "Validating repo configuration" was investigated as a possible gb300-specific defect — but a `dgx_gb200` control build, run purely to check, **failed identically**, redirecting the investigation to the head node itself. Root cause: the head node's own `devtmpfs` had lost most standard device nodes (`/dev/null`, `/dev/zero`, `/dev/random`, `/dev/urandom`, `/dev/tty`, `/dev/console`, `/dev/full`, `/dev/nvme0`) — a genuine host incident, unrelated to either `--dgx-type` value. Full writeup in §8.1. Once the head node was rebooted, `dgx_gb300` built successfully end-to-end.
- **Net effect: both `dgx_gb200` and `dgx_gb300` are confirmed to build successfully.** Neither flag was ever actually broken; the earlier "gb300 doesn't work, use gb200 out of necessity" conclusion traced entirely to the devtmpfs incident and should not be cited.
- **New evidence (on the `maxQ20GA` build, §9d of the log):** near the end of an otherwise-successful `dgx_gb300` build, a non-fatal warning appeared: `bcm-dgx-software-image-kernel-param-syncer --dgx-platform dgx_gb300 --show-only ... E | Unable to determine the correct method for collecting kernel parameters. Exiting!` — did not fail the build, but this tool's stated job is exactly what `--dgx-type` is supposed to control. Relevant new evidence for the NV escalation.
- **Still genuinely open:** which value is *correct* for real GB300 NVL hardware — a successful build is necessary but not sufficient; the risk of a wrong choice is a *silent* one (subtly wrong IOMMU/PCIe/NVLink boot parameters), not a build failure, and is worth NV's explicit confirmation before nodes are provisioned at scale on it. It was also never confirmed whether `maxQ106`'s own original validation/partnerdiag PASS ever went through this flag at all — if not, that precedent doesn't validate either flag's boot-parameter correctness, only that a build with some driver stack passed partnerdiag under whatever flag (if any) was used at the time.
- **Escalation question to send to NV** (see §10):
  > "`cm-create-image`'s `--dgx-type` help states it's used to 'obtain proper kernel parameters,' and `dgx_gb300` is a valid choice in our BCM version — we've confirmed both `dgx_gb200` and `dgx_gb300` build successfully in our environment (and separately saw a `kernel-param-syncer` warning under `dgx_gb300` — see attached). Given our target hardware is GB300 NVL, which is correct? Separately: did `maxQ106`'s original reference build/validation ever go through this flag, and if so, which value?"
- Concrete comparison available now that both build: diff kernel parameters/GRUB config and package selection directly via `cm-chroot-sw-img ... dpkg -l` / `cat /etc/default/grub` between a `gb200` and `gb300` build of the same archive.

---

## 4. Category & Node Configuration

### 4.1 Category creation
Two paths, in order of preference:
- **Clone an existing known-good category** (preferred whenever one exists):
  ```bash
  cmsh
  % category
  % clone <source-category> <category-name>
  % commit
  % category use <category-name>
  % set softwareimage <image-name>       # cloning does NOT carry this over — always set explicitly
  % commit
  ```
  Confirmed via direct `get` checks after cloning (`maxQ-1032-doca341` cloned from `maxQ-1029-doca341`): `disksetup` and `finalizescript` both carry over correctly; `softwareimage` does not and must be set manually every time.
- **Blank creation**, reserved for the first-ever category on a cluster with nothing suitable to clone:
  ```bash
  cmsh
  % category
  % add <category-name>
  % commit
  ```
  This step was originally undocumented as a prerequisite in the SOP (it was always assumed pre-existing) — now explicit.

### 4.2 `disksetup` — see §3.2.8 for the full symptom/fix. Add a pre-flight `get disksetup` check for every new category, don't wait to discover an unset value via a live node-installer halt.

### 4.3 `finalizescript` — hostname fix (`127.0.1.1 <hostname>`), full history

**Problem:** nodes provisioned from `baseos-1014-doca321` were failing the `BF3PcieInterfaceTraffic` partnerdiag test; a `127.0.1.1 <hostname>` line in `/etc/hosts` was the candidate remedy. The original candidate approach (`echo "127.0.1.1   #HOSTNAME#" > /cm/images/<image>/etc/hosts.suffix`) is **confirmed not a real BCM mechanism at all** — node-installer's own log shows it generates `/etc/hosts` from its own template + device database, with no code path anywhere that reads or merges a `.suffix` companion file. `#HOSTNAME#` is also not a real BCM macro. Both parts of the original idea were moot.

**Three real iterations, root cause found on the second:**
- **v1** (`echo "127.0.1.1 $(hostname)" >> /etc/hosts`, run as a category finalize script): ran successfully every time per the node-installer log, but the appended line never survived onto the booted node. **Root cause, confirmed from BCM's own shipped example script's header comment:** *"The root / of the running node is always mounted on /localdisk"* during the finalize stage. v1 wrote to the ramdisk's own throwaway `/etc/hosts`, not the node's real, persisted file at `/localdisk/etc/hosts` — a chroot/path mismatch, not a race condition or an overwrite as first suspected.
- **v2** (a self-healing systemd `.path` unit watching `/etc/hosts` and re-applying the entry on every change, installed via the finalize script): a workaround sidestepping the path-mismatch question by running post-boot on the real filesystem. Logically sound, but never deployed once the actual root cause (below) was found — not needed.
- **v3 (shipped):** writes directly to `/localdisk/etc/hosts` instead of `/etc/hosts`, fixing the root cause directly. Saved at `/cm/local/apps/cmd/etc/htdocs/scripts/finalize/finalize-hosts-127-v3.sh` — a real, `cmsh`-tab-completion-recognized directory alongside BCM's own shipped finalize examples. Applied via:
  ```
  cmsh
  % category use <category-name>
  % set finalizescript finalize-hosts-127-v3.sh
  % commit
  ```
  (`cmsh` reads the file by name directly from that directory — cleaner than the interactive editor-paste method used for v1/v2.)

**Validated on a full 18-node rack01 redeploy** — 4 of 18 spot-checked nodes each showed their own correct hostname, no cross-contamination, no leftover `#HOSTNAME#` literal. **Confirmed still standard practice on the `maxQ-1032-doca341` category too** (cloned settings carried it over correctly, §4.1).

**Still genuinely open:** whether this actually makes `BF3PcieInterfaceTraffic` partnerdiag pass has never been independently re-verified — the `/etc/hosts`-content theory for that failure was only assumed from how the fix was originally proposed, never proven. Re-run partnerdiag with this fix in place before treating the *original problem* (not just the delivery mechanism) as closed.

### 4.4 Category exclude lists (`excludelistupdate` / `excludelistsyncinstall`)

These lists control what a periodic BCM category sync will and won't overwrite on a live node. Two gaps found (both now fixed at the `maxQ-1032-doca341` category level, relevant to any rack that will run `rack_lifecycle.sh`'s `handoff`/`pre-diag` — see §7):
- `/etc/resolv.conf` was excluded, but `handoff` actually edits **`/etc/systemd/resolved.conf`** (a different file) — not excluded at all, so any sync was free to revert it.
- Many named services had explicit `.wants/<service>.service` exclude entries, but **`cuda-dcgm` did not** — any sync was free to recreate `multi-user.target.wants/cuda-dcgm.service`, silently re-enabling a service `pre-diag` had deliberately stopped.

Fix — both paths added to `excludelistupdate` and `excludelistsyncinstall`:
```
/etc/systemd/resolved.conf
/etc/systemd/system/*.wants/cuda-dcgm.service
```
Edited via `cmsh`'s interactive `vi` editor (`category use <category>; set excludelistupdate`) — there is no non-interactive append shortcut for this property per the admin manual.

**Bigger discovery than the exclude-list gap itself:** immediately after committing this **category-level** change (unrelated to services), CMDaemon fired `Service cuda-dcgm was started` on **all 18 nodes simultaneously** — silently undoing `pre-diag`'s stop across the entire rack as a side effect of an unrelated commit. **Operational rule, more important than the exclude-list fix:** any category-level `commit` — not just service-related ones — appears to trigger CMDaemon to re-assert/re-sync service state across the whole category. Treat `pre-diag`'s effect as fragile against *any* subsequent category-level change during a live diag campaign, not "set and forget." If a category commit during an active campaign is unavoidable, immediately re-run `pre-diag --rack <N>` afterward and verify via `status` before trusting the rack's diag-safe state again. **Not fully explained:** why this happens even with the CMDaemon-level `services` override (`monitored: no`) in place — possibly the override itself gets briefly reset/reprocessed during the category resync before reapplying, or the actual trigger is systemd reacting to the `.wants/` symlink being restored on disk, independent of CMDaemon's `monitored` flag. Worth an isolated observation test if this needs to be pinned down precisely.

### 4.5 `nsswitch.conf` / SSSD hang — fixed, then found to be a regression, currently unresolved

**Original symptom:** commands resolving an unknown UID/GID (`id <uid>`, `ls -l` on files owned by an unmapped UID) hung for an extended period rather than failing fast. Root cause: `nsswitch.conf`'s default `passwd`/`group`/`netgroup` lines fall through to SSSD, which attempts an LDAP lookup for the unknown ID and blocks until it times out.

**Fix applied (later reverted — see below):**
```bash
sed -i 's/passwd:.*/passwd:     files/' /etc/nsswitch.conf
sed -i 's/group:.*/group:      files/' /etc/nsswitch.conf
sed -i 's/netgroup:.*/netgroup:   files/' /etc/nsswitch.conf
```
**Real-node confirmation:** independently reproduced on a real PXE-provisioned node (`ls`/`ll` on a directory noticeably slow due to per-file SSSD/LDAP owner-name lookups accumulating), and confirmed resolved after this fix. Important general lesson from verifying this: **don't trust a check run only inside `cm-chroot-sw-img` as proof a fix works** — SSSD isn't an active daemon inside a chroot, so a fast result there only proves a config file changed, not that the real symptom is gone. Also worth remembering: `9999` is a safer test UID than a value like `604` for "prove this is definitely unresolvable" checks, since low three-digit UIDs risk coincidentally being real, locally-resolvable system accounts on some systems.

**⚠️ Confirmed regression (real-node evidence, `rack01node18`):** this fix disables SSSD/LDAP identity resolution on the node entirely, falling back to local (`/etc/passwd`/`/etc/group`) only — and `cmsupport` apparently must resolve via LDAP. With the fix applied, `id: 'cmsupport': no such user` and the `ldap` health check fails. **This step has been removed from the SOP.** Do not apply it to any further racks, and do not bake it into the reference image.

**Interesting cross-reference, not yet explained:** the hang does **not** reproduce on the separate `maxQ-1029-doca341`/`baseos-1029-doca341` line (`rack08node01`), despite that category sharing the identical `finalizescript` with `maxQ-1014-doca321` — `time id 9999` returns in 1-4ms there, no delay. Since the finalizescript is shared but the hang isn't, the root cause is more likely something specific to the `1014`/DOCA-3.2.1 image's actual content (an SSSD version/config or cached state baked into that particular tarball) than anything the finalizescript configures — worth diffing the two images' SSSD packages/config directly if this is revisited.

**Status: genuinely unresolved.** The underlying hang is real and confirmed; the fix that solved it is confirmed to break `cmsupport`; reverting to pre-fix `nsswitch.conf` isn't safe either since the hang was independently reproduced on real hardware. Two candidate directions, neither validated yet:
1. Keep `sssd` in `nsswitch.conf` but tune SSSD's own negative-cache/timeout settings so unknown-UID lookups fail fast instead of hanging, rather than removing LDAP from the chain entirely.
2. Explicitly allow-list `cmsupport` (and any other required service accounts) to resolve locally via `/etc/passwd`, while leaving `nsswitch.conf` otherwise pointed at SSSD for everything else.

Note this is a **different** thing from `rack_lifecycle.sh`'s `handoff` deliberately setting `nsswitch.conf` to `files`-only when a node is leaving the BCM network entirely (§7.2) — that's an intentional, controlled off-cluster transition with its own safeguards; this section is an accidental in-cluster regression from an unrelated fix. Don't conflate the two.

### 4.6 `ntp` health check FAIL — `chrony` missing from the image

**Root cause, confirmed on both archive lines:** `dpkg -l | grep -i -E "^ii\s+(ntp|chrony)"` returns nothing at all — neither package is present. `systemd-timesyncd` is installed but ships pre-disabled by default (same class of intentional image hardening already seen with `shorewall`/`shorewall6`/`auditd`), just without a replacement time-sync mechanism ever installed. Confirmed at fleet scale: all 18 `maxQ-1014-doca321` nodes on `rack01` showed `health check failed`; the same day, all 18 `maxQ-1029-doca341` nodes on `rack08` (already had the chrony fix applied) showed clean `[UP]` — same head node, same day, only difference being this fix's presence.

**Also confirmed: setting the category's `timeservers` field does not wire up persistent sync** — `journalctl -u systemd-timesyncd` showed zero entries after setting `timeservers` and a reinstall. That field only feeds node-installer's one-shot provisioning-time sync (`ntpd -c /tmp/ntp.conf -q -g`), not any persistent post-boot service. The health check specifically greps for `ntpd`/`chronyd` by process name, so `systemd-timesyncd` (even if enabled) won't satisfy it — chrony is the correct target, not timesyncd.

**Fix, applied once to the reference image, not per-node:**
```bash
cm-chroot-sw-img /cm/images/<image-name>
chmod 1777 /tmp && rm -rf /tmp/*     # standard precondition, §3.3.9
apt-get update && apt-get install -y chrony
systemctl disable systemd-timesyncd
systemctl mask systemd-timesyncd
systemctl enable chrony
```
Then point chrony at an internal time source in `/etc/chrony/chrony.conf` (replace the default `pool ntp.ubuntu.com`/`pool 2.ubuntu.pool.ntp.org` lines):
```
server 10.141.255.254 iburst
```
`exit`, then mount cleanup (§3.2.4), then commit if needed.

**Note on package behavior, varies by archive:** on `maxQ106`/`1014`, `systemd-timesyncd` stayed present-but-disabled after installing chrony. On `maxQ20GA`/`1032`, `apt-get install chrony` fully **removed** `systemd-timesyncd` as a conflicting package rather than leaving it disabled — functionally equivalent end state either way (`systemctl mask` still succeeds and creates the symlink even if the package is already gone), but don't assume the package will still be present after the install to check its state.

**Open decision, not a technical blocker:** on `rack08node01`, chrony was confirmed genuinely synced (`chronyc tracking`: `Leap status: Normal`, tight offsets) but off **public internet** NTP servers, not an internal one — the internal-server config above was never actually completed for that node (no internal address had been provided at the time). Decide deliberately whether public-internet NTP is acceptable for these compute nodes or whether they must sync internally, rather than defaulting to whatever chrony ships with.

**Validation status:** the fix is drafted and confirmed correct in root-cause terms, but full end-to-end re-validation (reinstall a node, confirm `chronyc sources`, confirm the health check itself flips PASS via `latesthealthdata`) was not completed this session on the original `1014` image — treat as not-yet-closed until that's done, even though the mechanism is well understood.

### 4.7 `cuda-dcgm` daemon missing from `baseos-1032-doca341` — confirmed root cause and fix

After `rack08node01` finished provisioning, CMDaemon's service monitor reported `cuda-dcgm` (and `mst`, see §4.8) dying and failing to restart every ~30s continuously, eventually failing `ManagedServicesOk`.

**Root cause, confirmed directly:** `systemctl list-units --all | grep -iE 'dcgm|mst'` on the live node returned empty — no units exist at all, not a crash loop. `dpkg -l` showed only `cuda-dcgm-libs` (libraries only) — **the actual daemon package was never installed on this image.** An initial guess that the correct package was some `datacenter-gpu-manager-4-*` variant (from `apt-cache search`) turned out to be wrong, and was superseded by a direct comparison against the already-working `rack01node01` (a different, already-live production node): `dpkg -l | grep -iE dcgm` there showed **`cuda-dcgm`** (the real daemon) and `cuda-dcgm-nvvs` (validation suite), both at the exact same version already present for `cuda-dcgm-libs` on the broken image — confirming the fix is simply "install the missing sibling packages," not a version-variant guessing exercise.

**Fix, applied to the image:**
```bash
cm-chroot-sw-img /cm/images/baseos-1032-doca341
chmod 1777 /tmp && rm -rf /tmp/*
apt-cache policy cuda-dcgm cuda-dcgm-nvvs   # confirm same version as already-installed cuda-dcgm-libs first
apt-get install -y cuda-dcgm cuda-dcgm-nvvs
exit
```
Then standard mount cleanup, then separately fix any node that was **already provisioned** from the broken image state directly over SSH (the image fix alone doesn't retroactively fix a live node).

**Decision: `cuda-dcgm-nvvs` (1.24GB) was ultimately NOT installed on the live-node fix** — not required for `ManagedServicesOk`/`cuda-dcgm` health checks or for `rack_lifecycle.sh`'s `pre-diag`/`post-diag` workflow, both of which only reference `cuda-dcgm.service` itself. Can be added later, off-hours, if a diag team's validation-suite tooling ends up needing it.

**Live-node fix confirmed working, including one false-alarm timing trap worth remembering generally:** immediately after installing and starting `cuda-dcgm` on the live node, a `latesthealthdata` check still showed `cuda-dcgm: FAIL` — but the sample timestamp was only 58.5s old, aligning almost exactly with the service's own start time. A check ~2 minutes later confirmed clean `PASS`. **General lesson for this whole SOP: always allow one full health-check cycle to pass before concluding a fix didn't work** — a fail right after a service starts is often just a stale sample caught mid-startup, not a real gap.

**Still pending at the time this was found:** the image-level fix had not yet been applied to `baseos-1032-doca341` itself, only to the one already-provisioned `rack08node01` — apply the image fix before provisioning further nodes from this line so they don't each need the same manual per-node SSH fix.

**Side finding while investigating this:** the `ldap` health check showed `PASS` on `rack08node01` (different from the confirmed `1014`-image regression in §4.5) — worth confirming this holds fleet-wide on this newer archive before revising that known-issue entry, since it may mean the regression is specific to the older image/fix history and doesn't apply to `maxQ20GA` at all. A separate caution surfaced alongside this: `getent passwd cmsupport` succeeding on its own is not conclusive proof of real LDAP resolution — it could be a local `/etc/passwd` fallback — while `nslcd`'s own log on the same node showed `Can't contact LDAP server` minutes into the same boot. Confirming whether `ldap: PASS` is genuinely meaningful (vs. masked by a local fallback) needs an explicit `grep cmsupport /etc/passwd` + `nsswitch.conf` check, not yet done.

### 4.8 `mst` — confirmed a pre-existing, fleet-wide non-issue, not a defect to chase

CMDaemon reports `mst` dying/failing-to-restart on freshly-provisioned nodes, same shape as the `cuda-dcgm` gap above. Investigation resolved this differently, though:

- `mst status` on the live node: `MST PCI module is not loaded` — no mechanism ever runs `mst start` (the one-shot command that loads the kernel module and creates `/dev/mst/*`) automatically. Cross-checked directly against `rack01node01` (an already-live, established production node on a completely different image/archive history): **identical** `mst status` output, and `systemctl list-units --all | grep -i mst` also empty there too. This rules out anything specific to the newer archive, `--no-cm-cuda-repo`, or this particular build — it's genuinely fleet-wide, consistent with the user's own recollection that `mst.service` has never been a real systemd unit anywhere on this fleet.
- **Mechanism clarified:** `systemctl status mst` confirms directly `Unit mst.service could not be found`. CMDaemon's generic service-monitoring feature simply maps a configured service name to `systemctl status <name>.service` — it does not create or provide the unit, only watches for one assumed to already exist. This is the identical mechanism used for `cuda-dcgm`, `nslcd`, and `rshim` in the same device-level `services` list; CMDaemon has no special-case logic per service. Since no node in the fleet has ever had a real `mst.service` unit, CMDaemon's periodic check will always report "died"/"could not restart" — that wording is CMDaemon's generic language for "expected unit not found or not active," not evidence anything ever actually crashed.
- **A real discrepancy was noticed and then explained, not left open:** `mst` doesn't appear at all in `rack01node01`'s `latesthealthdata` output, but does appear in `rack08node01`'s. Device-level `services; list` config was confirmed **identical** between the two nodes (both list `cuda-dcgm`, `mst`, `nslcd`, `rshim`, all `Monitored: yes, Autostart: yes`) — so it isn't a config difference. **Actual explanation: timing/freshness, not configuration.** `rack01node01` had been up ~1 week+; whatever restart-cycling happened on its own first boot had long since gone quiet. `rack08node01` was only ~30 minutes old at the time of the check — still inside the same initial noisy window every node goes through. Expect `mst` to eventually stop appearing in any node's `ManagedServicesOk` info column on its own, without action, once CMDaemon's retry-cycling settles the same way it has on every other established node.
- **Open, unresolved, needs an owner (not blocking):** why is `mst` in the fleet's expected-services list at all, given no node has ever had a real `mst.service` unit? Two live possibilities, neither confirmed: (1) NVIDIA's reference stack is *supposed* to ship a real `mst.service` (bundled with `mft`/`mstflint`/`kernel-mft-dkms`) and it's missing from every image built to date — a fleet-wide gap; or (2) BCM's own hardware-profile template for this platform has a stale/incorrect default, and `mst` was always meant to be a manual one-shot action, with the monitoring expectation itself simply wrong. Flag to whoever owns BCM's hardware-profile defaults, or NVIDIA support, for a definitive answer — not something to guess at per-rack.
- **Net: non-blocking for rollout and for handoff.** This is the same fleet-wide, pre-existing, already-tolerated condition surfacing on a new rack, not a new problem introduced by this build.

**Note: `rack_lifecycle.sh` has no `mst` handling anywhere** — its scope is `cuda-dcgm` only. Not yet decided whether that's acceptable to hand off as-is or needs separate resolution.

---

## 5. Provisioning Throughput & Peer-Provisioning

This is one continuous investigation that ran through most of one long session. It's presented here in final, resolved form first, then the ruled-out dead ends (kept because they're the fastest way to stop the next person from re-testing them), then the still-open secondary question.

### 5.1 The problem

Bringing up all 17-18 nodes of a rack simultaneously, all pulling from the head node, produces a clean bimodal split: roughly half the nodes finish at the genuine per-node baseline (~16-20 minutes), the other half take **3.5-4x longer** (~55min-2h). Precise timestamped measurement (start = node-installer's first `DHCPACK`; end = second `DHCPACK` + the following `update-node-params.py` cmdaemon line) confirmed this exactly on one 17-node batch: 9 fast nodes (15m53s-27m33s), 8 slow nodes (55m39s-1h01m43s), total wall-clock 1h02m50s.

### 5.2 Root cause and fix — confirmed via the BCM Administrator Manual, not further guessing

After several rounds of live-hardware trial-and-error failed to explain the split, the actual BCM Administrator Manual (§5.2 "Provisioning Nodes") was searched directly. Key documented facts:

1. **"The head node also always has a provisioning role."** A node given the `provisioning` role is never a *replacement* source, only ever an *additional* one competing alongside the head node's own implicit role.
2. **§5.2.4 — Provisioning Node Selection is load-based:** *"If there are several provisioning nodes that can provide the image required, then the task is allocated to the provisioning node with the lowest number of already-started provisioning tasks."* Not proximity- or config-scope-based.
3. **§5.2.2 — eligibility is tracked internally, not inferred from disk contents:** *"CMDaemon tracks the provisioning nodes role changes, as well as which provisioning nodes have up-to-date images available."* A provisioning node's local files happening to match the target image is **not** the same as CMDaemon's own bookkeeping recognizing it as eligible. The canonical path to that recognition is the `updateprovisioners` command, which runs automatically on role-property changes or when CMDaemon itself drives an image change — but **not** on the node's own ordinary client FULL install.
4. **§5.2.4 — Provisioning Tasks Deferral, explains the bimodal split exactly:** *"A provisioning request is deferred if the head node is not able to immediately allocate a provisioning node for the task. Whenever an ongoing provisioning task has finished, the head node tries to re-allocate deferred requests."* Combined with `Provisioning Slots` defaulting to **10** per provisioning node (§5.2.1) — if all requests land on the head node's implicit role alone, its 10-slot cap explains ~9-10 nodes served immediately and the remainder deferred until a slot frees, matching the observed group sizes and timing gap almost exactly.

**The actual failure on the first rack tested (rack08):** a designated peer node (`rack08node01`) had the `provisioning` role assigned and scoped (`localimages`, `categories`) — but this was done **before** the node had the target image installed on itself at all. It later acquired the image through a normal client FULL install (PXE), not through the `updateprovisioners` push mechanism, and per point 3 above, CMDaemon's internal "has up-to-date image" tracking was **never actually updated** for it. Confirmed directly: `rack08node01`'s own `rsyncd.log` showed **zero connections** from any of the other 16 nodes during the entire timed batch — a clean, definitive negative result, not a partial/statistical one. Configuring a node's `provisioning` role scope alone does **not** make BCM prefer it as a source.

**Confirmed fix, end-to-end, on a redo (rack01):**
1. Provision the designated peer node (`rack01node01`) alone first; confirm healthy.
2. Assign the `provisioning` role, scoped to `localimages <image>` / `categories <category>`.
3. **Run this before touching any other node — this is the step that was missing on the first attempt:**
   ```bash
   cmsh -c "softwareimage; updateprovisioners <image-name>"
   ```
4. Bring up the remaining nodes.

Result: `device; list` showed all 17 remaining nodes actively `provisioning`, **zero** in a `waiting` state — confirmed authoritatively via `lastprovisioningnode` showing `rack01node01` (not the head node) as the actual server for a sample of nodes. Confirmed working under full batch load too: checking every node's `lastprovisioningnode` showed a genuine split (9 served by the peer, 8 by the head node). **Final result: the peering-assisted 18-node batch completed in ~1h04m28s — matching the best-performing baseline of the entire investigation (rack08's original ~1h03m/17-node result, achieved with no working peering at all).** This is now understood to be the single most impactful fix of the whole investigation, and should be a required, validated SOP step for any future rack that will use a peer-provisioning node.

**Caveat on the exact command form — two different invocations were each confirmed, but never cross-tested on the same rack:**
- `rack08` (where the fix was first discovered): **bare** `updateprovisioners`, no image name, run interactively — produced an immediate, synchronous `Provisioning completed: sent ...` confirmation.
- `rack01` (the successful redo): **image-scoped** `updateprovisioners <image-name>` — produced a different, asynchronous `"...will be updated in the background"` response, confirmed working only indirectly afterward (via `lastprovisioningnode`).

Both forms individually work; they simply report differently. Don't describe them as identically validated on both racks — they weren't, they're just each individually confirmed on the rack they were used on.

### 5.3 Behavior to expect once peering is working (not bugs)

- **The split will be uneven** (e.g. 9-vs-8, not 9-vs-9) — each request is assigned to whichever source has the lowest task count *at that moment*; both sources are independently capped at the default 10 concurrent slots.
- **Allocation is fixed at request time and never dynamically rebalanced.** If the peer node finishes its entire assigned share early and sits idle for an extended period while the head node is still working through its own queue, that is expected — there is currently no mechanism to move an already-allocated (or even already-queued) request to an idle source later. Confirmed directly: rechecking `lastprovisioningnode` for the head-node-served nodes after the peer had long finished and sat idle showed no reassignment at all.
- **CMDaemon will periodically auto-resync a provisioning node's own local image copy, unprompted** — observed roughly every ~53 minutes on one run, unrelated to any specific target node's progress, most likely governed by `dirtyautoupdatetimeout`/`autoupdateperiod` (found under `partition use base; provisioningsettings; show`). Not investigated further, but worth remembering that a peer node may periodically consume some of its own bandwidth for this background maintenance during a long rollout — relevant to the dedicated-tier design idea in §5.5.
- A pending node's `cmsh` status showing `"waiting for FULL provisioning to '/' to start"` is normal queuing behind the slot cap, not a failure.

### 5.4 Dead ends — ruled out, don't re-test these

- **`provisioningslots` tuning is not the dominant lever.** Raising the head node's implicit provisioning role from 10 to 18 slots made a same-rack batch *slower* (~2h24m vs. a ~1h03m baseline elsewhere), which first looked like evidence that concurrency itself was the problem — but a same-switch, same-category retest at 9 vs. 18 slots showed only a **~3.6% difference** (2h18m vs 2h23m), nowhere near proportional to a 2x concurrency change. Reverted to the known-working default of 10; not empirically re-tuned beyond that since it clearly isn't the dominant variable.
- **NIC link speed is not rack-specific.** `ethtool enP5p9s0` showed `Speed: 1000Mb/s` on the affected rack, initially flagged as a "CONFIRMED root cause" — **this was premature.** The same reading, including the same internally-inconsistent `Supported: 10baseT` field, was confirmed **identical** on the already-fast rack once checked as a control. This is normal, expected behavior for this platform's onboard 1G management/provisioning NIC on every node, fleet-wide — not a degraded or misconfigured value on any one rack. Dead end, closed.
- **`nextinstallmode` (device-level) vs. `installmode` (category-level) is not a confound.** Both properties resolve to the identical FULL-install instruction; using one instead of the other produces no difference in install behavior. Confirmed both racks compared shared the same category `installmode: FULL` regardless of which mechanism was explicitly invoked.
- **Switch topology was investigated at length and ultimately superseded, not conclusively resolved on its own terms.** One rack (behind a two-hop `5140→5120` aggregation path) consistently outperformed another (directly attached to a `5140`) by ~2.2x, a genuinely counterintuitive "more hops is faster" result. A same-model dual-switch test produced two node failures that were later fully explained as a self-inflicted operational mistake (see §6.4), not a topology defect, and its partial timing data leaned against "any two-hop topology helps." A final, cleanest test — physically reconfiguring the slower rack to the *exact* same `5140→5120` topology as the faster one, combined with the peering fix from §5.2 applied in the correct order — produced a batch time matching the faster rack's baseline almost exactly. **This closes the investigation practically** (the peering fix was the dominant lever all along) but leaves the switch-topology question **technically unresolved** — direct switch-side diagnosis (per-port error counters, uplink utilization on the `5140→5120` link) was never done, being blocked on switch console credentials that were never obtained this session. If it matters later, that's the concrete next step, not further indirect BCM-side timing experiments.
- A secondary, minor factor worth remembering as an asterisk (not a resolution): one baseline comparison used a 17-node batch (peer node already separately provisioned beforehand) against an 18-node batch elsewhere — one fewer node in a batch does marginally reduce queue depth against a fixed slot cap, but not remotely enough to explain a 2x+ gap on its own.

### 5.5 Further contention reduction — proposed, not yet built

Even with peering working, the head node still serves roughly half the rack (~8/17 in the validated test) — contention is halved, not eliminated. The user's stated goal for production-line rollout is a genuinely **single-step** operation (trigger all N nodes at once), not the current two-step pattern (bootstrap one peer node, then trigger the rest).

- **Near-term, usable today:** extend the one-peer-node pattern to two — provision and scope two in-rack nodes as peer sources before triggering the remaining 16, structurally reducing the head node's expected share from ~8/17 toward roughly ~5-6/17. Still a two-step operation, just with one more bootstrap node. Not yet tested.
- **Long-term (blocked, hardware doesn't exist yet):** a dedicated, standalone provisioning-source tier — 1-2 nodes on their own separate hardware, permanently provisioned and idle, each scoped with the `provisioning` role and kept current via `updateprovisioners` whenever a new image is qualified. Per the manual's "lowest task count" allocator, this generalizes naturally to 3+ sources with **zero bootstrapping step per rack rollout** — genuinely single-step from the production line's perspective. Deliberately **not** finalized on topology/placement — the target rack for this doesn't exist yet, and given everything learned about switch-path sensitivity this session, placing these nodes behind an unknown or poor switch path could reintroduce the exact bottleneck class being solved for.

---

## 6. PXE Boot, BMC, and Network Topology

### 6.1 `pxe_rack_provision.sh` — capability summary
Supports: `--dry-run`, `-power on|off|cycle`, `-pxe`, `--rack N|N-M`, `--node N` (single) or `--node N-M` (range, added mid-session — validated the same way `--rack`'s range already was, backward-compatible with single-node use), `--nodes N`, `--delay N` (stagger between targets; default `0`, meaning a full rack hits DHCP/TFTP simultaneously), `-U`/`-P` credential overrides, `--pxe-method ipmitool|redfish` (added later — see §6.2), `--version`/`version`. Current version: **1.2.0**.

### 6.2 Redfish one-shot PXE override — mechanics and hard constraints

Two different BMC-level PXE mechanisms exist and were confirmed **not** equivalent by default: the script originally only used `ipmitool ... chassis bootdev pxe options=efiboot` (next-boot flag), while the mechanism actually validated by hand to reliably land on the correct NIC was the **Redfish** `BootSourceOverride` PATCH:
```bash
curl -k -u root:0penBmc -X PATCH \
  -H "Content-Type: application/json" \
  -d '{"Boot": {"BootSourceOverrideEnabled": "Once", "BootSourceOverrideTarget": "Pxe"}}' \
  https://<bmc-ip>/redfish/v1/Systems/System_0
```
**Hard constraint:** `BootSourceOverrideEnabled` must always be `"Once"`, never `"Continuous"` — this must never be made persistent. This BMC's `BootSourceOverrideTarget` only supports the generic `Pxe` enum value (no per-NIC targeting like `UefiTarget`/`BootNext`), so which physical NIC it resolves to is entirely a function of `BootOrder` ranking at boot time, not something this PATCH can force directly. `System_0` is the whole-host Redfish resource, not a per-NIC one — `HGX_Baseboard_0` is a separate, non-bootable baseboard endpoint, easy to confuse but unrelated. If a firmware's `BootOrder` ever needs changing to reliably land on a specific NIC, that is a **separate, persistent** change requiring its own explicit sign-off — never fold that into a routine "PXE override" request.

Added to `pxe_rack_provision.sh` as `--pxe-method ipmitool|redfish` (default `ipmitool`, backward-compatible); `redfish` combined with `-power`-only mode is rejected at parse time since that mode never sets a PXE flag at all. **`REDFISH_SYSTEM_ID` ("System_0") is confirmed only for this specific BMC/hardware** ("CARLO_NEXT-T1") — flagged in the script's own comments as something to re-verify, not assume, on different hardware.

**Confirmed effective via direct evidence, not just an HTTP 2xx:** a DHCP log for the override boot window showed only the intended 1G port's MAC issuing `DHCPDISCOVER` — no other MAC attempted PXE at all. Total boot-to-node-installer time was ~3m37s, matching the user's previously-reported "~3 minutes" experience — but this appears to be normal POST + PXE-software-boot time on this hardware platform, not evidence that BF3 was being attempted first (see §6.3). **The override works exactly as designed; it may not actually be reducing that ~3-minute figure**, since that time likely was never attributable to NIC ordering. Worth keeping as an explicit, auditable guarantee regardless.

### 6.3 Why BlueField-3 never appears as a PXE boot option — fully explained, not just observed

Full chain of investigation, now conclusively resolved:
1. Cross-referencing all 11 UEFI boot options against BF3's confirmed PCIe address (`0016:01:00.x`, via `mst status -v`) showed **none** of the 11 boot options reference that address at all — not merely low-ranked, genuinely absent from the boot-options collection. A second MAC seen in the boot options, initially suspected as possibly BF3, was later assessed as more likely a BMC-shared/virtual management NIC (its `UefiDevicePath` routes through a `USB(...)` pattern, and it doesn't match BF3's real PCIe location either).
2. Direct `mlxconfig -d 0016:01:00.0 query` against BF3 itself **settles the question**: `EXP_ROM_PXE_ENABLE`, `EXP_ROM_UEFI_x86_ENABLE`, `EXP_ROM_UEFI_ARM_ENABLE` are all `True`, and `LEGACY_BOOT_PROTOCOL` is `PXE` — **PXE is not disabled at the firmware level.** But `LINK_TYPE_P1`/`LINK_TYPE_P2` are both `IB` — **both BF3 ports are configured for native InfiniBand, not Ethernet.** Standard PXE requires an Ethernet-mode port; a port in native IB mode simply never presents as a PXE-capable Ethernet NIC to firmware, so no boot option gets generated for it, regardless of `EXP_ROM_PXE_ENABLE` being true. This is a deliberate IB fabric-role configuration for this GB300 NVL node, not an oversight — consistent with `mst status -v`'s "ib"-prefixed interface naming (`net-ibP22s22f0`/`net-ibP22s22f1`) seen throughout.
3. **A separate, additional layer was then found via `dmidecode -t 9`, correlated against confirmed PCI domains:** exactly six PCIe slots on this platform are `x16 Gen5` "NIC Slot" designations (4× ConnectX-8 + 1× BlueField-3, one currently unpopulated), and the BIOS `Bios/Attributes` payload shows **exactly six** `DisableOptionROM: true` entries, all on `x16`-width slots — count and width class both matching precisely. The 1G port's own slot (`x1 Gen3`, a different class entirely) is not among them. **Working conclusion (strong inference, not a confirmed 1:1 documented mapping):** this platform's BIOS deliberately disables PCIe option-ROM execution on all large fabric-facing NIC slots, leaving option ROM enabled only on the small onboard 1G management port meant for host provisioning. This is architecturally coherent — it explains, in one story, both why the 1G port has always been the only PXE-capable option and why the link-type change in step 2 could not, structurally, have produced a new PXE boot option on its own.

**Explicit limits on this conclusion, not resolved:** the exact `Socket*Pcie*` BIOS attribute → physical slot mapping is inferred from matching counts/widths, not from any documented 1:1 correlation. **Do not flip any `DisableOptionROM` setting on live hardware without confirming the exact mapping via OEM platform documentation or vendor support first** — a wrong guess could disable option ROM on an unrelated PCIe root port with unknown consequences. This finding does not roll back the link-type change (that remains durable and correct for the IB fabric requirement); it only explains why that change alone could never have been sufficient for PXE. Treat enabling BF3/CX8 as PXE-bootable via BIOS changes as a separate, higher-risk follow-up needing vendor confirmation, not something to attempt mid-rollout on production-track hardware.

### 6.4 Power-sequencing gotcha: never chain a power-off immediately followed by another power action

During one topology test, two nodes failed with `INSTALLER_UNREACHABLE` (10-minute timeout) after reaching `INSTALLER_CALLINGINIT`. Initially hypothesized as a network loop from an added switch — **retracted**. Root cause, confirmed via `dmesg`: a continuous, repeating `ACPI: Graceful shutdown in progress` loop, meaning the node received an ACPI shutdown signal mid-install and got stuck trying to honor it. Confirmed via the exact command timeline: an explicit `-power off --rack N` was followed only ~90 seconds later by the default full-workflow's own `power cycle` — many BMCs implement a plain `chassis power off` as a graceful ACPI shutdown request rather than an instant hard cut, and the follow-on power-cycle command arrived while the node was still mid-shutdown, leaving it stuck rather than cleanly cycling. **This was a self-inflicted operational sequencing mistake, not a topology or network defect** — the dual-switch test's own validity for the throughput question was not undermined by it. Fix for the stuck node: a single clean `ipmitool ... chassis power cycle`.

**Standing rule for `pxe_rack_provision.sh`/SOP use: never issue a power-off against a rack and then immediately re-trigger the default full workflow (or any other power action) against the same targets within the same short window.** Confirm power is genuinely settled first (poll BMC power status, or wait longer) before any follow-up power-affecting command.

---

## 7. Rack Lifecycle / Handoff (`rack_lifecycle.sh`)

Current version: **1.2.0**. Subcommands: `status` (read-only snapshot), `handoff` (one-way off-cluster transition), `pre-diag`/`post-diag` (reversible `cuda-dcgm` service toggle around diag testing), `finalize` (deliberately unimplemented — exits with an error on purpose — pending a decision on what "production-ready" actually requires: does a node rejoin the BCM network, or move to a separate production network with the off-cluster fixes staying in place?).

### 7.1 `handoff` — what it does, in order
1. Comments out a stale `DNS=10.141.255.254` line in `/etc/systemd/resolved.conf` (only if present), restarts `systemd-resolved`.
2. Tries to preserve `cmsupport` as a **local** account before LDAP is cut off.
3. Stops and disables `nslcd`.
4. Strips `pam_ldap.so` from the PAM stacks.
5. Sets `nsswitch.conf` (`passwd`/`group`/`netgroup`) to `files` only.
6. Automatically disables **CMDaemon's own monitoring** of `cuda-dcgm` for the whole target list (one `cmsh` call from the head node, not per-node) — folded in per explicit request, see §7.3.

**This is deliberately, by-design different from §4.5's `nsswitch.conf` regression** — that was an accidental bug from an unrelated fix that broke `cmsupport` in-cluster; this is an intentional, controlled step for racks genuinely leaving the BCM network, with its own explicit safeguard (step 2). Don't conflate the two.

**⚠️ One-way.** There is no rejoin/finalize path implemented. Once run, a node does not return to BCM-managed state on its own or via reboot.

**⚠️ Unresolved bug: `cmsupport` has ended up missing entirely (neither LDAP-resolvable nor a local account) on every node handed off so far (rack08, all 18 nodes).** An initial theory — that step 1's DNS edit broke step 2's `id cmsupport` check — was disproven (`getent hosts ldapserver` resolves fine via static `/etc/hosts`-style cluster aliases, independent of the DNS setting changed). Root cause not found; the real `handoff` run's console output (not the dry-run, which executes nothing) would show which branch step 2 actually took on each node, and hasn't been captured/reviewed yet. **Not fixed in the script.** Immediate mitigation (manually recreating `cmsupport` locally with `uid=1000, gid=1000, group=pega`) was offered but not confirmed executed. **Always verify with `status` after every handoff — never assume this step worked.**

### 7.2 `pre-diag` / `post-diag` — and why the CMDaemon-level override was necessary

`pre-diag` disables (`disable --now`, not just `stop`) `cuda-dcgm.service` — confirmed root cause of an earlier `SYNC_CLIENT_NOT_REGISTERED` diag failure was DCGM holding `/dev/nvidia*` open and blocking a diag tool's module-unload step. `disable`, not just `stop`, matters because a plain stop only affects the current boot, and a diag campaign can plausibly include a power cycle mid-campaign. `post-diag` restores whatever active/enabled state `pre-diag` recorded in `/etc/rack-lifecycle-state`.

**First real test found the systemd-level disable alone wasn't durable:** CMDaemon monitors `cuda-dcgm` independently of systemd via device/category-level `services` config, and silently restarted it within minutes of `pre-diag`'s disable — confirmed via `journalctl`. Fix: an explicit CMDaemon-level override, applied once from the head node:
```bash
cmsh -c "device foreach -g <nodegroup> (services; add cuda-dcgm; set monitored no; set autostart no; commit)"
```
Re-tested with this override in place: `pre-diag` held — no restart occurred, confirmed `Active: inactive (dead)` stayed put after `reset-failed`. (The `active=failed` state seen right after disabling is itself benign, not a new problem — the unit's own `ExecStop` script races the clean stop, finds no pidfile, and exits 1 even though the actual outcome is correct; `pre-diag` now runs `systemctl reset-failed cuda-dcgm.service` automatically to clear this cosmetic state.)

**Per explicit request, this CMDaemon-level override was then folded directly into `handoff` itself** (not left as a manual step, not tied to `--with-pre-diag`), via a new `disable_cmdaemon_dcgm_monitoring()` function that runs once (not per-node) right before the main dispatch loop, only for the `handoff` subcommand. It only fires automatically when targets were resolved via `--rack`/`--category` (which already proves `cmsh` is reachable); for `--ip-range`/`--rackgroup` targeting it prints a manual fallback command instead of guessing at `cmsh` availability. **Deliberately a smaller, more permanent action than `pre-diag`:** it only stops CMDaemon's own monitoring/auto-restart — it does **not** stop the `cuda-dcgm` service itself. `cuda-dcgm.service` keeps running normally after a plain `handoff`; only `pre-diag` (or `handoff --with-pre-diag`) actually stops it. **Not automatically undone by `post-diag`**, which only manages systemd-level state — reversing it requires a separate manual `cmsh` call (`services; use cuda-dcgm; set monitored yes; set autostart yes; commit`, or `services; remove cuda-dcgm; commit` to fall back to the `[general]` default).

**`--with-pre-diag`** runs `pre-diag` immediately after `handoff` in the same invocation — opt-in, since `handoff` and starting diag testing are different lifecycle moments that don't always happen back-to-back, and making the GPU-monitoring disable automatic on every handoff would lose monitoring on any rack that isn't testing immediately. The two actions it compounds have **asymmetric reversibility** (handoff is permanent; `pre-diag`'s disable is reversible via `post-diag`, but only if someone remembers to run it) — the flag requires a typed `yes` confirmation stating this plainly (skipped only under `--dry-run`).

**Also confirmed fragile against unrelated category changes — see §4.4:** any category-level `commit` during an active diag campaign can silently re-enable `cuda-dcgm` across the whole rack as a side effect, even with the CMDaemon-level override in place. Re-verify with `status` after any category-level change made during a live campaign.

### 7.3 Script version history
- **1.0.0** — original upload (`status`/`handoff`/`pre-diag`/`post-diag`/`finalize` placeholder).
- **1.1.0** — added `--with-pre-diag` to `handoff`.
- **1.2.0** — fixed a real `do_status` bug (`$(cmd || echo fallback)` concatenated real stdout printed even on non-zero exit with the fallback text, producing garbled output — fixed via two-step variable capture); `pre-diag` now auto-runs `systemctl reset-failed`; the CMDaemon-level `cuda-dcgm` monitoring disable was folded into `handoff` automatically (§7.2); `--with-pre-diag` now requires typed `yes` confirmation.

---

## 8. Standalone Incidents

### 8.1 Head-node `devtmpfs` lost core device nodes — resolved via reboot, root cause never confirmed

First surfaced as a `cm-create-image` failure (`Validating repo configuration` → `Failure getting installed package list`) under `dgx_gb300` — investigated as a possible dgx-type defect, but a `dgx_gb200` control build failed identically, correctly redirecting the investigation to the host. The real error underneath: `/dev/null is not a char or block device, cannot copy.` Direct checks confirmed `/dev/null` was genuinely missing (not just wrong-typed), and a wider sweep found `/dev/zero`, `/dev/random`, `/dev/urandom`, `/dev/tty`, `/dev/console`, `/dev/full`, and `/dev/nvme0` **all** missing too. `/dev` was correctly mounted as `devtmpfs` and `systemd-udevd` reported healthy throughout — `mount -o remount /dev` and `udevadm trigger && udevadm settle` both failed to repopulate anything, not normal degraded behavior for a live devtmpfs. Manually recreating standard nodes with `mknod` worked as a stopgap but was explicitly treated as incomplete (doesn't cover hardware-specific nodes like whatever backed `/dev/nvme0`). **Resolution: a full reboot of the head node** — all nodes confirmed present afterward, and the next build completed successfully.

**Root cause never established.** Candidates considered, none confirmed: a mistyped/malformed unmount during this session's own repeated `cm-chroot-sw-img` cleanup work possibly affecting the host's real `/dev` instead of just the image directory's bind-mounted copy (never definitively ruled out or confirmed); independently-logged `dmesg` filesystem/scheduling-stress warnings around the same window with no established causal link; continuous `dhclient` errors likely a downstream symptom of the broken `/dev` rather than a separate problem. **This head node manages 144 other production nodes and this should not be treated as fully closed** — worth a proper post-incident review (system logs from the actual window, correlated against exact command history) with whoever else holds admin/on-call responsibility for this system, separate from the rack-build work.

**Practical implication for future racks:** don't assume `--dgx-type` is the cause of a "Validating repo configuration" failure without first checking `ls -la /dev/null` on the head node directly — this exact on-screen failure now has two known, unrelated root causes (this incident, and the duplicate-CUDA-repo conflict in §3.3.5), and the message doesn't distinguish them. If `/dev` is genuinely missing nodes, that's a host-level incident, not something fixable by changing `cm-create-image` flags — check host `/dev` **before** re-running any chroot-cleanup or `cm-create-image` command, given the (unconfirmed but not ruled out) possibility that mount-cleanup activity is implicated.

### 8.2 NVSwitch devices landing in the wrong DHCP pool

Nine `nvs-rack01swN` NVSwitch management-interface devices were added to BCM's device list while a provisioning timing test was actively in progress — flagged as a possible confound for that test's timing data (different subnet, but potentially sharing upstream switch capacity), and separately, two of the nine (`sw1`, `sw2`) showed `state flapping` rather than a simple `DOWN`, suggesting an actual intermittent link/cabling issue worth investigating on its own. Several of the nine (`sw3`-`sw9`) subsequently landed in the generic compute-node DHCP pool instead of their expected static range — resolved via manual static-IP configuration directly on each switch's own `nvos` CLI (not a BCM/`cmsh`-side fix), consistent with BCM's device/interface object for this device class being passive bookkeeping rather than something that actively pushes config to the switch. All nine correctly show `[DOWN], pingable` rather than `[UP]` afterward — expected, not a new concern, since no CMDaemon agent runs on these devices at all; `pingable` is the meaningful positive signal for this device class.

---

## 9. Tooling / Scripts Reference

| Script | Current version | Purpose |
|---|---|---|
| `sw_checklist.sh` | — (bug-fixed, backup at `.bak`) | Post-install software/driver/kernel verification checklist. Had a hold-detection bug against the wrong package names (§1); NVIDIA driver version field still shows `[CHECK]` unexplained. |
| `l10-upgrade.sh` | 0.1.1 | Single-node, 3-step gated/idempotent **field** upgrade script (not BCM-based) — kernel exact-pin swap (self-terminates on reboot, manual re-invoke), DOCA+driver+IMEX install, BF3/CX8 firmware flash (needs a full power cycle, not just reboot). Config-driven (all versions in one editable block), versioned, kept as a single file per team preference. Firmware tool invocations (`bfup`, `mlxfwmanager`) are **unverified placeholders** — confirm against real `--help` output before trusting on hardware. |
| `pxe_rack_provision.sh` | 1.2.0 | Rack-range PXE/power orchestration. History: 1.0.0 original → 1.1.0 added `--node N-M` ranges → 1.2.0 added `--pxe-method ipmitool|redfish`. See §6.1-§6.2. |
| `rack_lifecycle.sh` | 1.2.0 | Post-BCM-provisioning handoff/diag lifecycle (`status`/`handoff`/`pre-diag`/`post-diag`; `finalize` unimplemented). See §7. |
| `NV-kernel-doca-compat-report.md` | draft, **not yet sent** | NV escalation report — needs updating per §10 before sending. |

---

## 10. Open Items & Escalations (priority order, current as of the last session entry)

1. **`6.17.0-1014` + DOCA `3.4.1` compatibility — untested.** The one piece needed to fully confirm `1014` as a genuinely dual-compatible field-upgrade kernel. §2.1.
2. **`dgx_gb200` vs `dgx_gb300` — build viability confirmed for both, correctness for real GB300 NVL hardware still unconfirmed with NV.** Do not treat a successful build as settling this. §3.4.
3. **NV escalation report — drafted, not yet sent.** Needs: the `dgx_gb200`/`gb300` question reframed with the new `kernel-param-syncer` evidence (§3.4); the CPU stream-score item reframed as "internally assessed as not customer-relevant" pending NV's own confirmation; the `1014`+3.4.1 result once tested; the original open questions (1016 nonexistence, patched-source availability for 1018/1029, CPU-score fix timeline, long-term kernel target).
4. **`nsswitch.conf`/SSSD fix — genuinely unresolved.** The hang is real, the fix that solved it is a confirmed `cmsupport` regression, and neither of the two candidate revised fixes has been designed or validated yet. §4.5. Do not bake anything back into the reference image until one is validated.
5. **`ntp`/chrony fix — root-caused and drafted, but not fully re-validated end-to-end** on the original `1014` image (reinstall + `chronyc sources` + `latesthealthdata` PASS confirmation still pending). Decide the internal-vs-public-NTP question deliberately. §4.6.
6. **`/swap.img` sparse-file inflation — confirmed, no fix chosen yet** (fix tar sparseness vs. simply exclude the file). Costs ~8GB per image × 8 racks if left unaddressed. §3.3.8.
7. **`6.8.0-106-generic-64k` build-time cost — reproduces reliably, mechanism not pinned down**, costs ~8.5hrs/build via redundant DKMS/OFED cycles. Worth an NV/BCM support report; `/var/log/apt/history.log`/`term.log` inside the image were never pulled to nail the exact disposal mechanism. §3.3.2.
8. **Head-node `devtmpfs` incident — root cause never established**, worth a proper post-incident review outside the scope of rack-build work. §8.1.
9. **`BF3PcieInterfaceTraffic` partnerdiag fix — delivery mechanism (the `127.0.1.1` hostname fix) is validated, but whether it actually fixes the original partnerdiag failure has never been re-confirmed.** §4.3.
10. **`mst`'s presence in the fleet's expected-services list — needs an owner to give a definitive answer**, not blocking. §4.8.
11. **Cascade/orchestration layer for 144 nodes/8 racks — design discussed, not built**, blocked on the team's own topology decision (direct SSH vs. jump-host-per-rack vs. multi-hop) and inventory format. §11.
12. **Switch-topology question for provisioning throughput — technically unresolved**, though practically superseded by the peering fix. Blocked on switch console credentials that were never obtained. §5.4.
13. **`rack_lifecycle.sh`'s `cmsupport`-missing bug — unresolved root cause**, needs the real `handoff` console output reviewed. §7.1.
14. **Whether an off-box backup of the reference host's pre-BCM-capture state exists — never explicitly confirmed**, worth checking given the root LV has zero LVM snapshot headroom (§1).
15. **Per-node identity regeneration (machine-id, SSH host keys, hostname) — not yet confirmed how/whether BCM's node-installer handles this automatically.** Check the BCM "Assigning Images to Nodes and Post Installation Configurations" documentation section directly rather than assuming.
16. **`gpu_health_overall` FAIL despite all per-GPU sub-checks PASS** on at least one node (`rack01node01`) — cause unknown, not investigated.
17. **`finalize` subcommand of `rack_lifecycle.sh` — deliberately unimplemented**, pending a decision on what "production-ready" actually means for a handed-off node (rejoin BCM, or move to a separate production network keeping the off-cluster fixes).

---

## 11. Scaling Context (for future sessions)

- **Eventual target:** 8 racks × 18 nodes = 144 nodes, via a "cascade through layers of switches" topology — exact network shape (flat vs. per-rack jump host vs. multi-hop) not yet determined, pending the team's own diag-team discussion.
- **Team preference: plain bash scripts, not Ansible** — despite the reference host already having `.ansible/`/`hosts.ini`/`CX8_BF3_config.yml` present (used for BF3/CX8 config specifically, not adopted for this upgrade workflow by team choice).
- **Proposed, not yet built:** a separate `node-agent.sh` (the current `l10-upgrade.sh`) plus a `cascade-orchestrator.sh` doing canary-first rollout (1 node → gate → 1 per rack → gate → remaining fleet), concurrency-throttled SSH, centralized result aggregation. Blocked on topology info from the team.
- The near-term/long-term provisioning-source scaling ideas in §5.5 (2-node in-rack bootstrap; dedicated standalone tier) are the most directly relevant pieces of this scaling design once the topology question is settled.

---

## Appendix A — Known-Acceptable States (do not re-debug on future racks)

| Symptom | Verdict |
|---|---|
| `cm-create-image` build takes several hours, mostly "stuck" on "Installing CM packages" | Expected — DKMS/OFED build against throwaway `6.8.0-106` kernel. §3.3.2. Not a hang. |
| Image's own `/boot/grub/grub.cfg` has no real kernel `menuentry` | Expected — node-installer doesn't use this file. §3.2.11. |
| `Setting up`/`Removing` never logged for `linux-image/modules/tools-6.8.0-106*`, yet `dpkg -l` shows them absent afterward | Reproduces reliably; end state confirmed correct even though the exact log mechanism is unresolved. §3.3.2. |
| `Finalizing cluster services` logs a `systemctl disable <service>` failure (e.g. bind9) for a service never installed | Non-fatal, build continues. §3.3.6 — different from the Fabric Manager case, which **is** fatal. |
| `nvidia-fabricmanager-580` version doesn't match the DKMS-built driver version | Irrelevant — package is masked and never runs; real FM runs off-host on the NVSwitch tray. §3.3.1/§3.3.7. |
| `cm-chroot-sw-img` reports mounts "already mounted" on entry | Expected if the mount-cleanup step wasn't run after the previous session — run it, don't ignore the warning. §3.3.3. |
| Per-session `/var/tmp/<random>` tmpfs still mounted after chroot exit, `umount` reports "target is busy" | Same category as above — exit doesn't always fully unmount. Check `fuser -vm <path>` before forcing; low-risk to leave. |
| A provisioned node's `/home` contains files/dirs not present in the source image | Not a bug — `excludelistupdate` includes `/home/*`, so update-style (non-`FULL`) installs deliberately never touch it, leaving prior-cycle content untouched. Check the image directly on the head node, not a live node's `/home`, for what the image actually ships. |
| `Validating repo configuration` fails with `Failure getting installed package list`, regardless of `--dgx-type` | Check the head node's own `/dev/null` first (§8.1) before assuming a repo conflict (§3.3.5) — two known, unrelated causes share this exact message. |
| PXE node-installer fails fatally on `interfaces.d/ifcfg-<iface>` or `ntpsec/ntp.conf` on first boot | Missing target directories in the image, not a package problem. Fix per §3.2.7 — check on every rack, doesn't survive a fresh `-a` rebuild. |
| PXE node-installer halts with `Missing device. Node Installer will halt.` during "Fetching disks setup" | Category `disksetup` likely unset, not a capacity problem. Fix per §3.2.8; pre-flight-check every remaining rack. |
| `gpu_health_nvlink`/`gpu_health_overall` FAIL right after a fresh rack is provisioned | Expected until the rack's NVSwitch fabric manager (GFM) is configured — a rack-infrastructure property, not a compute-image defect. |
| SSH host-key mismatch warning on first connect to a freshly-reinstalled node | Expected — every reinstall regenerates host keys. `ssh-keygen -R <hostname>` before first connect. Also seen on already-established nodes, suggesting the fleet's `known_hosts` is generally out of sync — worth a one-time bulk cleanup rather than clearing entries one at a time. |
| "Reboot required: Interfaces have been modified" warning immediately post-install | Universal, routine post-install artifact confirmed on effectively every node across every rack tested — no observed negative effect on subsequent health. |
| `cuda-dcgm`/`mst` reported "died"/"not restarted" by CMDaemon on a node with no such systemd unit ever installed | For `mst`: fleet-wide, pre-existing, non-functional-impact condition — see §4.8. For `cuda-dcgm`: only benign if the real daemon package (`cuda-dcgm`, not just `-libs`) is confirmed installed and just caught mid-startup (§4.7) — if the package itself is missing, this is a real gap, not acceptable. |

## Appendix B — Quick Command Reference

```bash
# Mount cleanup after any cm-chroot-sw-img session (§3.2.4)
umount -l /cm/images/<image-name>/sys/firmware/efi/efivars
umount -l /cm/images/<image-name>/var/tmp/* 2>/dev/null
for m in dev/pts dev proc sys run/systemd/resolve/resolv.conf run; do
  umount -l "/cm/images/<image-name>/$m" 2>/dev/null
done

# Peer-provisioning setup, correct order (§5.2)
# 1. Provision the peer node alone, confirm healthy, then:
cmsh
% device use <rack>node01
% roles
% assign provisioning
% set localimages <image-name>
% set categories <category-name>
% commit
# 2. BEFORE touching any other node:
cmsh -c "softwareimage; updateprovisioners <image-name>"
# 3. Then bring up the rest, and verify:
cmsh -c "device use <rack>node05; lastprovisioningnode"

# rack_lifecycle.sh handoff, with the CMDaemon-level DCGM override now automatic (§7.2)
./rack_lifecycle.sh handoff --rack <N>
./rack_lifecycle.sh status --rack <N>          # verify, especially cmsupport (§7.1)
./rack_lifecycle.sh handoff --with-pre-diag --rack <N>   # only if diag starts immediately

# Never do this (§6.4):
# -power off followed shortly by any other power action on the same targets
```
