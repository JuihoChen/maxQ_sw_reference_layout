# GB300 NVL L10 Reference Layout — Build Log

**Reference:** NVIDIA 2.0 release, GB300 L10 reference layout — MNNVL Bring-Up Guide, Release 1.15
**Checklist script version:** `gb300_l10_sw_checklist.sh` v0.4.28

## 0. Host Software Components — Version Matrix (source of truth)

Pinned versions per NVIDIA 2.0 release matrix. Confirmed `DOCA_Host` here (3.4.1-010000) is correct, overriding the public DOCA downloads page's current default landing version (3.4.0) — public page just hadn't surfaced the pinned point release by default.

**CUDA Toolkit corrected to `13.0.2`** (was previously `12.8` in this table, based on an earlier assumption — not an NVOnline-sourced confirmation). Verified via NVOnline **1160245** ("GB300 NVL72 MAXQ Software and Firmware Source of Truth Metadata File, 2.0.0RC4"), Table 2 (Public Release Links Associated with this Release), which pairs `Datacenter Driver Version 580.173.02` with `CUDA Toolkit 13.0.2` — the driver version is an exact match to what's already installed and confirmed via `nvidia-smi` in §7, giving high confidence this is the correct pairing.

| Component | Version |
|---|---|
| Kernel Module Source (NVIDIA driver) | `NVIDIA-kernel-module-source-580.173.10.tar.xz` (was `580.173.02` under RC4 — see §0a) |
| IMEX | `580.173.10` (tracks driver — installed from the same `.run` bundle, see §7) |
| CUDA Toolkit | `13.0.2` |
| MFT Tools | `4.36.0-147` |
| WinOF-2 | `26.4.27095` |
| DOCA_Host | `3.4.1-010000` |
| Fabric Manager (`nvidia-fabricmanager`, host package) | tracks Datacenter Driver (`580.173.10`) — sourced from the `nvidia-driver-local-repo` package, not an independent release train (corrected §0a) |
| NMX-M | `85.1.1100` (was recorded as `20v85.1.1100_85.1.1100.pdf` under RC4 — see §0a) |
| BF3 (firmware) | `32.49.1118` |

*Note: WinOF-2 is the Windows NIC driver and not applicable to this Ubuntu 24.04 L10 layout — listed here for completeness against the source matrix only.*

### NVOnline ID Reference (source: GB300 NVL72 2.0.0RC4 release table)

Master download manifest — every remaining stack component maps to one of these IDs on NVOnline.

| NVOnline ID | Version / Contents |
|---|---|
| 1160211 | Compute Tray Firmware for GB300 MaxQ NVL72 2.0.0RC4 |
| 1159830 | Switch Tray Firmware for GB300 NVL72 2.0.0RC4 |
| 1159832 | NVOS for GB300 NVL72 2.0.0RC4 |
| **1159833** | **CX8 and BF3 Firmware, Drivers, and Tools for GB300 NVL72 2.0.0RC4** ← ConnectX-8 firmware source |
| 1138693 | NMX-M Package for the 1.0.00 Software Release |
| 1160161 | GPU Drivers for GB200/GB300 NVL72 2.0.0RC4 |
| 1160245 | GB300 NVL72 MAXQ Software and Firmware Source of Truth Metadata File, 2.0.0RC4 |

**Confirmed:** ConnectX-8 firmware `.bin` sourced via NVOnline ID **1159833**, not the DOCA-Host package (DOCA-Host installs the MFT *tooling*; the firmware image itself comes separately from this ID). Same likely applies to BlueField-3 firmware under the same ID.

## 0a. 2.0.0GA Reconciliation — 2026-09-14

**NVIDIA has published the official GA release notes** (`RN-11874-001_2.0.0GA`, "NVIDIA GB300_Max-Q_NVL72_P4059_CX8_Release_2.0.0GA Release Notes"). This is now the authoritative source and supersedes NVOnline **1160245**'s RC4 metadata file (`GB300 NVL72 MAXQ Software and Firmware Source of Truth Metadata File, 2.0.0RC4`), which everything through §16 above was pinned against. Diffing the two:

| Component | RC4 (superseded) | 2.0.0GA (current) | Change |
|---|---|---|---|
| GPU Driver / Kernel Module Source | `580.173.02` | `580.173.10` | **Changed** |
| IMEX | `580.173.02` | `580.173.10` | **Changed** (tracks driver) |
| CUDA Toolkit | `13.0.2` | `13.0.2` | No change |
| MFT Tools | `4.36.0-147` | `4.36.0-147` | No change |
| WinOF-2 | `26.4.27095` | `26.4.27095` | No change |
| DOCA_Host | `3.4.1-010000` | `3.4.1-010000` | No change |
| BF3 firmware | `32.49.1118` | `32.49.1118` | No change |
| CX8 firmware | `40.49.1118` | `40.49.1118` | No change (confirmed against the GA notes' "CX8 N/S" section) |
| NMX-M | `20v85.1.1100_85.1.1100.pdf` | `85.1.1100` | Corrected — the RC4-era value was a bundle/filename artifact, not a clean version string |

**Fabric Manager — correction, not just a version bump.** RC4 metadata's `GFM: 580.173.04` (§16, Finding 2) was carried into §0 as if it were this host's Fabric Manager target. It isn't, and the earlier correction was wrong on the merits, not just stale: `nvidia-fabricmanager` (the host-side package, §25) is sourced from `nvidia-driver-local-repo-ubuntu2404-<driver-version>` and versioned `<driver-version>-1ubuntu1` — i.e., it **tracks the Datacenter Driver branch**, not an independent number. §16's Finding 2 is superseded. Whatever `GFM: 580.173.04` in the RC4 file actually referred to (most likely the NVSwitch tray's own NVOS-side Fabric Manager, a functionally separate thing from this compute-host package — see §25/note_na rows) is not confirmed against GA and should not be assumed equal to either the old `580.173.04` value or the new driver version without checking NVOS directly.

**New in GA — out-of-band firmware baseline not previously tracked at all** (BMC, MCU, HMC pages of the GA notes):

| Section | Component | GA Version |
|---|---|---|
| BMC bundle | BMC core | `GB200Nvl-26.07-1` |
| BMC bundle | EROT | `01.04.0055.0000_n04` |
| MCU | SMA Firmware | `0003.00.0278.0000` |
| HMC | CPLD | `0.22` |
| HMC | GPU (= VBIOS — see correction below) | `97.10.7D.00.16` |
| HMC | EROT | `01.04.0055.0000_n04` |

**Correction (2026-09-14):** the HMC table's "GPU" row is not a separate out-of-band Redfish-queryable firmware component — it's **VBIOS**, in NVIDIA's raw-hex notation, the same field `nvidia-smi` already reports. This reopens an unresolved thread from **§16** (RC4 era): that section logged VBIOS as `97.10.7D.00.0D` from the RC4 metadata and noted it "doesn't obviously match the already-confirmed-installed `97.10.59.00.13`," but treated the difference as possibly just notation and left it as an awareness-only note with no comparison target ever wired up. GA's value (`97.10.7D.00.16`) shares the **exact same `7D` segment** as the RC4 value — only the last segment moved (`0D` → `16`, a plausible RC4→GA build increment). Two independent NVIDIA-sourced metadata snapshots, weeks apart, agreeing with each other on `7D` while this host's actual installed VBIOS (`97.10.59.00.13`, unchanged throughout the entire build, correctly so since VBIOS isn't touched by driver installs) disagrees with both, is meaningfully stronger evidence of a **real VBIOS mismatch** than §16's original framing allowed for. Checklist v0.4.25 now wires `EXPECTED_VBIOS="97.10.7D.00.16"` into the existing "VBIOS Version" check, which previously had no comparison target at all. **Not yet investigated further** — whether this needs an actual VBIOS flash (a separate procedure from anything done in §7g/§10a, typically via `nvflash` and requiring its own caution around board-specific images) or is explained by something not yet considered is open.

The checklist script's §6b (Out-of-Band Firmware / Redfish) already reads BMC/EROT/CPLD/SMA live from the BMC's `FirmwareInventory` rather than needing per-component `EXPECTED_*` pins for those; VBIOS is checked separately via `nvidia-smi`, not through this Redfish path.

**Action item — not yet applied to any built system.** `carlonext` (§7), the `maxQ20rc4-1029-doca341-baseos.tgz` tarball (§25a/§25b), and the provisioned `rack08` (§25c) are all still on the RC4-era `580.173.02` driver — that's accurate history, not something to rewrite retroactively. They are now behind the GA-pinned target and need a driver/IMEX bump to `580.173.10` plus a re-validation pass (health checks, `dcgmi diag`, partner diag) before being considered GA-compliant. Tracked in §26.

## 0b. Full GA Release Notes PDF Reviewed — 2026-09-14

Everything up to this point in §0a was reconstructed from individual release-notes page images. The full PDF (`RN-11874-001_2.0.0GA_P4059_MAXQ__15.pdf`) surfaced several things those page crops didn't show — some resolve open threads from earlier in this session, some are new findings.

**⚠️ Critical, rack-wide, not yet actioned anywhere:** *"In release 2.0.0GA NVLink Recovery remains enabled by default. To ensure proper functionality and system stability, you must upgrade **all** components in the rack to release 1.0.5 or later, including compute nodes and NVSwitch. Failure to upgrade the entire rack may lead to incompatibility issues and unexpected behavior during NVLink Recovery operations."* This isn't scoped to `carlonext` alone — it applies to every compute node **and every NVSwitch tray** in a rack. `rack08` (§25c, provisioned 2026-09-08 from `baseos-1029-doca341`) has not been checked against this requirement. Needs verification before `rack08` is considered anything more than a health-check pass — NVLink Recovery incompatibility across a partially-upgraded rack is exactly the kind of failure mode that wouldn't necessarily show up in the `[UP]`/health-check spot-checks already done.

**NVOnline IDs changed for GA — §0's ID reference table is now stale.** Table 1 in the full PDF shows GA reissued three IDs that RC4-era metadata used different numbers for:

| Component | RC4 ID (used throughout §0-§16) | GA ID |
|---|---|---|
| Compute Tray Firmware | `1160211` | **`1162802`** |
| GPU Drivers (GB200/GB300 NVL72) | `1160161` | **`1162850`** |
| Source of Truth Metadata File | `1160245` | **`1162808`** |

`1162808` is the direct GA-era replacement for the exact metadata file (`1160245`) this whole build's version matrix was originally reconciled against in §16. Not yet re-pulled or diffed against what's already documented in §0/§0a — worth doing if a fully authoritative single-source check is ever needed, though the page-by-page GA release notes review already covers the same ground for the values actually in use on this host. Switch Tray Firmware (`1159830`), NVOS (`1159832`), and CX8/BF3 Firmware (`1159833`) remain on their RC4-era IDs even in the GA document — not reissued for GA, presumably unchanged content.

**GFM's actual target confirmed — resolves the open hedge from §0a/checklist v0.4.24.** The full PDF's "GB300 Switch Tray > NVOS" table gives:
```
NVOS Version: 25.02.4463
  SM:          2025.10.18
  NMX-C:       4.21.156
  GFM:         580.173.04
  NMX-T:       4.20.9
  Switch ASIC: 35_2014_5118
```
This directly confirms what §0a could only hedge on: `580.173.04` **is** a real, correct target — for the NVSwitch-tray-side Global Fabric Manager specifically, on its own independent release train tied to NVOS (`25.02.4463`), **not** tied to the compute-host driver version at all. It is a genuinely different thing from `carlonext`'s own inert `nvidia-fabricmanager` package (which does track the driver, now `580.173.10`, per §7g). Both numbers are real and both are now documented; checklist v0.4.27 adds `EXPECTED_GFM_NVOS="580.173.04"` alongside the existing `EXPECTED_FM`, and corrects the "Fabric Manager Version" N/A row's message, which was incorrectly still saying "not confirmed against GA."

**HMC baseline was incomplete — two components missing from §0a's table.** The full PDF's HMC section lists two rows the earlier page crop didn't include:
| Component | Version |
|---|---|
| SBIOS | `02.06.06` |
| FPGA | `1.66` |
Added to the running baseline for completeness. Neither has a corresponding checklist check yet — not yet wired up, tracked in §26.

**Entirely new baseline: GB300 Switch Tray firmware.** Not applicable to `carlonext` today (single un-racked L10 compute tray, no switch tray present), but now documented for whenever this unit or any other joins a rack:

| Section | Component | Version |
|---|---|---|
| NVOS | (see GFM block above) | `25.02.4463` |
| Switch BMC+FPGA+EROT bundle | EROT | `01.04.0055.0000_n04` (same EROT version as the compute-tray HMC/BMC — consistent across the whole rack) |
| Switch BMC+FPGA+EROT bundle | BMC | `88.0002.1984` (switch tray's own BMC — different numbering scheme entirely from the compute-tray HMC's `GB200Nvl-26.07-1`, different board) |
| Switch BMC+FPGA+EROT bundle | FPGA | `0.24` |
| Switch SBIOS+EROT bundle | EROT | `01.04.0055.0000_n04` |
| Switch SBIOS+EROT bundle | SBIOS | `0ACTV_01.01.030` |
| Switch CPLD bundle | CPLD1/2/3 | `CPLD000420_REV0300` / `CPLD000419_REV0500` / `CPLD000418_REV0300` |
| Switch CPLD bundle | FUI | `FUI000493` |

**Resolves the `flint`/`mstflint` tooling mystery from §10a.** §10a flagged finding two apparently-different MFT tool generations installed side by side (`flint` worked with plain PCI addresses, `mstflint`/`mstfwreset` didn't) as a minor, un-investigated finding. The full PDF's Table 9 explains it: **`MFT Tools` (`4.36.0-147`, Host Software Components table) and `MSTflint` (`v4.36.0-1`, Table 9) are two separate, distinctly-versioned components in NVIDIA's own release** — not a drift or accidental double-install on this host. Not a bug; closed.

**DCGM target now known.** Table 9: `DCGM 4.6.0` (NVOnline `1139880`). The checklist's `EXPECTED_DCGM` had been `"3.3"` since v0.1.0 — an unsourced placeholder, never actually verified against anything. Corrected to `4.6.0` in checklist v0.4.27. Relevant once the still-`MISSING` "DCGM Version"/`dcgmi diag` install step (§26) is finally reached.

**Kernel branch context for the currently-held `apt list --upgradable` decision (§7g).** Improvement #32 in the GA notes fixes a real PCIe/SMMU issue and states it's *"fixed in the `7.0.0-1015-nvidia-64k` kernel and later"* — the same `7.0.0` branch that showed up in §7g's `apt list --upgradable` review as a held, not-yet-taken major kernel jump (`6.17.0-1032.32` → `7.0.0-1019.19~24.04.2`). This isn't proof the jump is required right now (the specific PCIe surprise-link-down scenario the fix addresses hasn't been observed on this unit), but it confirms `7.0.0` is a real, intentional target with actual fixes behind it — not an arbitrary Ubuntu HWE bump to be reflexively ignored. Worth factoring in whenever the kernel-hold decision is revisited.

**Confirmed compatible, no action needed:** current kernel `6.17.0-1032-nvidia-64k` satisfies the documented minimum (`6.17.0-1014-nvidia-64k or later`, Table 11). Improvement #27's `6.17.0-1015-nvidia-64k` fix (NVLOOM/partition GPU-removal crash) is also covered, since `1032 > 1015`.

**Noted for awareness, not yet relevant to this L10 host:** Known Issue #9 (FPGA may permanently assert power brake after a secondary-module OVERT fault, workaround: AC power cycle) and #10 (BMC ERoT serial number occasionally fails to populate in Redfish, <0.5%, workaround: graceful BMC restart) — both plausible future troubleshooting context given this unit's BMC/EROT work in §0a/§10a, not observed here yet.

**Follow-up, same session — a real drift found, and a real bug fixed.** Running checklist v0.4.27 surfaced `HGX_FW_FPGA_0/1: 1.60` with no comparison target (this HMC field wasn't wired up yet) and `FW_E1S_CPLD_0/1: 0b.04.02 (expected 0.22)` showing `CHECK`. Neither was right as-is:
- **FPGA drift is real.** `1.60` vs GA's HMC target `1.66` (this section's table above) — same shape as the already-known BMC/EROT staleness, not previously checked. Confirmed the correct target is the HMC's own FPGA field, *not* the physically separate NVSwitch-tray FPGA (`0.24`, this section's Switch Tray table) — this host has no switch tray, so that number was never applicable regardless of the naming coincidence.
- **The E1S CPLD comparison was an actual bug, not a missed check.** v0.4.24's case-match used a bare `*CPLD*` substring pattern, which caught `FW_E1S_CPLD_0/1` (the E1S NVMe drive-carrier board's own, unrelated CPLD) and compared it against the HGX baseboard CPLD's `0.22` target — two different components being measured against each other's spec, producing a false mismatch rather than a real finding.

Fixed in checklist v0.4.28: every Redfish component pattern (EROT/CPLD/FPGA/SMA/BMC) now anchors to the confirmed `HGX_FW_` prefix instead of loose substring matching, and `EXPECTED_HGX_FPGA_FW="1.66"` was added. `FW_E1S_CPLD_0/1` is now correctly excluded — no GA target exists for that component and none should be applied to it.

*Status: informational review complete. Three checklist corrections applied across v0.4.27-v0.4.28 (DCGM, GFM, FPGA/E1S-CPLD). NVLink Recovery rack-wide upgrade requirement flagged as the most operationally urgent item — not yet verified against `rack08`. Tracked in §26.*

---
**Status:** In progress — installation not yet complete

---

## 1. Base OS Install

- Ubuntu **24.04** installed on target (`carlonext`)

## 2. Root Account / SSH Access

```bash
sudo passwd root
sudo mkdir -p /root/.ssh
sudo cp ~/.ssh/authorized_keys /root/.ssh/
sudo chown -R root:root /root/.ssh
sudo chmod 700 /root/.ssh
sudo chmod 600 /root/.ssh/authorized_keys
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

**Notes:**
- Used `sed` instead of `nano` after hitting `Error opening terminal: unknown` (missing/unsupported `TERM` on the console session — `export TERM=xterm` or `apt install ncurses-term` are the interactive fixes; `sed` sidesteps it entirely and is scriptable).
- Open item: `PermitRootLogin yes` allows root password auth. Consider `prohibit-password` if this box will be reachable outside an isolated bring-up network.

## 3. Grace 64K-Page Kernel Swap

GB300's Grace CPU requires the 64KB-page HWE kernel rather than the stock 4KB-page generic Ubuntu kernel.

```bash
sudo DEBIAN_FRONTEND=noninteractive apt purge \
  linux-image-$(uname -r) linux-headers-$(uname -r) linux-modules-$(uname -r) -y
sudo apt update
sudo apt install linux-nvidia-64k-hwe-24.04 -y
# reboot
```

**Verification (post-reboot):**

| Check | Command | Result |
|---|---|---|
| Kernel version | `uname -r` | `6.17.0-1029-nvidia-64k` ✅ |
| Page size | `getconf PAGE_SIZE` | `65536` ✅ |
| Package installed | `dpkg -l \| grep linux-nvidia-64k` | `linux-nvidia-64k-hwe-24.04 6.17.0-1029.29 arm64` ✅ |

**Cleanup — leftover kernel packages (resolved):**

Initial state after driver bring-up prep showed both the new Grace kernel and stale generic-kernel packages installed simultaneously:

```
linux-image-6.17.0-1029-nvidia-64k   [installed,automatic]  <- in use, correct
linux-image-6.8.0-137-generic        [installed,automatic]  <- stale
linux-image-generic                  [installed,automatic]  <- stale (meta-package, re-pulled the generic kernel)
linux-image-nvidia-64k-hwe-24.04     [installed,automatic]  <- metapackage, correct
```

Cleanup performed:

```bash
sudo apt purge -y linux-image-6.8.0-137-generic linux-image-generic
sudo update-grub
```

Purge left an empty-directory warning (`rmdir: failed to remove '/lib/modules/6.8.0-137-generic': Directory not empty`). Investigated before removing manually — no DKMS installed, and `kernel/` contained only stock in-tree module directories (no third-party driver modules), so it was safe to clear:

```bash
sudo rm -rf /lib/modules/6.8.0-137-generic/
sudo apt purge -y linux-headers-6.8.0-137-generic   # removed dangling headers too
sudo apt autoremove -y                              # cleared remaining orphaned packages
```

**Final verification:**

| Check | Result |
|---|---|
| `dpkg -l \| grep linux-image` | Only `linux-image-6.17.0-1029-nvidia-64k` and `linux-image-nvidia-64k-hwe-24.04` remain ✅ |
| `ls /lib/modules/` | Only `6.17.0-1029-nvidia-64k` ✅ |

*Status: complete.*

## 4. Package Hold & Automatic-Update Hygiene

With the correct kernel in place, locked the version and disabled anything that could silently pull a newer kernel or run apt mid-install during the rest of the bring-up.

```bash
# Fix TERM for interactive tools (nano, watch, etc.) - console lacked it, hit
# "Error opening terminal: unknown" twice before adding this permanently
echo 'export TERM=xterm-256color' >> ~/.bashrc
source ~/.bashrc

# Hold the Grace kernel package(s) so apt upgrade can't move it mid-bring-up
sudo apt-mark hold \
  linux-nvidia-64k-hwe-24.04 \
  linux-image-nvidia-64k-hwe-24.04 \
  linux-headers-nvidia-64k-hwe-24.04

# Disable unattended-upgrades + apt timers - a background unattended-upgrade
# (pid 3875) was holding the dpkg lock and blocked the hold command above
sudo systemctl stop unattended-upgrades
sudo systemctl disable unattended-upgrades
sudo systemctl stop apt-daily.timer apt-daily-upgrade.timer
sudo systemctl disable apt-daily.timer apt-daily-upgrade.timer
```

**Verification:**

| Check | Result |
|---|---|
| `apt-mark showhold` | `linux-nvidia-64k-hwe-24.04`, `linux-image-nvidia-64k-hwe-24.04`, `linux-headers-nvidia-64k-hwe-24.04` ✅ |
| `unattended-upgrades` service | stopped + disabled ✅ |
| `apt-daily.timer` / `apt-daily-upgrade.timer` | stopped + disabled ✅ |

**Note for later:** re-enable `unattended-upgrades` and the apt timers if this image is handed off for production use with automatic security updates desired. For the reference bring-up itself, keeping them off avoids apt racing the driver/CUDA/Fabric Manager installs.

*Status: complete.*

## 5. Kernel Build Packages

Per MNNVL Bring-Up Guide Release 1.15, §3.3.3.4.1 — required before the NVIDIA driver install since DKMS needs a build toolchain to compile kernel modules against `6.17.0-1029-nvidia-64k`.

```bash
sudo apt update -y && sudo apt install -y gcc dkms make
```

Pulled in the full build-essential chain (`gcc-13`, `binutils`, `libgcc-13-dev`, `libstdc++-13-dev`, `dpkg-dev`, `fakeroot`, etc.) as dependencies.

*Status: complete.*

## 6. DOCA Host Install (BlueField-3 / Networking Drivers)

Per MNNVL Bring-Up Guide Release 1.15, §3.3.3.5 — installs DOCA host software for the ConnectX NICs / BlueField-3 DPUs on the compute tray.

**Required version: DOCA-Host `3.4.1-010000`** — GB/B-designated release package (see confirmation notes below), not the general public download page default.

**Open items / to verify before running:**
- [x] Confirm exact DOCA-Host version — **confirmed 3.4.1-010000** per Host Software Components matrix (§0)
- [x] Confirm exact `.deb` filename — **confirmed `doca-host_3.4.1-010000-26.04-ubuntu2404_arm64.deb`**, obtained directly from NVIDIA via the NVONLINE bug/support system.
  - Public DOCA downloads page (developer.nvidia.com/doca-downloads) and DOCA Archive were checked and do **not** list 3.4.1 — only up to 3.4.0 (April 2026) is publicly listed.
  - Likely explanation: DOCA 3.4.0 docs explicitly state that version is *"not intended for GB/B [Grace Blackwell] customers"* and that GB/B customers should use a *"designated release package"* for full compatibility/qualification/support alignment. `3.4.1-010000` appears to be that GB/B-designated build, distributed out-of-band via NVONLINE rather than the general public DOCA page.
- [ ] Confirm `doca-kernel-support` compatibility with the **non-stock** `nvidia-64k-hwe` Grace kernel — guide explicitly notes *"doca-kernel-support does not support customized or unofficial kernels"*; still need to verify the 64k-page HWE kernel is treated as officially supported by DOCA's tooling before running step 4
- [ ] `doca-extra` and `doca-all` version pins should be double-checked against 3.4.1-010000 compatibility once package list is visible

**Final command sequence (filename confirmed):**

```bash
# .deb obtained via NVONLINE, not public download page - place in working dir first
ls -la doca-host_3.4.1-010000-26.04-ubuntu2404_arm64.deb   # confirm file present

sudo dpkg -i doca-host_3.4.1-010000-26.04-ubuntu2404_arm64.deb
sudo apt-get update
sudo apt install -y doca-extra

rm -rf /tmp/DOCA*
sudo /opt/mellanox/doca/tools/doca-kernel-support
# generates e.g. /tmp/DOCA.<hash>/doca-kernel-repo-<ver>.deb - install it:
dpkg -i /tmp/DOCA.<hash>/doca-kernel-repo-<ver>.deb

cat <<'EOF' | sudo tee /etc/apt/preferences.d/doca-host-repository-pin-600
Package: *
Pin: release l=DOCA-HOST
Pin-Priority: 600
EOF

sudo apt update
sudo apt -y install doca-all
```

**Execution log:**

Steps 1–3 completed successfully:

```
pega@carlonext:~$ sudo dpkg -i doca-host_3.4.1-010000-26.04-ubuntu2404_arm64.deb
Setting up doca-host (3.4.1-010000-26.04-ubuntu2404) ...

pega@carlonext:~$ sudo apt-get update
# picked up local repo: /usr/share/doca-host-3.4.1-010000-26.04-ubuntu2404/repo

pega@carlonext:~$ sudo apt install -y doca-extra
# installed: doca-ofed-source 26.04.1.0.9-1, doca-extra 2604.0.14-1
```

`doca-extra` pulled in `doca-ofed-source` (26.04.1.0.9-1) as a dependency — this is the OFED source tree that `doca-kernel-support` (step 4) will build kernel modules from via DKMS.

**⚠️ Before running step 4 (`doca-kernel-support`):** this is the step flagged earlier as potentially incompatible with non-stock kernels per the guide's note. Recommend confirming with NVIDIA (NVONLINE channel already open) that the Grace `nvidia-64k-hwe` kernel is supported before proceeding, since a failed/partial DKMS build here could leave the kernel module state inconsistent.

**Kernel-compatibility note resolved:** `nvidia-64k-hwe` is the NVIDIA-provided/qualified kernel for Grace, not an ad-hoc custom build — treated as the correct target for `doca-kernel-support` (the guide's "customized/unofficial kernel" warning is aimed at non-NVIDIA-provided kernels). Proceeding with step 4.

**Step 4 execution:** `doca-kernel-support` ran successfully, confirming compatibility empirically — it built and packaged kernel modules directly against the running kernel:

```
doca-kernel-support: Creating repo in .../Modules/6.17.0-1029-nvidia-64k
doca-kernel-support: Built single package: doca-kernel-repo-26.04-1.0.9.0-6.17.0.1029.nvidia.64k_26.04.1.0.9.0_arm64.deb
```

Modules built: `mlnx-ofed-kernel`, `iser`, `isert`, `srp`, `mlnx-nfsrdma`, `mlnx-nvme`, `virtiofs`, `xpmem`, `kernel-mft`.

Installed the generated repo package:
```bash
sudo dpkg -i /tmp/DOCA.H5uA7GDPfZ/doca-kernel-repo-26.04-1.0.9.0-6.17.0.1029.nvidia.64k_26.04.1.0.9.0_arm64.deb
```

**Steps 5–6 execution:**

Note: proceeded directly to the apt-pin + `doca-all` install; the intermediate `doca-ofed-userspace` / `doca-kernel-6.17.0.1029.nvidia.64k` install suggested by the `doca-kernel-support` tool output was not run as a separate step — `doca-all` pulled in everything needed as part of its own dependency resolution (confirmed by the kernel modules being built/installed successfully during the `doca-all` run below).

```bash
cat <<'EOF' | sudo tee /etc/apt/preferences.d/doca-host-repository-pin-600
Package: *
Pin: release l=DOCA-HOST
Pin-Priority: 600
EOF

sudo apt update
sudo apt -y install doca-all
```

Full `doca-all` install completed successfully. **153 new packages, 2 upgraded, 1 removed** (`sosreport` → `doca-sosreport`). Key confirmations:

- `doca-runtime`, `doca-devel`, `doca-all` all resolved to **3.4.1-010000** — matches target exactly
- DKMS modules (`mlnx-ofed-kernel`, `iser`, `isert`, `srp`, `xpmem`, `kernel-mft`) all built successfully against `6.17.0-1029-nvidia-64k`, installed to `/lib/modules/6.17.0-1029-nvidia-64k/updates/dkms/`
- No build failures anywhere in the sequence

**Open follow-ups (not blocking, but noted):**
- [ ] `rshim` service installed but not yet enabled/started — needed for BlueField-3 host↔DPU management interface. Install output explicitly recommends:
  ```bash
  sudo systemctl daemon-reload
  sudo systemctl enable rshim
  sudo systemctl start rshim
  ```
- [ ] `ubuntu-server` metapackage dependency on stock `sosreport` was overridden by `doca-sosreport` — low risk, but note in case anything later assumes the stock package name
- [ ] BF3 firmware version (`32.49.1118` target) not yet verified — worth checking once `rshim`/`mst` tooling is up

*Status: DOCA-Host / BlueField-3 driver stack complete.*

## 6a. ConnectX Firmware Update (§3.3.3.5.2 / .5.3)

Guide explicitly states MFT and firmware updates are bundled with DOCA-HOST, and the manual MFT install steps (§3.3.3.5.2 steps 1–2: `tar -xvf mft-*.tgz`, `install.sh`) only apply if DOCA-HOST was *not* installed. Since `doca-all` already pulled in the full MFT stack (`mft`, `mft-mlx5`, `mft-nvredfish`, `kernel-mft-dkms` — all `4.36.0-147`, matching §0 matrix), those steps are **skipped as redundant**.

Still relevant — device discovery + actual firmware flash (not an install step, just using the MFT tooling already present):

```bash
mst start
mst status -v          # confirmed: 4x ConnectX-8, see §6b for PCI IDs

# quick PSID sanity check - all 4 expected ST0 per diag confirmation
sudo flint -d 0000:03:00.0 q | grep -i psid
sudo flint -d 0002:03:00.0 q | grep -i psid
sudo flint -d 0010:03:00.0 q | grep -i psid
sudo flint -d 0012:03:00.0 q | grep -i psid

# flash all 4 cards with ST0_Ax firmware (function .0 only; .1 shares same flash)
FW=/fwupd/CX8_BF3_DOCA_MFT/ConnectX-8/fw-ConnectX8-rel-40_49_1118-900-9X86E-00CX-ST0_Ax-UEFI-14.42.15-FlexBoot-3.9.101.signed.bin

sudo flint -d 0000:03:00.0 -i "$FW" burn
sudo flint -d 0002:03:00.0 -i "$FW" burn
sudo flint -d 0010:03:00.0 -i "$FW" burn
sudo flint -d 0012:03:00.0 -i "$FW" burn

sudo mst stop

# ConnectX-8 acts as a PCIe switch - requires full reboot (not mlxfwreset)
sudo reboot
```

**Open items:**
- [x] Firmware source identified — NVOnline ID **1159833** (CX8 and BF3 Firmware, Drivers, and Tools, GB300 NVL72 2.0.0RC4). Same ID likely covers both ConnectX-8 and BlueField-3 firmware.
- [ ] Download the actual `.bin` from NVOnline 1159833 and confirm exact filename/PSID match for the 4x ConnectX-8 adapters found via `mst status` (see §6b)
- [ ] Confirm ConnectX adapter generation — **confirmed ConnectX-8** via `mst status -v` (see §6b), so firmware update path is: flash all 4 cards → `mst stop` → full `reboot` (not `mlxfwreset`)

**Firmware files staged (production-line diag folder convention):**

```
/fwupd/CX8_BF3_DOCA_MFT/ConnectX-8/fw-ConnectX8-rel-40_49_1118-900-9X86E-00CX-ST0_Ax-UEFI-14.42.15-FlexBoot-3.9.101.signed.bin
/fwupd/CX8_BF3_DOCA_MFT/ConnectX-8/fw-ConnectX8-rel-40_49_1118-900-9X86E-00CX-SP0_Ax-UEFI-14.42.15-FlexBoot-3.9.101.signed.bin
```

Sourced from NVOnline 1159833. Two files, differing by PSID suffix (`ST0_Ax` vs `SP0_Ax`) — different ConnectX-8 board variant/OPN.

**Confirmed by diag team: use `ST0_Ax` for this build.** Both files kept staged in the folder per diag's production-line convention (future variant support), but only `ST0_Ax` is used for this L10 layout's 4x ConnectX-8 cards.

**Before flashing — quick PSID sanity check (all 4 cards expected ST0):**

```bash
sudo flint -d 0000:03:00.0 q | grep -i psid
sudo flint -d 0002:03:00.0 q | grep -i psid
sudo flint -d 0010:03:00.0 q | grep -i psid
sudo flint -d 0012:03:00.0 q | grep -i psid
```

*Status: firmware variant confirmed (ST0). Pending PSID sanity check + burn.*

**PSID sanity check result:** all 4 cards report identical PSID `MT_0000001513` — confirms uniform board variant across all four ConnectX-8 adapters, consistent with diag's guidance to use a single `ST0_Ax` file for all of them. No mixed-variant risk.

*Status: PSID confirmed uniform. Ready to burn.*

**Note: `flint ... burn` is a production-line step, not executed during this L10 reference bring-up.** This section documents the staged firmware, confirmed PSID match, and the exact command sequence for the production line's diag/flashing process to consume — the burn itself is out of scope for this build session.

*Status: firmware staged and verified, burn commands documented for production line. Executed as a bare-metal validation pass in §10 (not a production-line flash) — confirmed 40.49.1118 on all 4 cards.*

**File placement verified on disk:**

```
pega@carlonext:~$ ll /fwupd/CX8_BF3_DOCA_MFT/ConnectX-8
-rw-r--r-- 1 root root 67108864 Aug  7 01:52 fw-ConnectX8-rel-40_49_1118-900-9X86E-00CX-SP0_Ax-UEFI-14.42.15-FlexBoot-3.9.101.signed.bin
-rw-r--r-- 1 root root 67108864 Aug  7 01:51 fw-ConnectX8-rel-40_49_1118-900-9X86E-00CX-ST0_Ax-UEFI-14.42.15-FlexBoot-3.9.101.signed.bin
```

Both files present, matched size (64 MB each), root-owned, correct diag-convention path.

*Status: §6a complete — ConnectX-8 firmware staged and verified for production-line handoff.*

## 6b. Adapter Topology (`mst status -v`)

```bash
sudo mst start
sudo mst status -v
```

Discovered topology:

**4x ConnectX-8 adapters** (dual-port each, confirmed `ConnectX8(rev:0)`):

| Card | PCI ID (function 0) | Ports (mlx5 / net) |
|---|---|---|
| 1 | `0000:03:00.0` | mlx5_0 (`net-enp3s0f0np0`) / mlx5_1 (`net-enp3s0f1np1`) |
| 2 | `0002:03:00.0` | mlx5_2 (`net-enP2p3s0f0np0`) / mlx5_3 (`net-enP2p3s0f1np1`) |
| 3 | `0010:03:00.0` | mlx5_4 (`net-enP16p3s0f0np0`) / mlx5_5 (`net-enP16p3s0f1np1`) |
| 4 | `0012:03:00.0` | mlx5_6 (`net-enP18p3s0f0np0`) / mlx5_7 (`net-enP18p3s0f1np1`) |

**1x BlueField-3 DPU** (dual-port), `BlueField3(rev:1)` at `0016:01:00.0` (mlx5_8) / `.1` (mlx5_9) — follows separate §3.3.3.5.3 BFB flow, not the ConnectX flint flow.

**8x `GB100(rev:0)` entries** at PCI domains `0008`, `0009`, `0018`, `0019` — no RDMA/NET/VFIO shown, PCI config interfaces only. ~~Not yet identified~~ **Resolved in §7:** these are the 4x GB300 Max-Q GPUs' PCI config endpoints, confirmed once `nvidia-smi` came online post-driver-install and reported matching PCI addresses.

*Status: topology mapped. GB100 entries still unidentified (informational, not blocking).*

## 6c. BlueField-3 Firmware (§3.3.3.5.3)

Same NVOnline ID (1159833) also provides the BF3 bundle. Staged per diag convention:

```
pega@carlonext:~$ ll /fwupd/CX8_BF3_DOCA_MFT/BlueField-3/
-rw-r--r-- 1 root root 712789448 Aug  7 01:58 bf-fwbundle-3.4.1-11_26.04-prod.bfb
```

Single `.bfb` bundle (~680 MB, `prod` build) — version `3.4.1-11_26.04` tracks the same DOCA_Host `3.4.1` / Ubuntu-companion `26.04` build tag seen throughout this install.

**Naming discrepancy investigated — resolved (design-based explanation):**

Full NVOnline 1159833 tarball contents include **two** BF3 `.bfb` bundles, not one:

| File | Size | Contents |
|---|---|---|
| `bf-bundle-3.4.1-11_26.04_ubuntu-22.04_prod.bfb` | 1.4 GB | OS+firmware — but tagged **Ubuntu 22.04** |
| `bf-fwbundle-3.4.1-11_26.04-prod.bfb` (staged) | 712.8 MB | Firmware-only, no OS |

**Leading explanation: BlueField-3 is configured for NIC mode in this design**, not full DPU/embedded-CPU mode. In NIC mode the BF3's Arm cores don't run a customer-facing OS, so the OS+firmware bundle (which would install a full DPU-side Linux) is the wrong artifact for this deployment regardless of Ubuntu version — the firmware-only bundle is architecturally correct, not a workaround. (The earlier-considered Ubuntu 22.04-vs-24.04 host mismatch is secondary/moot under this explanation, since no DPU-side OS is in use.)

**Action:** confirming directly with diag that BF3 is running NIC mode for this design, to close this out with certainty.

Actual `bfb-install` execution is a production-line step, out of scope for this L10 reference bring-up session. This section documents staging only.

*Status: BF3 firmware staged (firmware-only bundle, correct per diag). Leading explanation: NIC-mode design; final confirmation with diag still pending — flashed successfully in §10 as a bare-metal validation pass (confirmed 32.49.1118 via `ibstat mlx5_8`), but that confirms the firmware-only bundle installs and runs correctly, not that the NIC-mode explanation itself is diag-confirmed.*

## 7. NVIDIA GPU Driver + IMEX (§3.3.3.5.4)

Per NVOnline 1160161 (GPU Drivers for GB200/GB300 NVL72 2.0.0RC4). `.run` file method used (not APT — guide warns not to mix).

```bash
sudo sh ./NVIDIA-Linux-aarch64-580.173.02.run --dkms -q -s -m=kernel-open
sudo sh ./nvidia-imex-aarch64-580.173.02.run
```

**Driver install:** completed cleanly. Two benign warnings (X library path guess, missing Vulkan ICD loader) — both irrelevant on a headless GB300 compute node.

**`nvidia-smi` confirms — first GPU visibility in this build:**
- Driver `580.173.02` — exact match to §0 target
- CUDA `13.0` runtime reported (relevant for upcoming CUDA toolkit step)
- **4x NVIDIA GB300 Max-Q GPUs detected**, 284,208 MiB (~278 GB) each
- PCI locations: `0008:06:00.0`, `0009:06:00.0`, `0018:06:00.0`, `0019:06:00.0`
- All healthy: ~31-32°C, 176-181W/1200W cap, 0% util, no running processes

**Mystery resolved:** these 4 GPU PCI addresses are the exact same domains (`0008`, `0009`, `0018`, `0019`) flagged as unidentified `GB100(rev:0)` entries in §6b's `mst status -v` output. Confirmed: those were the GPUs' PCI config endpoints as enumerated by MST, not a separate NVLink/BMC component as speculated earlier.

**IMEX install:** completed. Config staged at `/etc/nvidia-imex/config.cfg`.

```bash
sudo systemctl enable nvidia-imex
sudo systemctl start nvidia-imex
sudo systemctl status nvidia-imex --no-pager
```

Service enabled and started, exits cleanly (`status=0/SUCCESS`, "Deactivated successfully") to `inactive (dead)`. **This is expected at L10** — IMEX is a multi-node (MNNVL) fabric service; with no peer nodes present in the NVLink domain yet (single unit, not racked), it correctly finds nothing to exchange and exits rather than staying resident. Expected to become persistently active once racked at L11+ with real NVLink domain peers.

*Status: driver + IMEX complete. §7 done.*

## 7a. Configure NVIDIA Packages (§3.3.3.6)

Applies to both `.run` and APT install methods.

```bash
# 3.3.3.6.1 - remove unused KMS config file (may not exist depending on install path - harmless if so)
sudo rm /etc/modprobe.d/nvidia-graphics-drivers-kms.conf

# 3.3.3.6.2 - enable profiling for all users
echo 'options nvidia NVreg_RestrictProfilingToAdminUsers=0' | sudo tee /etc/modprobe.d/nvprofiling.conf

# 3.3.3.6.3 - enable IMEX control channel
echo 'options nvidia NVreg_CreateImexChannel0=1' | sudo tee /etc/modprobe.d/nvidia.conf

# rebuild initramfs to pick up modprobe changes (Ubuntu)
sudo update-initramfs -u -k all
```

**§3.3.3.6.4 Configure IMEX Peers — deliberately deferred, not skipped by oversight.** This step creates `/etc/nvidia-imex/nodes_config.cfg` with management-Ethernet IPs of all cluster nodes. Same reasoning as IMEX service state in §7: this is single-unit L10, not yet racked with NVLink domain peers, so there are no peer node IPs to configure yet. Revisit once at L11+/rack integration with real peer addresses.

*Status: 6.1–6.3 ready to execute. 6.4 deferred to rack-level integration.*

**Execution:**

```
pega@carlonext:~$ echo 'options nvidia NVreg_RestrictProfilingToAdminUsers=0' | sudo tee /etc/modprobe.d/nvprofiling.conf
pega@carlonext:~$ echo 'options nvidia NVreg_CreateImexChannel0=1' | sudo tee /etc/modprobe.d/nvidia.conf
pega@carlonext:~$ sudo update-initramfs -u -k all
update-initramfs: Generating /boot/initrd.img-6.17.0-1029-nvidia-64k
```

`nvidia-graphics-drivers-kms.conf` (step 6.1) was never present on this system — `rm` step had nothing to clean up, not an error. `nvprofiling.conf` and `nvidia.conf` both created, initramfs regenerated against the correct kernel.

**Note on `NVreg_RestrictProfilingToAdminUsers=0`:** relaxes GPU performance-counter access from admin-only to all users, so profiling tools (Nsight, CUPTI, `nvprof`) work without sudo. This exists as a restriction by default because perf counters can act as a timing/utilization side-channel between mutually-untrusted tenants sharing a GPU. Appropriate here since this is a single-tenant reference/dev build; worth revisiting if this image is ever deployed in a genuinely multi-tenant context downstream.

*Status: §7a (6.1–6.3) complete. 6.4 deferred per above.*

## 7b. Enable the NVIDIA Persistence Daemon (§3.3.3.6.5)

**Step 1 — unit file check:** `/etc/systemd/system/nvidia-persistenced.service` did **not** exist prior to this step — confirms the `.run` driver installer (580.173.02) does not ship this unit file by default on this build. Created manually per guide §3.3.3.6.5:

```bash
sudo tee /etc/systemd/system/nvidia-persistenced.service > /dev/null <<'EOF'
[Unit]
Description=NVIDIA Persistence Daemon
Wants=syslog.target

[Service]
Type=forking
PIDFile=/var/run/nvidia-persistenced/nvidia-persistenced.pid
Restart=always
ExecStart=/usr/bin/nvidia-persistenced --verbose
ExecStopPost=/bin/rm -rf /var/run/nvidia-persistenced

[Install]
WantedBy=multi-user.target
EOF
```

**Step 2 — enable + start:**

```bash
sudo systemctl enable nvidia-persistenced.service
sudo systemctl start nvidia-persistenced.service
```

Result: `active (running)`, PID 199655, all 4 GPUs registered and persistence-enabled per journal (`0009:06:00.0`, `0018:06:00.0`, `0019:06:00.0` visible in `status` tail; full set confirmed below).

**Verification — all 4 GPUs:**

```
pega@carlonext:~$ nvidia-smi --query-gpu=index,pci.bus_id,persistence_mode --format=csv,noheader
0, 00000008:06:00.0, Enabled
1, 00000009:06:00.0, Enabled
2, 00000018:06:00.0, Enabled
3, 00000019:06:00.0, Enabled
```

*Status: complete. §3.3.3.6.5 done.*

## 7c. Enable the IMEX Daemon (§3.3.3.6.6) — Confirmation Only

Already enabled + started in §7 as part of the driver/IMEX `.run` install. This step in the guide is a re-run of the same enable command, so treated as a confirmation pass rather than new work:

```
pega@carlonext:~$ systemctl is-enabled nvidia-imex.service
enabled
pega@carlonext:~$ systemctl status nvidia-imex.service --no-pager
○ nvidia-imex.service - NVIDIA IMEX service
     Loaded: loaded (/usr/lib/systemd/system/nvidia-imex.service; enabled; preset: enabled)
     Active: inactive (dead) since Fri 2026-08-07 03:21:45 UTC; 3h 45min ago
        CPU: 5ms
Aug 07 03:21:45 carlonext systemd[1]: Starting nvidia-imex.service - NVIDIA IMEX service...
Aug 07 03:21:45 carlonext systemd[1]: nvidia-imex.service: Deactivated successfully.
Aug 07 03:21:45 carlonext systemd[1]: Started nvidia-imex.service - NVIDIA IMEX service.
```

`enabled` + clean `inactive (dead)` exit, consistent with §7 — expected at L10 with no NVLink domain peers. No action required.

*Status: confirmed, no action needed — see §7. §3.3.3.6.6 done.*

## 7d. Extended GPU Memory (§3.3.3.6.7) — Deferred to Partner Diag Prep

Guide note: only required for partner diagnostics. Originally logged as skipped outright (no partner-diagnostics package present at that point in the build). Superseded — NV L10 partner diag is now in scope for this unit, so this step is folded into that upcoming work rather than tracked as a separate, closed-out decision here.

*Status: deferred — see partner diag prep (§18) rather than treated as resolved/skipped.*

## 7e. Reboot the Compute Tray (§3.3.3.6.8)

```bash
sudo reboot
```

**Post-reboot verification:**

```
pega@carlonext:~$ nvidia-smi --query-gpu=index,persistence_mode --format=csv,noheader
0, Enabled
1, Enabled
2, Enabled
3, Enabled
pega@carlonext:~$ systemctl is-active nvidia-persistenced nvidia-imex
active
inactive
pega@carlonext:~$ uname -r
6.17.0-1029-nvidia-64k
```

- Persistence mode survived reboot, `Enabled` on all 4 GPUs ✅
- `nvidia-persistenced`: `active` ✅
- `nvidia-imex`: `inactive` — expected, same clean-exit behavior as §7 (no NVLink domain peers at L10, not a fault) ✅
- Kernel unchanged: `6.17.0-1029-nvidia-64k` ✅

**IMEX control channel device verified** (confirms `NVreg_CreateImexChannel0=1` from §7a took effect post-reboot):

```
pega@carlonext:~$ ll /dev/nvidia-caps-imex-channels/channel0
crw-rw-rw- 1 root root 503, 0 Aug  7 07:13 /dev/nvidia-caps-imex-channels/channel0
```

Device node present with correct major/minor — the modprobe config wasn't just written to disk, the kernel module actually applied it.

*Status: complete. §3.3.3.6 (Configure NVIDIA Packages, 6.1–6.8) fully done.*

## 7f. `nvidia-persistenced` Found Disabled — 2026-09-14

**Regression against §7e.** §7e confirmed `nvidia-persistenced` as `active` + surviving a reboot back on 2026-08-07. Found today, unprompted (not during a specific reinstall step logged elsewhere in this document), in a completely different state:

```
root@carlonext:~# systemctl status nvidia-persistenced.service
○ nvidia-persistenced.service - NVIDIA Persistence Daemon
     Loaded: loaded (/etc/systemd/system/nvidia-persistenced.service; disabled; preset: enabled)
     Active: inactive (dead)
```

Same unit file, same path as §7b's manually-authored one — not overwritten by a package-shipped unit. `preset: enabled` but actual state `disabled` means something explicitly removed the `multi-user.target.wants` symlink (or otherwise disabled it) sometime between 2026-08-07 and today; **not yet root-caused**. Candidates not yet checked: whether this correlates with any of the driver/DKMS work in §16a/§25, the BIOS/BMC update reboot in §20, or something outside this log entirely. Whether this happened as a side effect of driver-reinstall activity toward the pending `580.173.10` GA bump (§0a/§26) is also unconfirmed — asked, not answered as of this writing.

**Fix applied:**

```bash
sudo systemctl enable --now nvidia-persistenced.service
```

Result: `enabled` + `active (running)`, all 4 GPUs re-registered and persistence-enabled cleanly per journal (`0009:06:00.0`, `0018:06:00.0`, `0019:06:00.0`, plus the 4th).

**Open item:** root cause not established. Recurrence risk is real and unquantified — if whatever disabled it once (reboot, package action, manual command) happens again, especially during the still-pending `580.173.10` driver bump, it could regress silently, since the existing checklist only checks `nvidia-smi`'s runtime `persistence_mode` field (§0/checklist "Persistence Mode" row), not systemd enablement — see checklist v0.4.22 for the added `is-enabled` check this finding prompted. Re-verify this survives the *next* reboot (especially the one following the driver bump) before considering it closed.

*Status: fixed, not closed — root cause open, recurrence unconfirmed either way.*

## 7g. GA Driver Bump — `580.173.02` → `580.173.10` (2026-09-14)

**Executes the action item from §0a.** Full sequence, in order, on `carlonext`.

**Step 1 — uninstall old driver:**
```bash
sudo sh ./NVIDIA-Linux-aarch64-580.173.02.run --uninstall
```
Verified thorough before proceeding: `dkms status` showed `nvidia/580.173.02` fully deregistered (all other DKMS modules — `mlnx-ofed-kernel`, `iser`/`isert`/`srp`, `kernel-mft-dkms`, `xpmem` — untouched, all still against `6.17.0-1032-nvidia-64k`); `nvidia-smi` binary gone; no orphaned `/usr/src/nvidia-*` source tree. `nvidia_cspmu`/`arm_cspmu_module` remained loaded post-uninstall — checked and confirmed **unrelated**: `modinfo` shows `intree: Y`, `dpkg -S` traces it to `linux-modules-6.17.0-1032-nvidia-64k` (an in-tree ARM CoreSight PMU module, not shipped by the GPU driver package at all). Correctly left alone.

One side effect caught, not assumed: `nvidia-persistenced` went into a restart-failure loop (`status=203/EXEC`, "Start request repeated too quickly") once its binary disappeared — the hand-authored unit from §7b stayed `enabled` and kept retrying. Silenced with `sudo systemctl stop nvidia-persistenced` until the new binary was back. Second time this session `nvidia-persistenced` has needed a manual save (see §7f) — different trigger, same daemon.

**Step 2 — old `nvidia-fabricmanager`/`nvidia-imex` removed first (separately, before this step's install — see below for why that mattered).**

**Real finding, not just cleanup: `nvidia-imex` was `dpkg`-tracked (`580.173.02-1ubuntu1`) on `carlonext`, contradicting §7's documented `.run`-based install.** `dkms status`/`dpkg -l` pre-removal both confirmed this live. §25 already documented that `nvidia-driver-580-open`/`nvidia-open-580` pull bare `nvidia-imex` in as a dependency when installed from the local-repo package, which stayed installed and pinned from §25 through §22a — a plausible mechanism. **Checked directly and ruled out for this specific file:** `grep -iE 'apt|nvidia-driver|nvidia-open|cuda-drivers|state:.*latest|upgrade' CX8_BF3_config.yml` (the Ansible config present in `~pega`) returned zero matches — this file has nothing to do with it. The dependency-pull mechanism §25 documented remains a real, general risk of leaving that repo installed, but the specific trigger for *this* occurrence is genuinely unknown, not "probably this file." Root cause remains open.

Removal (both were plain `dpkg` packages by this point, no holds, dry-run confirmed no dependency casualties):
```bash
sudo apt purge --dry-run nvidia-fabricmanager nvidia-imex   # confirmed: only these 2 packages
sudo systemctl unmask nvidia-fabricmanager
sudo apt purge -y nvidia-fabricmanager
sudo systemctl disable --now nvidia-imex
sudo apt purge -y nvidia-imex
```
Two directories dpkg left behind (same conservative-non-empty-dir behavior as §22b): `/usr/share/nvidia` (from `nvidia-fabricmanager`) and `/etc/nvidia-imex` (from `nvidia-imex` — likely still holding the `config.cfg` staged in §7; contents not reviewed before this session ended, flagged for a `cat` check before deleting rather than assumed disposable).

**Step 3 — install new driver:**
```bash
sudo sh ./NVIDIA-Linux-aarch64-580.173.10.run --dkms -q -s -m=kernel-open
```
Clean install. `nvidia-smi` confirms `580.173.10` exactly, CUDA `13.0`, all 4 GPUs visible (`00000008/9/18/19:06:00.0`), 0 MiB used, no running processes. `dkms status` shows `nvidia/580.173.10` correctly registered against `6.17.0-1032-nvidia-64k`, every other module undisturbed. The install-time `libglvnd EGL vendor library` warning is benign — headless server, no display stack, same category of noise as the X11-stack side effect already documented in §25.

**Step 4 — IMEX reinstalled via its dedicated `.run`, deliberately NOT via the local-repo `.deb` this time** — restores §7's original method rather than repeating whatever produced the `dpkg`-tracked state found above:
```bash
sudo sh ./nvidia-imex-aarch64-580.173.10-internal.run
sudo systemctl enable --now nvidia-imex
```
Clean install ("IMEX installation completed"), enabled. **Note the `-internal` suffix on this filename** — absent from the `580.173.02` `.run` used in §7. Not yet confirmed whether this is simply how this GA build happens to be named on NVOnline or signals a distribution-channel distinction worth being aware of; flagged, not resolved.

**Step 5 — persistence daemon restored:**
```bash
sudo systemctl enable --now nvidia-persistenced
```
`active (running)`, all 4 GPUs re-registered, `persistence_mode: Enabled` across the board confirmed via `nvidia-smi`.

**Step 6 — Fabric Manager reinstalled from the `580.173.10` local-repo `.deb`, masked, held (same pattern as §25):**
```bash
sudo dpkg -i nvidia-driver-local-repo-ubuntu2404-580.173.10_1.0-1_arm64.deb
sudo cp /var/nvidia-driver-local-repo-ubuntu2404-580.173.10/nvidia-driver-local-180A0A68-keyring.gpg /usr/share/keyrings/
sudo apt update
sudo dpkg -i /var/nvidia-driver-local-repo-ubuntu2404-580.173.10/nvidia-fabricmanager_580.173.10-1ubuntu1_arm64.deb
sudo systemctl mask nvidia-fabricmanager
sudo apt-mark hold nvidia-fabricmanager
```
Same benign `Could not execute systemctl ... deb-systemd-invoke` postinst warning §25 already root-caused (real hardware, not chroot — cosmetic). Correctly masked (`→ /dev/null`) and held.

**Step 7 — repo removed deliberately, promptly, this time — not left installed for weeks like the `580.173.02` copy was:**
```bash
sudo apt purge -y nvidia-driver-local-repo-ubuntu2404-580.173.10
```
600 MB freed. Live for only the few minutes needed to extract the FM `.deb`, directly motivated by Step 2's finding — an unpinned local-repo source sitting around indefinitely is exactly the mechanism suspected of having converted `nvidia-imex` to `dpkg`-tracked the first time. The downloaded `.deb` itself (`~596M`, separate from the `/var` repo tree the `dpkg -i` unpacked it into) was also deleted from `~pega` afterward — already consumed, no longer needed.

**Step 8 — `apt list --upgradable` reviewed before considering this closed, per §26's standing item.** Found `libnvidia-nscq` unheld, showing an available "upgrade" to `615.71.09-2ubuntu1` — not a point release, a different major driver branch entirely. `nvidia-fabricmanager` and `nvidia-modprobe` show the identical `615.x` target, but both were already protected (FM just held in Step 6; `nvidia-modprobe` was already on the hold list from earlier in the build) — `libnvidia-nscq` was the one gap in an otherwise-working defense. Fixed:
```bash
sudo apt-mark hold libnvidia-nscq
```
Also surfaced, not yet acted on:
- `nvidia-modprobe` remains held at `580.173.02` — didn't drift to `615.x` (good), but is now one point-version behind the rest of the freshly-bumped stack. Needs a deliberate unhold → upgrade to `580.173.10-1ubuntu1` → re-hold cycle.
- `cuda-toolkit-13-0` and its family show `13.0.2-1` → `13.0.3-1` available — a genuine in-branch point release, unlike the others. §0's GA-pinned target is `13.0.2` specifically. **Decision not yet made:** stay pinned at `13.0.2`, or take `13.0.3`.
- The kernel HWE trio (`linux-headers/image/nvidia-64k-hwe-24.04`) shows a major-version jump (`6.17.0-1032.32` → `7.0.0-1019.19~24.04.2`) — already correctly held, cited here as a concrete real-world instance of exactly the risk §26's "review before ever running `apt upgrade`" item was written to prevent.

**Final verified state:** driver `580.173.10`, IMEX `580.173.10` (via `.run`, method restored), persistenced `enabled`+`active`, Fabric Manager `580.173.10` (masked, held), `libnvidia-nscq` now held, local-repo removed. CUDA toolkit untouched at `13.0.2` throughout (independent of the driver swap, as expected).

**Open items carried forward, not resolved this session:**
- ~~`CX8_BF3_config.yml` grep~~ — done, ruled out (see correction above). `nvidia-imex`'s conversion to `dpkg`-tracked remains genuinely unexplained.
- `/usr/share/nvidia` and `/etc/nvidia-imex` leftover directories — reviewed (2026-09-14): both are current, from this session's `580.173.10` reinstall (timestamps confirm), not stale cruft from the old install. `config.cfg` is the untouched factory default. No action needed, closed.
- ~~`nvidia-modprobe` version-alignment~~ — done: unheld, upgraded to `580.173.10-1ubuntu1` (confirmed via `nvidia-modprobe --version`), re-held.
- ~~`cuda-toolkit-13-0` → `13.0.3` decision~~ — **decided: stay pinned at `13.0.2`.** `13.0.3` is not part of the GA-qualified pairing at all — it comes from NVIDIA's general public CUDA apt repo (`developer.download.nvidia.com/.../ubuntu2404/sbsa`), which rolls forward independently of this specific GB300 MaxQ release train. GA's release notes specify `13.0.2` as the validated pairing with this driver/firmware stack; newer isn't the same as qualified-for-this-stack. `apt-mark hold cuda-toolkit-13-0` applied.
- IMEX `.run` filename's `-internal` suffix — still unexplained; not diagnosable from this session, would need an NVOnline/NVIDIA support-channel answer.
- §7f's `nvidia-persistenced` disablement root cause — still open; this session's uninstall/reinstall cycle is a plausible-but-unconfirmed trigger for *a* disablement, but doesn't explain the original 2026-08-07→2026-09-14 gap that predated any of this session's work.
- Also newly surfaced this session, see §10a: CX8/BF3 firmware found reverted to pre-§10 baseline, re-flashed and verified, root cause of the revert itself still unconfirmed (leading theory: process-level, possibly tarball/BCM-related, not a hardware rollback — SEL/dmesg came back clean).

*Status: driver bump complete and verified. Most threads closed this session; two genuinely unexplained items remain (see above) rather than papered over.*

## 7h. `nvidia-persistenced` Found Stopped Again — Partner Diag, Not a Regression — 2026-09-15/16

**Found, ahead of re-tarring the reference layout:** `nvidia-smi` showed `Persistence-M: Off` on all 4 GPUs. Unlike §7f's original mystery, this one has a clear, plausible cause and a clean shutdown signature — not treated as a repeat of the same unexplained regression.

```
Active: inactive (dead) since Mon 2026-09-14 11:29:06 UTC; 1 day 14h ago
Loaded: loaded (...; enabled; preset: enabled)
```
`enabled` confirms the systemd enablement itself was never touched — this is a *stop*, not a disable, and the journal shows a graceful one: `Received signal 15` → clean stop sequence → `Deactivated successfully`, both the daemon and its `ExecStopPost` cleanup exiting `status=0/SUCCESS`. That's the signature of something intentionally running `systemctl stop nvidia-persistenced`, not a crash. Timing lines up with partner diagnostics run the same day — GPU diag suites commonly stop this daemon first to get unmediated device access. Not confirmed against actual partner-diag logs/scripts, but plausible and distinct from §7f's original disablement (different mechanism — stopped vs. disabled — so not assumed to be the same root cause, or to retroactively explain it).

Fixed immediately (`systemctl start nvidia-persistenced`) — confirmed `active (running)`, all 4 GPUs re-registered, persistence re-enabled.

**Then: does this survive an actual reboot, not just a manual start?** Given how much of this session turned "should work per the config" into "didn't, actually" (§7f, §10a's firmware revert), this was tested directly rather than assumed from the unit file (`WantedBy=multi-user.target`, `Restart=always`, §7b):

```bash
sudo reboot
# post-reboot:
systemctl status nvidia-persistenced --no-pager
nvidia-smi --query-gpu=index,persistence_mode --format=csv,noheader
```

**Result — clean, first-attempt success, no restart-loop:**
```
Active: active (running) since Wed 2026-09-16 02:01:09 UTC; 2min 51s ago
```
Single clean start sequence in the journal (all 3 remaining GPUs registered/persistence-enabled in order, `Local RPC services initialized`, `Started nvidia-persistenced.service`) — no failed early attempts, no evidence of racing the NVIDIA kernel module despite the unit having no explicit `After=`/`Requires=` tying it to driver readiness. `nvidia-smi --query-gpu=index,persistence_mode`: all 4 GPUs `Enabled`, zero manual steps required.

**This genuinely closes out the "will a provisioned node boot with persistence on" question** — not just config-reviewed, actually boot-tested on this hardware/kernel/driver combination. Since the reboot didn't modify the unit file or its `enabled` state (both already correct and already captured in `maxQ20GA-1032-doca341-baseos.tgz`, tar'd before this test), the tarball doesn't need to be recaptured on account of this finding — this test validates what's already in it.

*Status: fixed and, more importantly, boot-verified. §7f's original disablement root cause remains separately open — this event's clean-stop signature doesn't retroactively explain it.*

## 8. CUDA Toolkit Install

Per corrected §0 matrix (`13.0.2`, confirmed via NVOnline 1160245 — see §0 note) and the public CUDA download selector (Linux / arm64-sbsa / Ubuntu 24.04 / deb (local)).

```bash
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/sbsa/cuda-ubuntu2404.pin
sudo mv cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600

wget https://developer.download.nvidia.com/compute/cuda/13.0.2/local_installers/cuda-repo-ubuntu2404-13-0-local_13.0.2-580.95.05-1_arm64.deb
sudo dpkg -i cuda-repo-ubuntu2404-13-0-local_13.0.2-580.95.05-1_arm64.deb
sudo cp /var/cuda-repo-ubuntu2404-13-0-local/cuda-*-keyring.gpg /usr/share/keyrings/

sudo apt-get update
sudo apt-get -y install cuda-toolkit-13-0
```

**Note on `.deb` filename:** local-repo package embeds `580.95.05` in its name — that's the driver build this CUDA local-installer package happens to be associated with upstream, not a driver it installs or requires. It does not touch the already-installed `580.173.02` driver; `cuda-toolkit-13-0` only pulls toolkit/library/tooling packages (confirmed by the package list — `cuda-cudart`, `libcublas`, `nsight-*`, `cuda-nvcc`, etc., no `nvidia-driver`/`nvidia-kernel-module` packages present).

**Install result:** `apt-get update` picked up the new local CUDA repo alongside the existing DOCA-Host and doca-kernel-support local repos with no conflicts. `cuda-toolkit-13-0 (13.0.2-1)` installed cleanly — 95 new packages, 0 removed, no errors. `update-alternatives` set `/usr/local/cuda` → `/usr/local/cuda-13.0`. No service restarts flagged as needed.

**Verification — deferred, not yet run.** `nvcc --version` and a post-install `nvidia-smi` check (confirm driver still reports `580.173.02` unchanged) still need to be run before this step is considered fully closed out.

*Status: toolkit installed successfully. Verification pending — run `nvcc --version` and `nvidia-smi` before marking §8 fully complete.*

## 9. Linux Kernel Tool Install List

Per internal "Installation - Linux kernel tool install list" slide. Two items needed disambiguation before install:

- **`mstvp`** — not a real package name; identified as a truncated/typo'd reference to `mstvpd` (Mellanox VPD-read tool), which ships bundled inside the `mstflint` package rather than as its own apt package. Installed `mstflint` only; `mstvpd` came along with it.
- **`mstflint`** — this is the open-source Ubuntu-repo package (distinct from NVIDIA's own MFT `mft`/`mft-mlx5`/`mft-nvredfish` 4.36.0-147 already installed via `doca-all` in §6). Both can coexist on disk, so before logging this complete, checked whether apt's `mstflint` (4.26.0) shadows the NVIDIA MFT `flint` binary (4.36.0-147) that §6a's PSID-check/burn commands depend on — **confirmed no shadowing**, `flint` on `PATH` still resolves to the correct `4.36.0-147` MFT build.

```bash
sudo apt install -y fio sysstat smartmontools numactl net-tools unzip \
  jq ipmitool nvme-cli expect stress-ng sshpass mstflint ifupdown
```

**Already present before this run** (no-op, previously installed): `sysstat` (12.6.1-2), `numactl` (2.0.18-1ubuntu0.24.04.1), `jq` (1.7.1-3ubuntu0.24.04.2). `gcc` and `make` (also on the slide's implied baseline) were already installed in §5 and not re-specified here.

**Newly installed (35 packages total incl. dependencies):** `fio`, `smartmontools`, `net-tools`, `unzip`, `ipmitool`, `nvme-cli`, `expect`, `stress-ng`, `sshpass`, `mstflint` — plus transitive deps (`freeipmi-common`, `openipmi`, `libglusterfs0`/`librados2`/`librbd1` stack pulled in by `fio`'s optional storage-backend support, etc.). No errors, no service restart required.

**`ifupdown` added, not on the original slide's list — Ubuntu 22.04 vs 24.04 difference:**
- **22.04:** Netplan is already the default renderer, but `ifupdown`/legacy compatibility bindings are commonly still present in the base image, so `/etc/network/interfaces` and `/etc/network/interfaces.d/*` are often still parsed if those bindings exist.
- **24.04 (this platform):** `ifupdown` has been fully removed from default installs — Netplan + `systemd-networkd` is the only supported path by default. Any file dropped into `/etc/network/interfaces.d/` is silently ignored by the kernel/systemd unless `ifupdown` is explicitly installed — hence adding it here rather than assuming it's present.

**Post-install verification:**

```
pega@carlonext:~$ which mstvpd
/usr/bin/mstvpd
pega@carlonext:~$ mstvpd -v
mstvpd 2.0.0, mstflint 4.26.0, Git SHA Hash: 9f7f49c
pega@carlonext:~$ which flint
/usr/bin/flint
pega@carlonext:~$ flint -v
flint, mft 4.36.0-147. Git SHA Hash: 7a24adf8c
```

`mstvpd` present via the new `mstflint` package. `flint` confirmed still resolving to the NVIDIA MFT build (4.36.0-147), not the apt-repo mstflint's own `flint` — §6a firmware workflow unaffected.

*Status: complete. §9 done.*

## 10. ConnectX-8 / BlueField-3 Firmware Flash — Bare-Metal Validation Pass

**Context:** §6a and §6c originally scoped the CX8 burn and BF3 flash as production-line-only steps, staged and documented but explicitly not executed during the L10 reference build. This section is a deliberate reversal of that scoping — **executed as a validation/practice pass on this bring-up unit prior to handing off the reference software layout**, to confirm the documented procedure is actually correct before it goes out as the standard path. Not a production-line flash of a shipping unit.

Firmware source: NVOnline 1159833 (see §0 / §6a), staged files unchanged from what was verified in §6a/§6c.

**Step 1 — Enable rshim** (open item from §6, required for BF3 flash):

```bash
sudo systemctl daemon-reload
sudo systemctl enable rshim
sudo systemctl start rshim
```

Result: `active`. `/dev/rshim0/{boot,console,misc,rshim}` present. `ip a` also showed `tmfifo_net0` as `UP,LOWER_UP` — confirms the rshim host↔DPU management tunnel is live.

**Step 2 — Burn ConnectX-8 firmware** (all 4 cards, ST0_Ax, PSID-confirmed uniform per §6a):

```bash
sudo mst start

FW=/fwupd/CX8_BF3_DOCA_MFT/ConnectX-8/fw-ConnectX8-rel-40_49_1118-900-9X86E-00CX-ST0_Ax-UEFI-14.42.15-FlexBoot-3.9.101.signed.bin

sudo flint -d 0000:03:00.0 -i "$FW" burn
sudo flint -d 0002:03:00.0 -i "$FW" burn
sudo flint -d 0010:03:00.0 -i "$FW" burn
sudo flint -d 0012:03:00.0 -i "$FW" burn

sudo mst stop
```

All 4 cards: `40.47.2526` → `40.49.1118`, `FSMST_INITIALIZE` / `Writing Boot image component` / `Restoring signature` all `OK`. No interactive burn confirmation prompt appeared on any card (worth noting for anyone reproducing this — not a skipped step, all four completed with `OK` status).

**Step 3 — Flash BlueField-3 firmware:**

```bash
sudo bfb-install --rshim rshim0 --bfb /fwupd/CX8_BF3_DOCA_MFT/BlueField-3/bf-fwbundle-3.4.1-11_26.04-prod.bfb
```

Result: BMC firmware updated to `26.04-8`, NIC (BF3) firmware updated to `32.49.1118`, DPU Golden Image and certificates updated, final status `DPU is ready`.

**Anomaly encountered:** `ERR[MISC]: NIC Firmware reset failed. Host power cycle is required`. This is a hard requirement, not a cosmetic warning — an in-band NIC firmware reset failed, and the tool explicitly calls for a **host power cycle**, not an OS-level `reboot`. A warm `sudo reboot` restarts the OS/kernel but does not de-energize the PCIe/NIC hardware, so it would not have been sufficient to load either the new CX8 boot image (Step 2) or the new BF3 NIC firmware.

Also observed during the second boot pass: `GET P-S:fail(3)` (BMC/Redfish power-state query failure). Not confirmed related to the NIC reset failure above — flagged for awareness, not diagnosed further, since the subsequent power cycle resolved the outstanding item regardless.

**Step 4 — DC power cycle via BMC** (in place of a plain OS reboot, per the reset-failure requirement above):

```bash
ipmitool chassis power status
ipmitool chassis power cycle
```

Host management NIC (`enP5p9s0`) went down for the cycle as expected (same power domain) — SSH session dropped and was reconnected once the host came back up.

**Step 5 — Post-power-cycle verification:**

```
pega@carlonext:~$ ibstat mlx5_5
CA 'mlx5_5'
        CA type: MT4131
        Firmware version: 40.49.1118
        Port 1:
                State: Down
                Physical state: Disabled
                Link layer: Ethernet
pega@carlonext:~$ ibstat mlx5_8
CA 'mlx5_8'
        CA type: MT41692
        Firmware version: 32.49.1118
        Port 1:
                State: Down
                Physical state: LinkUp
                SM lid: 0
                Link layer: InfiniBand
```

- CX8 (`mlx5_5`): firmware confirmed `40.49.1118` ✅
- BF3 (`mlx5_8`): firmware confirmed `32.49.1118` ✅ — matches `EXPECTED_BF3_FW` in §0/checklist script
- Both ports show `State: Down` — expected at this stage, not a fault: `mlx5_5` has no cable connected yet; `mlx5_8` is `Physical state: LinkUp` with `SM lid: 0`, i.e. physically up but no InfiniBand subnet manager present since this is a single un-racked L10 unit, not yet joined to a fabric.

*Status: complete. Firmware confirmed updated and correct on both CX8 and BF3. Validated as a practice pass ahead of reference hand-off — procedure in §6a/§6c confirmed correct, with the host-power-cycle requirement (vs. plain reboot) now captured for anyone following this as the reference path.*

## 10a. CX8/BF3 Firmware Found Reverted to Pre-§10 Baseline — 2026-09-14

**Discovered via the checklist script, not suspected first.** Running `gb300_l10_sw_checklist.sh` v0.4.23 during the §7g driver-bump work showed:
```
BF3 Firmware Version : FW Version:  32.47.2526   [CHECK]
CX8 Firmware Version : FW Version:  40.47.2526   [CHECK]
```
This is not a nearby-but-different version — it is **the exact pre-burn baseline §10 itself documented** ("`40.47.2526` → `40.49.1118`" for CX8; BF3's pre-flash value was `32.47.2526` per the same section). Confirmed independently via `flint -d <pci-addr> query` on all 5 devices (4× CX8, 1× BF3) using direct PCI-address syntax rather than `/dev/mst/*` paths (the latter failed to parse against this unit's installed `mstflint`/`mstfwreset` — a separate, minor tooling-version mismatch between `flint` and `mstflint`/`mstfwreset` on this host, not investigated further, noted here for anyone hitting the same parse error): all 4 CX8 ports at `40.47.2526`, BF3 at `32.47.2526`, both matching `FW Release Date: 12.1.2026` (pre-dating this entire bring-up).

**Ruled out before re-flashing, not assumed:**
- **Pending-activation theory (burn written but not yet loaded):** ruled out. `flint`/`mstflint` show a single `FW Version` with no distinct "Running" value on any device — if an unapplied newer image were sitting behind the running one, that would show as two separate version fields. `mstfwreset -d 0016:01:00.0 query` (BF3) confirmed no pending reset state either; `mstfwreset` against the CX8 ports failed with `ICMD_NOT_READY` (523) — a known ConnectX/BlueField capability difference in this interface, not evidence of anything.
- **PSID mismatch risk:** checked and genuinely relevant, but for the *GA release-notes-referenced* bundle only (`fw-ConnectX8-...-SPA_Ax-...MT_0000001228.fwpkg` — PSID `MT_0000001228`, while this hardware's actual CX8 PSID is `MT_0000001513`, confirmed via `flint query` on all 4 ports). **Not applicable to the file actually used for re-flashing** (see below) — §10's original burn used a different, `ST0_Ax`-suffixed file from `/fwupd/CX8_BF3_DOCA_MFT/`, already validated against this exact hardware's real PSID once before.
- **Hardware-level rollback/recovery mechanism:** checked via `ipmitool sel list`/`sel elist` (full history back to 2026-08-14) and `dmesg -T`. **Clean** — nothing but routine ACPI power-state transitions in the SEL, no CPLD/EROT/watchdog event, no reset flags; `dmesg` from the post-reflash boot shows only routine platform boot noise (`tegra-qspi ... device reset failed`, a known GICv3 firmware-bug log line typical of this platform) plus the expected `vfio-pci` reset that's a normal part of `bfb-install`'s DPU-mode transition. No evidence of a triggered hardware rollback.
- **Physical event on the unit:** asked directly — none recalled.

**Leading explanation (unconfirmed, not a hardware defect theory):** given the SEL/dmesg came back clean and no physical event is recalled, the most consistent explanation is a **process-level revert**, not a hardware-triggered one — most plausibly connected to the tarball-capture/`cm-create-image` work in §25, if `carlonext` or an equivalent captured/restored state was ever re-applied to this unit from a point predating §10's August flash. Not confirmed against actual BCM/tarball timestamps or logs — flagged as the leading theory, not treated as established fact.

**Also newly relevant:** the BMC/EROT staleness first found two sessions ago (`HGX_FW_BMC_0: GB200Nvl-25.09-2` vs GA's `26.07-1`; `HGX_FW_ERoT_*: 01.04.0031.0000_n04` vs GA's `01.04.0055.0000_n04`) was considered as a possible *shared* root cause (a platform-level recovery event affecting BMC/EROT and CX8/BF3 together) but the clean SEL doesn't support that either — these may simply be two independent instances of stale firmware on this unit rather than one unifying event. Not resolved either way.

**Re-flash — exact repeat of §10's procedure, same staged files:**
```bash
FW=/fwupd/CX8_BF3_DOCA_MFT/ConnectX-8/fw-ConnectX8-rel-40_49_1118-900-9X86E-00CX-ST0_Ax-UEFI-14.42.15-FlexBoot-3.9.101.signed.bin
sudo flint -d 0000:03:00.0 -i "$FW" burn
sudo flint -d 0002:03:00.0 -i "$FW" burn
sudo flint -d 0010:03:00.0 -i "$FW" burn
sudo flint -d 0012:03:00.0 -i "$FW" burn

sudo bfb-install --rshim rshim0 --bfb /fwupd/CX8_BF3_DOCA_MFT/BlueField-3/bf-fwbundle-3.4.1-11_26.04-prod.bfb
```
All 4 CX8 cards: `40.47.2526 → 40.49.1118`, identical `OK` sequence to §10. BF3: NIC firmware updated to `32.49.1118`, BMC to `26.04-8`. Same `NIC Firmware reset is not supported. Host power cycle is required` message as §10 — same correct response:
```bash
ipmitool chassis power cycle
```

**Post-cycle verification — confirmed at two independent layers, not just one tool's report:**
```
root@carlonext:~# ibstat mlx5_5
Firmware version: 40.49.1118
root@carlonext:~# ibstat mlx5_8
Firmware version: 32.49.1118
```
Cross-confirmed via kernel `dmesg`: `mlx5_core 0000:03:00.0: firmware version: 40.49.1118` (and identically for every other CX8/BF3 PCI function) — the driver itself sees the new firmware, not just userspace tooling reporting a cached value. Re-ran `gb300_l10_sw_checklist.sh` afterward: `BF3 Firmware Version`/`CX8 Firmware Version` both `OK` at `32.49.1118`/`40.49.1118`.

**Open item — recurrence risk not closed.** The leading explanation (a process-level revert, possibly tarball/BCM-related) is unconfirmed, and the checklist's firmware checks are what caught this, not proactive monitoring — if whatever caused this happens again (a future tarball recapture, a BCM resync, or genuinely something else undiagnosed), it could revert silently between checklist runs. Worth treating "verify BF3/CX8 firmware" as a standing pre-handoff/post-any-reimage step, not a one-time confirmation, until the actual mechanism is understood.

*Status: firmware corrected and verified at two independent layers (userspace `ibstat` + kernel `dmesg`). Root cause of the original revert not confirmed — leading theory documented, not established. Recurrence risk explicitly open.*

## 11. Ansible Install

```bash
apt install ansible-core
```

Installed `ansible-core` (2.16.3-0ubuntu2) and the full `ansible` metapackage (9.2.0+dfsg-0ubuntu5), 15 packages total, no errors. Installed ahead of the remaining bring-up tasks; not yet tied to a specific playbook or automation target — noted here for completeness rather than as a scoped bring-up step.

*Status: complete.*

## 12. CX8 / BF3 Ethernet Mode Configuration (Ansible)

**Context:** Prep for NV L10 partner diagnostics — both CX8 and BF3 need to be in Ethernet mode. Executed via `CX8_BF3_config.yml` (attached playbook), which uses `mlxconfig` to reset and reconfigure both device types.

**Playbook logic:**
- BF3: dynamically discovers its MST device path (`mt41692_pciconf*`), resets config, sets `LINK_TYPE_P1=2 LINK_TYPE_P2=2` (Ethernet on both ports), `INTERNAL_CPU_OFFLOAD_ENGINE=1`, and LLDP settings on both ports.
- CX8: dynamically discovers all MST device paths (`mt4131_pciconf*`), sets `LINK_TYPE_P1=2`, `NUM_OF_PLANES_P1=0`, `MODULE_SPLIT_M0` (per-range split config), `NUM_OF_PF=2`.

**Note — CX8 has no `LINK_TYPE_P2` set in the playbook, by design, not a gap:** each ConnectX-8 card exposes one physical port that is split into logical ports via `NUM_OF_PLANES_P1`/`MODULE_SPLIT_M0`, rather than having an independent physical P2 — confirmed by the person running this build, not something to "fix" to match BF3's both-ports pattern.

**Setup — inventory + become password:**

```bash
cat <<'EOF' > inventory.ini
[compute_nodes]
localhost ansible_connection=local
EOF
```

First run failed under the `pega` user (`become: true` requires non-interactive sudo, no password cached): `sudo: a password is required`. Re-ran from a root shell (`sudo -i`) instead of using `--ask-become-pass`.

**Run result:**

```
TASK [Start MST service] ... ok
TASK [Get BlueField-3 MST device name dynamically] ... ok
TASK [Reset and configure BlueField-3] ... changed
TASK [Dynamic search for CX8 MST devices] ... ok
TASK [Configure CX8 devices dynamically] ... changed (x8 — see note below)
PLAY RECAP: ok=5  changed=2  unreachable=0  failed=0
```

**Bug found — CX8 devices configured twice each:** the "Dynamic search for CX8 MST devices" task's regex (`mt4131_pciconf\d+`) matched both PCIe functions per card (`mt4131_pciconf0` *and* `mt4131_pciconf0.1`, etc. — confirmed via `mst status -v`, which lists each ConnectX-8 card as two separate lines, one per function). The regex doesn't exclude the `.N` function suffix, so each of the 4 physical cards was matched twice, and the `mlxconfig set` block ran twice per card (8 "changed" entries for 4 devices). Idempotent (no harm from running the same `set` twice), but should be fixed before this playbook is treated as the reference version — e.g. dedup with `| sort -u` or tighten the regex to exclude `.\d` suffixes.

**Applying the change — this took three attempts:**

1. `sudo reboot` (OS-level) — **insufficient.** Post-reboot, `mlxconfig -d /dev/mst/mt41692_pciconf0 q` showed the staged value (`LINK_TYPE_P1/P2 = ETH(2)`), but `ibstat mlx5_8` still reported live `Link layer: InfiniBand` — config written but not actually loaded by BF3's firmware.
2. `sudo mlxfwreset -d /dev/mst/mt41692_pciconf0 -y reset` — **stalled**, ran far longer than expected with no completion. Likely cause (not confirmed via `ps`/`dmesg` before cutting over): `rshim` was still active from §10 and may have held the device open, blocking `mlxfwreset`'s exclusive-access requirement. Worth checking `systemctl stop rshim` before `mlxfwreset` on BF3 in future runs.
3. `sudo ipmitool chassis power cycle` (DC power cycle via BMC) — **worked.** Same mechanism required for the firmware load in §10.

**Post-power-cycle verification:**

```
pega@carlonext:~$ ibstat mlx5_8
CA 'mlx5_8'
        Firmware version: 32.49.1118
        Port 1:
                State: Down
                Physical state: Disabled
                Link layer: Ethernet
```

`mst status -v` also confirms BF3's interface names flipped from `net-ibP22s22f0`/`net-ibP22s22f1` (InfiniBand naming) to `net-enP22s22f0np0`/`net-enP22s22f1np1` (Ethernet naming).

CX8 params confirmed applied on card 0 (representative check, all 4 cards ran identical `mlxconfig set`):

```
pega@carlonext:~$ sudo mlxconfig -d /dev/mst/mt4131_pciconf0 q | grep -iE 'num_of_pf|num_of_planes|module_split'
        NUM_OF_PF                                       2
        MODULE_SPLIT_M0                                 Array[0..15]
        NUM_OF_PLANES_P1                                0
        NUM_OF_PLANES_P2                                0
```

`NUM_OF_PF=2` and `NUM_OF_PLANES_P1=0` confirmed matching the playbook's staged values. CX8 was already Ethernet-mode by default (unlike BF3), so no link-layer flip was needed there — only the parameter values themselves needed confirming.

*Status: complete. Both BF3 and CX8 (all 4 cards) confirmed in Ethernet mode with target config applied, ready for NV L10 partner diagnostics. Open follow-up: fix the CX8 device-discovery regex duplicate-match bug before this playbook is used as the reference version.*

## 13. gb300_l10_sw_checklist.sh — First Full Run + Bugfixes

**Run 1 (as `pega`, no sudo):** `22 OK | 3 NEEDS REVIEW | 12 MISSING`. Several `MISSING` results were false negatives from lacking root — `BMC/BIOS`, `System Product Name`, `IOMMU Enabled`, `MFT Tools Version`, `BF3 Firmware Version` — `dmidecode`/`mst`/`flint` all silently fail without privilege.

**Run 2 (as root):** `26 OK | 2 NEEDS REVIEW | 9 MISSING`. Confirmed:
- `BMC/BIOS`: `00.56.02`
- `System Product Name`: `Carlo_Next MaxQ`
- `MFT Tools Version`: `4.36.0-147` — matches §0/§6a target
- `BF3 Firmware Version`: `32.49.1118` — matches §10's confirmed flash

**Remaining `MISSING` after root run — expected, matches known open work:** Fabric Manager Service/Version, DCGM Version, Docker/containerd/nvidia-container-toolkit/Default Runtime, `nvcc` (CUDA toolkit — see below).

**`NVSwitch Devices`: still `MISSING`** even as root. Not yet resolved either way — plausibly expected for a single un-racked L10 unit with no switch tray/fabric attached (same reasoning applied elsewhere in this log to IMEX/NVLink), but not confirmed. Flagged as open, not assumed benign.

**Two script bugs found and fixed (now v0.4.2):**

1. **`IOMMU Enabled` — false negative on this platform.** Script checked `dmesg | grep -m1 -i 'IOMMU enabled'`, an x86-style log string that Grace/ARM never emits (SMMU is enabled via ACPI IORT tables, not a boot-time log line). Investigated directly before concluding it was a script bug rather than a real gap:
   - `dmesg | grep -iE 'smmu|arm.*iommu'` → confirmed 27+ `arm-smmu-v3-pmcg` PMU instances registered across multiple PCIe root complexes (hardware present/probed, but PMCG alone doesn't prove translation is active)
   - `ls /sys/kernel/iommu_groups/ | wc -l` → **90** populated groups — definitive confirmation IOMMU/SMMU translation is genuinely active and enforcing isolation, not just probed.
   - Fixed: check now uses the `/sys/kernel/iommu_groups/` population count directly (architecture-agnostic) instead of a platform-specific log string.

2. **`CUDA Version (driver)` — invalid query field.** `nvidia-smi --query-gpu=cuda_version` returned `Field "cuda_version" is not a valid field to query.` on this driver/nvidia-smi build. Fixed: now parses `CUDA Version: X.Y` out of plain `nvidia-smi`'s header output instead of the `--query-gpu` field list.

**Not yet fixed — flagged for follow-up:**
- **`nvcc (CUDA toolkit)`: `MISSING`.** This is the deferred CUDA verification from §8 finally surfacing a real result: `nvcc` is not on `PATH`. Toolkit installed correctly (`update-alternatives` set `/usr/local/cuda` → `/usr/local/cuda-13.0` per §8), but `/usr/local/cuda/bin` was never added to `PATH`. Fix identified, not yet applied:
  ```bash
  echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
  ```
- **`MOFED Version` shows `CHECK`** — actual installed value `OFED-internal-26.04-1.0.9` vs. script's `EXPECTED_MOFED="24.10"`. Same stale-matrix pattern as the CUDA 12.8→13.0.2 correction in §0 — `24.10` was never verified against NVOnline 1160245 the way driver/CUDA/DOCA/MFT/BF3-FW were. **Resolved in §16.**

*Status: script bugs fixed (v0.4.2). Real findings (`nvcc` PATH, `EXPECTED_MOFED` staleness, `NVSwitch Devices`) still open, not yet resolved.*

## 14. nvcc PATH Fix (system-wide, for reference hand-off)

`nvcc` was MISSING in checklist runs — toolkit installed correctly (§8), but `/usr/local/cuda/bin` was never added to `PATH`. Used a system-wide `/etc/profile.d/` drop-in rather than `~/.bashrc`, since this build is meant for hand-off:

```bash
echo 'export PATH=/usr/local/cuda/bin:$PATH' | sudo tee /etc/profile.d/cuda.sh
sudo chmod 644 /etc/profile.d/cuda.sh
```

`ldconfig -p | grep cudart` confirmed runtime libs were already correctly registered, no extra fix needed there. Confirmed both via `nvcc --version` (`release 13.0, V13.0.88`, matching the installed toolkit) and a full checklist re-run (`nvcc` now `OK`, `29 OK | 1 CHECK | 7 MISSING`).

**Aside — checklist hang during active MODS session:** separately, `gb300_l10_sw_checklist.sh` was found to hang indefinitely if run while a MODS-related setup step from the partner diagnostics package was already active (MODS unloads/blacklists the `nvidia` driver for exclusive GPU access, and the checklist has no timeout on its checks). Not a defect — the checklist can't produce meaningful GPU results while the driver is deliberately out of the picture. Resolved once the MODS session cleared. Missing-timeout-on-checks noted as a real, separate script follow-up.

*Status: complete.*

## 15. nvcc PATH — Round 2: Non-Interactive/sudo Invocation

**Symptom:** after §14's fix (`/etc/profile.d/cuda.sh`) and re-login, `nvcc` was reported lost again.

**First diagnosis:** re-login was via a **non-login shell** (`echo $0` → `/bin/bash`, no leading `-`; `shopt login_shell` → `off`). `/etc/profile.d/` only loads for login shells, so it never ran. Fixed by also adding the `PATH` export to `/etc/bash.bashrc`, which covers all interactive bash shells (login or not):

```bash
grep -q '/usr/local/cuda/bin' /etc/bash.bashrc || \
  echo 'export PATH=/usr/local/cuda/bin:$PATH' | sudo tee -a /etc/bash.bashrc
```

Verified working in a plain non-login subshell (`bash` → `which nvcc` → `/usr/local/cuda/bin/nvcc`).

**Second failure — different mechanism, not a regression:** running `sudo bash ./gb300_l10_sw_checklist.sh` right after still showed `nvcc: MISSING`. Root cause is distinct from the login-shell issue:
- `bash script.sh` is a **non-interactive** shell — non-interactive script execution never sources `/etc/profile.d/`, `/etc/bash.bashrc`, or `~/.bashrc` at all, regardless of login/non-login status.
- `sudo` additionally resets `PATH` via its own `secure_path` setting in `/etc/sudoers`, independent of whatever the calling shell's environment was.

Since the checklist script's own documented usage is `sudo ./gb300_l10_sw_checklist.sh`, it can never reliably depend on the caller's shell environment — the correct fix is inside the script itself, not another layer of shell rc files. Patched (now v0.4.3):

```bash
[[ -d /usr/local/cuda/bin ]] && PATH="/usr/local/cuda/bin:$PATH"
```

Added immediately after `set -uo pipefail`, so it applies before any checks run regardless of how the script is invoked (interactive, non-interactive, login, non-login, cron, etc).

*Status: complete. Three layers now in place: `/etc/profile.d/cuda.sh` (login shells), `/etc/bash.bashrc` (all interactive shells), and the script's own defensive PATH line (non-interactive/sudo invocation, covers the checklist script regardless of caller environment).

**Confirmed via `sudo bash ./gb300_l10_sw_checklist.sh`** — the exact invocation that was failing:
```
 nvcc (CUDA toolkit)              : Cuda compilation tools, release 13.0, V13.0.88 [OK]
 ...
 Summary: 29 OK | 1 NEEDS REVIEW | 7 MISSING
```
`nvcc` now `OK` regardless of how the script is invoked. All three PATH layers verified working end-to-end.*

## 16. EXPECTED_MOFED / EXPECTED_FM Resolved via NVOnline 1160245 Raw JSON

**Source used:** raw JSON export of NVOnline 1160245 (`GB300MaxQNVL_72x1_2.0.0RC4`, milestone `2.0.0-build25`, BoardSKU `P4059`) — a higher-confidence source than the earlier Table 2 screenshot, since it's the full structured component list rather than a single public-links excerpt.

**Method:** parsed every `Component`/`Version` pair in the file rather than searching for MOFED specifically, to avoid missing it under a different name:

```
BF3_BFB: 32.49.1118        BFB: 3.4.1-11              BMC: 260710.1.0_custom
CPLD: 0.22                 CX8: 40.49.1118             DOCA_Host: 3.4.1-010000
GFM: 580.173.04             GPU: 97.10.7D.00.0D        MFT Tools: 4.36.0-147
NMX-C: 4.21.156             NMX-T: 4.20.9              NVOS: 25.02.4463
SBIOS: 02.06.06             VBIOS: 97.10.7D.00.0D       WinOF-2: 26.4.27095
(+ several BMC/CPLD/EROT/SMR/SM variants)
```

**Finding 1 — MOFED has no independent version entry in this release.** Confirmed by exhaustive check, not just absence-of-evidence: `DOCA_Host: 3.4.1-010000` is the only OFED-adjacent line item anywhere in the file. MOFED is absorbed into `DOCA_Host` rather than tracked separately in this release train. `EXPECTED_MOFED="24.10"` was checking against a target that no longer exists as an independent value.

**Fix:** removed `EXPECTED_MOFED` entirely rather than replacing it with the installed value (`26.04-1.0.9`) — setting it to "whatever's installed" would just reintroduce the same category of unverified-assumption problem the CUDA fix was meant to close. `MOFED Version` is now an informational-only row (no PASS/FAIL comparison).

**Finding 2 — `EXPECTED_FM="570"` was also stale**, found opportunistically while reviewing the full list. `GFM: 580.173.04` is the confirmed Fabric Manager target. Corrected in the same pass and added to the §0 matrix (previously had no Fabric Manager row at all).

**Not corrected — noted, not acted on:** `VBIOS: 97.10.7D.00.0D` in this source file doesn't obviously match the already-confirmed-installed `97.10.59.00.13` from earlier checklist runs, but the two use different notation (this file's value appears to be raw hex bytes) and there's no `EXPECTED_VBIOS` variable in the script to correct either way. Flagged for awareness only — not treated as a discrepancy without understanding the notation difference first.

**Update, 2026-09-14 — see §0a.** GA's release notes independently confirm the same `7D` segment (`97.10.7D.00.16`), reopening this as a likely-real mismatch rather than a notation artifact. `EXPECTED_VBIOS` added to the checklist in v0.4.25.

```bash
# gb300_l10_sw_checklist.sh changes (v0.4.3 -> v0.4.4)
EXPECTED_FM="580.173.04"       # was "570"
# EXPECTED_MOFED removed
```

*Status: complete. `EXPECTED_FM` corrected and added to §0. `EXPECTED_MOFED` removed (no longer a valid independent target per source of truth); `MOFED Version` check is now informational. `NVSwitch Devices` remains the one still-open item from §13, unconfirmed either way (expected for un-racked L10 vs. real gap).*

## 16a. Checklist Confirmation Run — Post §16 Fix

```
 MOFED Version                    : OFED-internal-26.04-1.0.9:             [OK]
 ...
 Summary: 30 OK | 0 NEEDS REVIEW | 7 MISSING
```

`MOFED Version` now `[OK]` (informational, no stale-target false flag). `CHECK` column at zero for the first time. Remaining `MISSING` rows are all legitimately pending installs (Fabric Manager, DCGM, Docker/containerd/nvidia-container-toolkit/default runtime) plus `NVSwitch Devices`, the one still-unresolved item.

*Status: complete.*

## 17. CPLD / EROT / HMC / FPGA Readout — In-Band vs. Out-of-Band

Checked whether CPLD, EROT, HMC, FPGA (per NVOnline component table) are readable in-band, same as SBIOS (`dmidecode -t 0`) and GPU/VBIOS (`nvidia-smi`).

**Finding:** only SBIOS is genuinely in-band — CPLD/EROT/HMC/FPGA are BMC-domain firmware, not exposed to the host as PCIe/DMI devices. The standard tool for reading them (`nvfwupd`) is explicitly documented as out-of-band, requiring a BMC IP target (`-t ip=<bmc-ip> ...`) regardless of whether that IP is reached over the datacenter network or a local host↔BMC link. Decided not to pursue further since a BMC IP is required either way.

**Separately confirmed as an accepted, known gap (not investigated further):** HMC version mismatch against the NVOnline reference table — firmware update not yet available for this component.

*Status: superseded — see §22, this was actually implemented and resolved rather than staying closed.*

## 18. L10 Partner Manufacturing Diag — Config Reference (partnerdiag)

Two files synced late, after most of the bring-up above was already logged: `spec_gb300_nvl_2_4_board_pc_partner_mfg.json` and `sku_gb300_nvl_2_4_board_pc_partner_mfg.json`. This is the diag referenced back in §7d ("NV L10 partner diag is now in scope for this unit") — logging it here now rather than retroactively editing §7d.

**What these two files are:**
- `spec_...json` — the diag action list, run via MODS (`DiagType: partner_mfg`, `GB300-NVL L10 Partner Manufacturing Diag`). Defines every test step, thresholds, timeouts, and which subtests are enabled vs. `skip_test: true` for this run profile. Board identity is set via `BaseboardsPciIds` (`0009/0008/0019/0018:06:00.0`) and `gpu_pci_ids_loc_info_map`, which assigns `logical_id 0-3` to `sxm_id 1-4` respectively.
- `sku_...json` — the expected-inventory manifest the spec's `Inventory` action (`Level0`) validates the physical board against: 2 CPUs × 144 cores (`NUMA_NODE0_CPU 0-71` / `NUMA_NODE1_CPU 72-143`), 2 × 480 GB DIMMs (960 GB total), 4 GPUs at the same PCI IDs as the spec's baseboard map.

**Cross-check against what's already confirmed elsewhere in this log:** only GPU count lines up with something independently confirmed so far — checklist script's `GPU Count: 4 [OK]`. CPU core count, DIMM/memory total, and the specific GPU PCI IDs (`0008/0009/0018/0019:06:00.0`) haven't been independently verified against `lscpu`/`free`/`lspci` output anywhere in this log yet — worth a quick confirm before relying on the SKU file as a passive cross-check rather than running the diag's own `Inventory` action to do it.

**Test coverage this run profile actually exercises** (i.e. not `skip_test: true`): inforom/checkinforom, `Inventory` (Level0), `HbmScreen`, PCIe properties for CX8 (Gen5 + Gen6), BF3 (data + mgmt), SSD (E1.S), USB; Grace CPU/memory/C2C-link diags (`TegraCpu`, `TegraMemory`, `CpuMemorySweep`, `TegraClink`); `Gpustress`/`Gpumem` (Level0); `PerfBenchmark_GEMM` (`pass_on_fail: true` — informational, doesn't fail the run); `Pcie` (Level0); `Connectivity` (with `nvlink`/`i2c`/`powercable` explicitly skipped inside that action); `NvlBwStress`/`NvlBwStressBg610`/`C2C`; `CpuGpuSyncPulsePower` + `ThermalSteadyState` (with DRA thermal-limit checks against all 4 GPU BDFs); `CxeyegradeStart`/`Stop` (SerDes eye/BER margin on CX8 + BF3 ports); `Ssd` (fio read/write/randread/randwrite thresholds against `/dev/nvme0n1` → `/`); and the syslog/kern.log/dmesg error + AER scrapers.

**Explicitly skipped in this run profile** (`skip_test: true`) — worth calling out so "diag passed" doesn't get read as "everything ran": `DisableAcs`; all four GPUDirect RDMA subtests (`Cx8GpuDirectLoopback_ETH`, `Cx8GpuDirectExtLoopback_ETH`, `Cx8GpuDirectCrossNIC_ETH`, `Cx8GpuDirectCrossNIC_IB`); all four CPU-path IB/Ethernet bandwidth subtests (`Cx8CpuCrissCrossNIC_ETH`, `Cx8CpuCrossNIC_ETH`, `Cx8CpuCrossNIC_IB`, `Cx8CpuLoopback_ETH`, Level1); `BF3PcieInterfaceTraffic` (dpudiag against the BF3 at `172.16.0.151`); and the `DNM6` workload (4× 900 s runs). None of the IB/RDMA bandwidth subtests run in this profile — consistent with this being a single, un-racked compute tray with no fabric peers, same reasoning already applied to Fabric Manager and `NVSwitch Devices` elsewhere in this log.

**Not included in these two files: actual execution results.** Both are diag *definitions* — a test spec and an expected-inventory manifest — not a results/report output. No pass/fail data to log from this sync; that still needs to come from an actual diag run.

*Status: reference-only, logged for traceability ahead of provisioning. Diag has not been executed yet — see Next Steps.*

## 18a. MaxQ SKU — Required Diag JSON Modifications (Reference for Others)

This unit is confirmed `GPU Name: NVIDIA GB300 Max-Q` (checklist §13/17a). The stock `spec_gb300_nvl_2_4_board_pc_partner_mfg.json` / `sku_gb300_nvl_2_4_board_pc_partner_mfg.json` from §18 are for the standard (non-MaxQ) board and **will misreport a MaxQ unit as failing `Inventory`/`BfPcieProperties`/`BfMgmtPcieProperties` if used as-is**. Diffed the standard files against the MaxQ-specific ones (`spec_gb300_nvl_2_4_board_pc_partner_mfg_maxQ.json`, `sku_gb300_nvl_2_4_board_pc_partner_mfg.json` — same filename as before, content replaced) to isolate exactly what changes. Logging the deltas here as a checklist for anyone repeating this on another MaxQ unit, rather than just swapping files silently.

**SKU manifest (`sku_...json`) — GPU PCI IDs, all 4 entries (`0008/0009/0018/0019:06:00.0`):**

| Field | Standard | MaxQ |
|---|---|---|
| `DeviceID` | `31c2` | `31a1` |
| `DeviceName` | `Device 31c2` | `Device 31a1` |
| `SSDeviceID` | `21f1` | `2274` |

Everything else in the SKU file — CPU count/cores, DIMM quantity/size, `VendorID`, `PCIID`, `RetimerCount` — is identical between the two. This is purely the GPU die/subsystem ID differing by power/binning SKU, not a topology change.

**Diag spec (`spec_...json`) — three categories of change, not just one:**

1. **Global timeout added** — top-level `global_args` goes from `[]` to `["timeout_ms=30000"]`. Applies diag-wide, not tied to a specific test.

2. **BF3 BDFs move buses** — `BfPcieProperties` and `BfMgmtPcieProperties` target `0016:03:00.{0,1,2}` on the standard board but `0016:01:00.{0,1,2}` on MaxQ. This is a real topology difference (different PCIe bus enumeration on the MaxQ board layout), not a cosmetic rename — using the standard BDFs against a MaxQ unit will simply not find the device rather than fail a threshold check.

3. **Seven previously-skipped tests are enabled** (`skip_test: true → false`): `DisableAcs`, `Cx8GpuDirectLoopback_ETH`, `Cx8GpuDirectExtLoopback_ETH`, `Cx8GpuDirectCrossNIC_ETH`, `Cx8CpuCrossNIC_ETH`, `Cx8CpuLoopback_ETH`, `BF3PcieInterfaceTraffic`. Four remain skipped in both profiles: `Cx8GpuDirectCrossNIC_IB`, `Cx8CpuCrissCrossNIC_ETH`, `Cx8CpuCrossNIC_IB`, `DNM6`. Net effect: the MaxQ profile actually exercises GPUDirect RDMA loopback/cross-NIC-Ethernet and CPU-path Ethernet bandwidth, on top of everything §18 already listed as common to both profiles.

4. **`BF3PcieInterfaceTraffic` itself is restructured, not just re-timed.** Beyond the longer `timeout_sec` (240→450) and `duration` (30→300):
   ```
   standard:  "players": [{ "bf": { "ip": "172.16.0.151", "username": "root",
                                     "password": "SuperNvidia1", "pci": "0016:03:00", "sd_pci": null } }]
   maxQ:      "players": [{ "cx": { "pci": "0016:01:00", "sd_pci": null } }]
   ```
   Standard targets a `bf` player — SSH into the BlueField's own DPU-side OS at a management IP. MaxQ targets a `cx` player — PCI-only, no SSH, no DPU-side OS credentials. This lines up with §6c/§18: this build's BF3 runs in NIC mode with no DPU-side OS on the Arm cores (same reasoning behind waiving the "BF3 DPU OS version" checklist row), so a diag step that assumes an SSH-reachable DPU OS would have been structurally wrong here regardless of thresholds — the MaxQ spec's `cx`-player version is actually the *only* variant of this test that fits this unit's configuration, not just a MaxQ-specific preference.

**Practical takeaway for the checklist:** don't treat "MaxQ" as a single value substitution — it's a different SKU manifest, a different BF3 PCI topology, a wider enabled-test set, and one test's execution mechanism changes because it now correctly matches this unit's NIC-mode BF3 rather than assuming a DPU OS exists.

*Status: reference-only, both MaxQ-specific files now on file for the diag run planned in §18's Next Steps item.*

## 18b. L10 Partner Diag — PASS Result (run.log)

Actual execution of the MaxQ-profile diag configured in §18/§18a.

```
Command Line: onediagfield.r9.343.7 --run_on_error --no_bmc --force_product=titania_gb110 --dra
              --run_spec=spec_gb300_nvl_2_4_board_pc_partner_mfg_maxQ.json
              --skip_os_check --skip_id=SsdPciePropertiesE1S --auto_repair
```

**Board identity confirmed by the diag itself** — consistent with §0/checklist confirmations already in this log:

| Field | Diag-reported |
|---|---|
| Product | Carlo_Next MaxQ |
| Product Version | DVT |
| Family | MGX |
| SKU | RA4802-72N2 |
| Serial Number | 267548730004 |

**Result: `Final Result: PASS`.** Start `Mon, 10 Aug 2026 01:26:06`, end `04:06:43`, elapsed `160:37s` (~2h 40m). Every enabled test completed with no `FAIL`.

**Two `IGNORED` results, not a gap** — `PerfBenchmark_GEMM` and `CxeyegradeStop` both report `IGNORED` rather than `OK`/`SKIPPED`. That's the diag's status label for the spec's `pass_on_fail: true` steps (both carry that flag per §18). `CxeyegradeStop`'s own per-connection detail table shows `OK` underneath — `IGNORED` only means the result doesn't gate the overall pass/fail, not that it didn't run.

**Five skips, for two different reasons — worth keeping distinct:**
- `Cx8GpuDirectCrossNIC_IB`, `Cx8CpuCrissCrossNIC_ETH`, `Cx8CpuCrossNIC_IB`, `DNM6` — skipped per the MaxQ spec's own `skip_test: true` (§18a already documented these as still-disabled even in the MaxQ profile).
- `SsdPciePropertiesE1S` — skipped via the **command line** (`--skip_id=SsdPciePropertiesE1S`), not the spec file. The spec doesn't mark this test skipped by default, so this was an operator decision on this specific run, not a MaxQ-vs-standard spec difference — §18a's diff wouldn't have caught it since it isn't in the JSON at all. A future MaxQ run without that flag would exercise it.

**`--auto_repair` had nothing to do** — `AutomaticRepair OK - Nothing to repair`, confirming no corrective action was triggered during the run.

*Status: complete — diag PASS, board identity self-confirmed, no failures or unexplained skips. Cleared for provisioning per this log's own gating criteria.*

## 19. IMEX Service Inactive — Resolved: Expected L10 Behavior, Not a Bug

`gb300_l10_sw_checklist.sh` v0.4.8 added `IMEX Service`/`IMEX Version` rows, checking for `active`. v0.4.8's version had a bug that reported `IMEX Service: inactive [OK]` as a false pass (no exact-match comparison). v0.4.9's attempted fix (`expected="active"`) didn't work either — substring match means `"inactive"` passes against `expected="active"` since it literally contains that substring. v0.4.10 fixed the comparison mechanics correctly and the checklist started reporting the true state: `IMEX Service: - [MISSING]`.

**That MISSING was then wrongly treated as an open bug in this section's original text.** It isn't one — §7 and §7c, written *before* this checklist row even existed, already documented that `inactive (dead)` is IMEX's expected clean-exit state at L10. More precisely than "no fabric peers": IMEX only goes and stays active once **two separate conditions** are both met — (1) GFM is actually up and functioning on the NVSwitch tray's NVOS (§16's Fabric Manager `N/A` rows — this host can't provide that), and (2) this node's own IMEX peer config (`/etc/nvidia-imex/config.cfg`, staged but not populated per §7) is filled in with the actual NVLink domain member IPs, typically via `nodes_config.cfg`. Neither is meaningful or achievable on a single un-racked L10 compute tray. The bug was in what v0.4.8–v0.4.10 chose to *check for* (`active`), not in the system itself.

**v0.4.11 corrects the checklist** to ask two separate questions instead of one conflated one: `IMEX Service (enabled)` (checks `systemctl is-enabled`, meaningful at any bring-up stage — a real `MISSING` here would be a real problem) and `IMEX Active State` (now `N/A`, same treatment as `Fabric Manager`, since `active` genuinely isn't meaningful until racked).

*Status: resolved — no root cause to chase. Closing out; §7/§7c already had the answer, this section just hadn't cross-referenced them before flagging it as open.*

## 20. mst Device Tree Not Persistent Across Reboot

Found via a routine BIOS/BMC upgrade (`00.56.02` → `00.58.03`) and reboot: `gb300_l10_sw_checklist.sh` came back with `BF3 Firmware Version`/`CX8 Firmware Version` both `[MISSING]`, having previously been `[OK]` on every prior run.

**Not caused by the BIOS/BMC update content.** `MFT Tools Version`, `BlueField DPU Detected`, and `IB Devices` (`mlx5_0`–`mlx5_9`, all present) were all still `[OK]` — the cards themselves are fine, still enumerated, still queryable via the standard `ibstat`/`rdma-core` paths. Only the two checks that go through `flint -d /dev/mst/...` broke.

**Root cause:** §10's firmware-burn procedure ran `sudo mst start` (creates the `/dev/mst/*` device tree), did the burn, then explicitly `sudo mst stop`'d afterward — deliberate cleanup at the time, but `mst start` was never set up as a persistent boot-time service anywhere in this bring-up. The device tree it creates is ephemeral by design; it does not survive a reboot on its own. The checklist script itself compounded this — it queries `/dev/mst/mt41692_pciconf0`/`mt4131_pciconf0` directly but never called `mst start` first, just assuming the device tree already existed. Every prior checklist run showing `OK` was relying on residual manual state (most likely someone running `mst start` incidentally during §12's Ansible CX8/BF3 config work) rather than anything actually persistent. **This will recur after any reboot** — this BIOS/BMC update just happened to be the reboot that exposed it, not a special trigger.

**Fix — `gb300_l10_sw_checklist.sh` v0.4.13:** added an idempotent `mst start >/dev/null 2>&1` immediately before the BF3/CX8 checks, so the script no longer depends on leftover state from something else:

```bash
mst start >/dev/null 2>&1
check "BF3 Firmware Version"   "flint -d /dev/mst/mt41692_pciconf0 q 2>/dev/null | grep -m1 'FW Version'" "$EXPECTED_BF3_FW"
check "CX8 Firmware Version"   "flint -d /dev/mst/mt4131_pciconf0 q 2>/dev/null | grep -m1 'FW Version'" "$EXPECTED_CX8_FW"
```

**Worth knowing beyond just the checklist script:** anything else on this node that assumes `/dev/mst/*` is present — other MFT-based tooling, manual `mlxconfig`/`mlxfwmanager` invocations, future firmware re-verification — will hit the same silent gap after a fresh reboot unless it also calls `mst start` first (or unless `mst start` gets made a genuinely persistent boot-time service, which hasn't been done here — the checklist fix works around the gap rather than closing it at the source). Relevant for §16's rack-wide cloning plan too: whoever clones this reference layout to the other 17 compute trays will hit this exact same thing on their first reboot post-image unless they know to run `mst start` (or apply this same checklist fix) first.

**Two unrelated but real identity changes also observed from this same BIOS/BMC upgrade, confirmed intentional-looking rather than a mis-flash but not independently verified against release notes:**

| Field | Before (`00.56.02`) | After (`00.58.03`) |
|---|---|---|
| System Product Name | `Carlo_Next MaxQ` | `CARLO_NEXT-T1` |
| VBIOS Version | `97.10.59.00.13` | `97.10.7D.00.0D` |

`GPU Name` still correctly reports `NVIDIA GB300 Max-Q` throughout, so the underlying hardware/SKU hasn't changed — this looks like a DMI/system-identity table string change and a bundled GPU VBIOS capsule update shipped together in the same `00.58.03` release, not a hardware swap or wrong-image flash. Not chased further here since it didn't block anything, but worth a sanity check against the BIOS/BMC release notes if this System Product Name string is depended on anywhere downstream (inventory tooling, asset tags, etc.) — a string change like `Carlo_Next MaxQ` → `CARLO_NEXT-T1` could silently break exact-match lookups elsewhere.

*Status: resolved for the checklist script (v0.4.13). Not resolved at the source — `mst start` still isn't a persistent boot-time service, so any tooling outside this checklist that assumes `/dev/mst/*` exists remains exposed to the same gap after a reboot.*

## 21. Field-Site Offline Kernel Upgrade Procedure (6.14 → 6.17.0-1029-nvidia-64k)

Customer request: bring field-deployed units (shipped with the Grace 4KB-page-era `6.14` nvidia kernel) up to this reference layout's kernel — `6.17.0-1029-nvidia-64k`, `6.17.0-1029.29` — but field sites have no internet access. Package acquisition has to happen on a connected staging machine, then be carried in and installed offline. Logging the procedure here since this is the kind of thing that's easy to half-remember and get subtly wrong (wrong version pinned, missing DKMS prerequisites, dependency-resolution gaps) on a repeat.

**Good news up front:** this kernel comes from the plain Ubuntu archive, not NVIDIA's private NVOnline repo — §3 installed it with a bare `apt install linux-nvidia-64k-hwe-24.04`, no special repo added beforehand. No NVOnline credentials needed for this part, only for the driver/DOCA/CUDA pieces covered elsewhere in this log.

**1. Stage on a connected machine with matching OS + arch.** Ubuntu 24.04, `arm64`/aarch64. Doesn't need to be a GB300 itself — any Ubuntu 24.04 aarch64 box or container with internet access works, since this is just resolving and downloading `.deb`s from the standard archive.

**1a. Staging from an x86 laptop specifically.** Confirmed workable, with a caveat on *how*, not *whether* — and importantly, **this never touches the reference layout at all**. It's pure package acquisition on a separate machine; the GB300 reference node isn't involved in staging, only as the source of the pinned version number (`6.17.0-1029.29`) being matched.

Why the plain approach doesn't work: `linux-nvidia-64k-hwe-24.04` and its siblings are arm64-only (the 64KB-page kernel flavor doesn't exist for x86_64 — it's a Grace/ARM-server thing). A stock x86_64 laptop's default apt sources don't even index that architecture, so a bare `apt install` fails outright with `Unable to locate package`, not a wrong-architecture download. Ubuntu's arm64 packages also live on a different mirror (`ports.ubuntu.com`) than the default amd64 mirror (`archive.ubuntu.com`).

Two ways around it:

- **Docker + QEMU emulation (recommended).** Works regardless of the laptop's host OS (Windows/Mac/Linux) — Docker Desktop or Docker Engine is enough. Gives a real arm64 apt environment, so `install --download-only` resolves the *full* dependency tree correctly, same as step 2 below assumes:
  ```bash
  # one-time: enable QEMU emulation for cross-arch containers
  docker run --rm --privileged tonistiigi/binfmt --install arm64

  # arm64 Ubuntu 24.04 container, host directory mounted so the .debs land
  # directly on the laptop's filesystem
  docker run --rm -it --platform=linux/arm64 \
    -v "$(pwd)/gb300-kernel-repo:/out" ubuntu:24.04 bash

  # inside the container - same download command as step 2 below:
  apt-get update
  apt-get install -y --download-only \
    linux-nvidia-64k-hwe-24.04=6.17.0-1029.29 \
    linux-image-nvidia-64k-hwe-24.04=6.17.0-1029.29 \
    linux-headers-nvidia-64k-hwe-24.04=6.17.0-1029.29
  cp /var/cache/apt/archives/*.deb /out/
  exit
  ```
  Then continue directly at step 3 below (bundle into a local repo) using the `.deb`s now sitting in `~/gb300-kernel-repo/` on the laptop.

- **Native multi-arch apt, only if the laptop itself runs Ubuntu/Debian x86_64:**
  ```bash
  sudo dpkg --add-architecture arm64
  echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble main restricted universe multiverse" \
    | sudo tee /etc/apt/sources.list.d/arm64-ports.list
  sudo apt-get update
  sudo apt-get download \
    linux-nvidia-64k-hwe-24.04:arm64=6.17.0-1029.29 \
    linux-image-nvidia-64k-hwe-24.04:arm64=6.17.0-1029.29 \
    linux-headers-nvidia-64k-hwe-24.04:arm64=6.17.0-1029.29
  ```
  Real caveat: `apt-get download` (unlike `install --download-only`) only fetches the exact packages named — it does **not** walk the dependency tree. Missing dependencies would have to be resolved and downloaded manually (e.g. via `apt-cache depends`/`apt-rdepends`), which is easy to get wrong and quietly ship an incomplete bundle. The Docker route above avoids this failure mode entirely, which is why it's the recommended one.

**2. Download the exact pinned version this reference layout uses — not whatever HWE happens to be current at build time.** Field units need to land on the same build (`6.17.0-1029.29`, per §3's verification table), not a newer HWE point release that might land between now and when the bundle gets built:

```bash
sudo apt-get update
sudo apt-get install --download-only \
  linux-nvidia-64k-hwe-24.04=6.17.0-1029.29 \
  linux-image-nvidia-64k-hwe-24.04=6.17.0-1029.29 \
  linux-headers-nvidia-64k-hwe-24.04=6.17.0-1029.29
```

`--download-only` pulls the *full resolved dependency tree* into `/var/cache/apt/archives/`, not just the three named packages. This matters — a manual per-package `dpkg -i` will hit unmet-dependency errors offline with no way to fetch the missing pieces, unlike on a connected system.

**3. Turn the download cache into a portable local apt repo, not loose `.deb`s.** This preserves dependency resolution on the air-gapped side instead of manually figuring out install order:

```bash
mkdir -p ~/gb300-kernel-repo && cp /var/cache/apt/archives/*.deb ~/gb300-kernel-repo/
cd ~/gb300-kernel-repo
dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
sha256sum * > SHA256SUMS   # checksum before transfer - no internet at the far
                            # end to re-verify against upstream if something
                            # got corrupted in transit
```

**4. Transfer via removable media**, then on the field unit:

```bash
echo "deb [trusted=yes] file:///path/to/gb300-kernel-repo ./" | sudo tee /etc/apt/sources.list.d/local-kernel.list
sudo apt-get update   # only touches the local repo, no internet needed
sudo apt-get install linux-nvidia-64k-hwe-24.04=6.17.0-1029.29 \
                      linux-image-nvidia-64k-hwe-24.04=6.17.0-1029.29 \
                      linux-headers-nvidia-64k-hwe-24.04=6.17.0-1029.29
sudo reboot
```

**5. DKMS prerequisite — confirm BEFORE shipping the bundle, not after.** The NVIDIA driver on this reference layout was installed with `--dkms` (§7), so it needs to rebuild its kernel module against the new 6.17 headers after the swap. That rebuild is normally triggered automatically by the kernel package's postinst DKMS hook — but it needs `dkms`, `gcc`, and `make` (§5, "Kernel Build Packages") **already present on the 6.14 field system before the upgrade**, since there's no internet there to fetch them if missing. Check `dpkg -l | grep -E 'dkms|build-essential'` on a representative field unit ahead of time — if those are missing, they need to go into the same offline repo bundle in step 3, not be assumed present.

**6. Post-reboot verification, mirroring §3/§4's original bring-up hygiene:**

- `uname -r` → `6.17.0-1029-nvidia-64k`
- `dkms status` → NVIDIA module shows built/installed against the new kernel
- Purge the old `6.14` kernel packages the same way §3 cleaned up the stale generic kernel (check for leftover `/lib/modules/<old>/` directories, dangling headers, `apt autoremove`)
- Re-apply the same `apt-mark hold` from §4 (`linux-nvidia-64k-hwe-24.04`, `linux-image-nvidia-64k-hwe-24.04`, `linux-headers-nvidia-64k-hwe-24.04`) so nothing drifts again
- Run `gb300_l10_sw_checklist.sh` as the final gate — it already checks kernel version, page size, held-package state, and GPU kernel module version in one pass (`OS / Kernel / Platform` and `NVIDIA Driver / CUDA / GPU` sections)

**Open items not yet resolved, to fill in on the first real field attempt:**
- Staging method now documented (§21 step 1a, Docker+QEMU on an x86 laptop) but not yet actually run — first real attempt should confirm the emulated arm64 apt environment resolves cleanly end-to-end.
- Confirmed presence (or absence) of `dkms`/`build-essential` on the actual 6.14 field-shipped image — step 5 assumes this needs checking, not yet confirmed against a real unit.

*Status: procedure drafted, not yet executed against a real field unit. Treat as a reference plan to validate on the first attempt, not a confirmed-working runbook yet.*

## 22. Out-of-Band Firmware via Redfish — §17 Resolved

Triggered by an HMC firmware release-notes screenshot (bundle `nvfw_GB300-P4059-0311_0044_260710.1.0_custom_prod-signed.fwpkg`, version `260710.1.0_custom`) showing `CPLD: 0.22`, `GPU: 97.10.7D.00.0D`, `EROT: 01.04.0055.0000_n04`, `HMC: GB200Nvl-26.07-1`, `SBIOS: 02.06.06`, `FPGA: 1.66`. The `GPU` value matched the checklist's post-`00.58.03`-upgrade reading exactly, confirming that VBIOS change from §20 was intentional bundle content, not a mis-flash — that part of §20's open item is now closed.

**`ipmitool` confirmed not a substitute for this.** CPLD/EROT/FPGA as individually-versioned components is a Redfish/PLDM `FirmwareInventory` concept with no classic-IPMI equivalent — `ipmitool mc info` can only reach the BMC's own version (roughly the `HMC` row), and even that may be blocked depending on the BMC's "IPMI visibility for Host" setting.

**Implemented directly in `gb300_l10_sw_checklist.sh` (v0.4.14 → v0.4.17), not just discussed:**
- BMC IP discovered in-band via `ipmitool lan print 1`; reports `N/A` (not `MISSING`) if empty — same principle as `Fabric Manager`/`IMEX Active State`, never attempts a doomed Redfish call.
- v0.4.14's first attempt used a single-call `?expand=.$levels=1`, per NVIDIA's DGX GB Rack Scale Systems doc — confirmed against this unit's actual Pegatron-built BMC (Redfish 1.17.0) that the expand syntax is **not honored**; it silently returns the plain unexpanded list instead. NVIDIA's documented syntax was apparently AMI-BMC-specific, not universal.
- v0.4.15 switched to a guaranteed-correct two-step approach: plain `Members` list → filter by keyword (`CPLD|EROT|HMC|BMC|FPGA`) → `GET` each matched component individually. ~12 HTTP calls instead of 1, prioritizing correctness over call count.
- v0.4.16 split the result into one row per component instead of one long semicolon-joined string, for readability.
- Credentials default to `root`/`0penBmc` (MaxQ factory account), overridable via `BMC_USER`/`BMC_PASS` env vars for units with rotated credentials.

**Real confirmed data from this unit (2026-08-11)** — 12 of 30 total `FirmwareInventory` members matched the filter:

| Component Id | Version |
|---|---|
| `FW_BMC_0` | `carlonext-bmc_0.82.03` |
| `FW_E1S_CPLD_0` | `0b.04.02` |
| `FW_E1S_CPLD_1` | `0b.04.02` |
| `HGX_FW_BMC_0` | `GB200Nvl-26.07-1` |
| `HGX_FW_CPLD_0` | `0.22` |
| `HGX_FW_ERoT_BMC_0` | `01.04.0055.0000_n04` |
| `HGX_FW_ERoT_CPU_0` | `01.04.0055.0000_n04` |
| `HGX_FW_ERoT_CPU_1` | `01.04.0055.0000_n04` |
| `HGX_FW_ERoT_FPGA_0` | `01.04.0055.0000_n04` |
| `HGX_FW_ERoT_FPGA_1` | `01.04.0055.0000_n04` |
| `HGX_FW_FPGA_0` | `1.66` |
| `HGX_FW_FPGA_1` | `1.66` |

**Cross-checked against the HMC bundle screenshot — all four match:** `HGX_FW_CPLD_0=0.22` ↔ bundle `CPLD 0.22`; `HGX_FW_ERoT_*=01.04.0055.0000_n04` ↔ bundle `EROT 01.04.0055.0000_n04`; `HGX_FW_BMC_0=GB200Nvl-26.07-1` ↔ bundle `HMC GB200Nvl-26.07-1`; `HGX_FW_FPGA_*=1.66` ↔ bundle `FPGA 1.66`.

**One real distinction the live data revealed, worth keeping straight going forward:** two separate "BMC" identities exist on this platform — `FW_BMC_0` (`carlonext-bmc_0.82.03`, this compute tray's own BMC firmware, versioned independently) vs. `HGX_FW_BMC_0`/`HGX_FW_ERoT_BMC_0` (the HGX baseboard's BMC-domain components, matching the HMC bundle's own versioning track). They are not the same firmware and don't share a version number — don't conflate them when reading future output. Also worth noting: no component `Id` on this BMC literally contains the string `"HMC"` — the concept is exposed via `BMC` naming instead.

*Status: resolved. §17's "closed, not pursued further" is superseded — this is now implemented, tested against the real unit, and producing accurate data on every checklist run.*

## 22a. Disk-Cleanup Pass — Stale Local-Repo Packages + Unused Swap (2026-09-02)

Triggered by a routine `du -shc *` under `/var` showing 5.2G total, with two single directories accounting for the bulk of it:

| Directory | Size | What it actually was |
|---|---|---|
| `cuda-repo-ubuntu2404-13-0-local` | 3.6G | Local APT repo tree created by the `.deb` used to install the CUDA Toolkit (§8) |
| `nvidia-driver-local-repo-ubuntu2404-580.173.02` | 573M | Local APT repo tree created by the local-repo `.deb` used for the `nvidia-fabricmanager` install (§25) |

**Confirmed both are dpkg-tracked packages, not orphaned folders** — `dpkg -l | grep -iE 'cuda|nvidia'` showed both as `ii`:
```
ii  cuda-repo-ubuntu2404-13-0-local                       13.0.2-580.95.05-1
ii  nvidia-driver-local-repo-ubuntu2404-580.173.02        1.0-1
```
So the correct removal path is `apt purge` (removes the dpkg entry, the `/var/...` tree, and the matching `/etc/apt/sources.list.d/*.list` entry together), not a manual `rm -rf` against a directory dpkg still owns.

**Pre-removal safety checks — both packages confirmed as install-time scaffolding only, not needed post-install:**
- `dpkg -l | grep -i cuda` — full CUDA 13.0 toolkit/library set present and unaffected by the repo package itself (`cuda-toolkit-13-0`, `cuda-cudart-13-0`, `cuda-nvcc-13-0`, etc. all separate, real packages).
- `nvidia-smi` — driver `580.173.02`, CUDA `13.0` reported correctly; all 4 GB300 Max-Q GPUs visible, 0 MiB used, no running processes. Confirms the driver install itself has nothing to do with whether its local-repo scaffolding stays on disk.

**Commands run:**
```bash
sudo apt purge cuda-repo-ubuntu2404-13-0-local
sudo apt purge nvidia-driver-local-repo-ubuntu2404-580.173.02
sudo apt update
sudo apt clean
```
Both purges cleanly removed the dpkg entry, config, and `/var/...` directory (`3,856 MB` and `600 MB` respectively per apt's own accounting). `apt update` afterward confirmed no dangling `sources.list.d` entries for either — the only remaining NVIDIA/DOCA-related repo file, `doca-kernel-26.04-1.0.9.0-6.17.0.1029.nvidia.64k.list`, is correctly left alone (belongs to the still-installed, in-use `doca-kernel-repo-...` package from §6, not leftover cruft).

**Result:** ~4.4G reclaimed under `/var`. `cuda-toolkit-13-0` (`13.0.2-1 [installed,local]`) confirmed still installed and intact via `apt list --installed` post-purge — this is the source referenced by §23's CUDA version table.

**Unrelated finding surfaced by `apt update`, logged but not acted on:** 130 packages showing as upgradable. **Deliberately not run** on this unit — with a custom `linux-nvidia-64k` kernel, DKMS-built NVIDIA driver, and DOCA host stack all version-pinned against the NVIDIA 2.0 release matrix (§0), a blanket `apt upgrade` risks pulling a mismatched kernel/driver and breaking `nvidia-smi` or DOCA. Flagged as a `Next Steps` item (§26) to review the list explicitly (`apt list --upgradable`) before ever upgrading this reference layout.

### Swap File Removal (`/swap.img`, 8G)

Found while auditing top-level `/` usage (`du -shc /*`) — `/swap.img` was present and mounted (`swapon --show` → `/swap.img file 8G 0B -2`) but showed **0B used** despite the host having been up and under normal bring-up load.

**Checked against the BCM category's actual disk-setup definition** (`get disksetup` on `category[maxQ-1014-doca321]`) — confirms swap is **not part of the intended reference layout** at all: the category only defines `efi` (100M), `boot1` (4G), and `slash1`/`/` (max, ext4). No swap partition or swap-file directive anywhere in the XML.

**Confirmed not provisioning-managed** — checked the category's `Initialize script` and `Finalize script` (both `<0B>`, i.e., empty) via `cmsh`, so nothing in this category's automated provisioning creates `/swap.img`; it was added manually/out-of-band by whoever originally set up this node, not by BCM.

**Confirmed safe on resource grounds** — `free -h` showed `2.0Ti` total RAM, `56Gi` used, swap at `0B` used out of `8.0Gi`. At this RAM scale, 8G of swap provides negligible OOM protection and was never being touched.

**Commands run:**
```bash
sudo swapoff -v /swap.img
sudo rm /swap.img
sudo sed -i '/swap.img/s/^/#/' /etc/fstab   # comment out rather than delete the line, for auditability
```

**Verification:**

| Check | Command | Result |
|---|---|---|
| Swap disabled | `free -h` | `Swap: 0B / 0B / 0B` ✅ |
| No active swap device | `swapon --show` | *(empty)* ✅ |
| fstab entry preserved but disabled | `cat /etc/fstab` | `#/swap.img      none    swap    sw      0       0` ✅ |
| `/` free space | `df` | `/dev/nvme0n1p2` — 856G available, 2% used ✅ |

**Open item — not yet checked at the category/fleet level:** confirmed only that *this node's* provisioning scripts don't recreate `/swap.img` on reinstall/resync. Whether other nodes in `maxQ-1014-doca321` (38 total) were built the same manual way and are carrying the same unused 8G swap file has not been checked. Worth a quick audit (`filesystemmounts` submode, plus a live `swapon --show` sweep across the category) if this reference layout's disk footprint is being finalized for fleet-wide golden-image capture (§25).

**`gb300_l10_sw_checklist.sh` v0.4.20 adds a "Disk Hygiene / Repo Cleanup" section** covering both findings — reports `OK` if the two local-repo packages stay purged and no swap is active, `CHECK` (not `MISSING` — footprint concern, not a functional defect) if either regresses on a future rebuild/re-clone. Run the checklist after any reinstall of §8/§25's steps to confirm this cleanup pass hasn't silently been undone.

*Status: both cleanup items complete and verified on `carlonext`. ~4.4G (repo packages) + 8G (swap) = **~12.4G reclaimed total** under `/`, with no functional regression — CUDA, driver, and DOCA stack all confirmed intact post-cleanup.*

## 22b. Stale Kernel Removal — `6.17.0-1029-nvidia-64k` (2026-09-14)

**Goal:** slim the reference layout further by removing the old kernel now that `6.17.0-1032-nvidia-64k` is current and both `vmlinuz`/`initrd.img` symlinks already point there with no `.old` fallback pointing at `1029`.

**Pre-removal checks (in order, before touching anything):**

```
root@carlonext:~# dpkg -l | grep '6.17.0-1029'
ii  doca-kernel-repo-26.04-1.0.9.0-6.17.0.1029.nvidia.64k 26.04.1.0.9.0
ii  linux-headers-6.17.0-1029-nvidia-64k                  6.17.0-1029.29
ii  linux-image-6.17.0-1029-nvidia-64k                    6.17.0-1029.29
ii  linux-modules-6.17.0-1029-nvidia-64k                  6.17.0-1029.29
ii  linux-nvidia-6.17-headers-6.17.0-1029                 6.17.0-1029.29
ii  linux-nvidia-6.17-tools-6.17.0-1029                   6.17.0-1029.29
ii  linux-tools-6.17.0-1029-nvidia-64k                    6.17.0-1029.29
ii  xpmem                                                 2604.0.2-1.kver.6.17.0-1029-nvidia-64k
```

```
root@carlonext:~# dkms status
iser/26.04.OFED.26.04.1.0.9.1-1, 6.17.0-1032-nvidia-64k, aarch64: installed
isert/26.04.OFED.26.04.1.0.9.1-1, 6.17.0-1032-nvidia-64k, aarch64: installed
kernel-mft-dkms/4.36.0.147, 6.17.0-1032-nvidia-64k, aarch64: installed
mlnx-ofed-kernel/26.04.OFED.26.04.1.0.9.1-1, 6.17.0-1032-nvidia-64k, aarch64: installed
nvidia/580.173.02, 6.17.0-1032-nvidia-64k, aarch64: installed
srp/26.04.OFED.26.04.1.0.9.1-1, 6.17.0-1032-nvidia-64k, aarch64: installed
xpmem/2604.0.2, 6.17.0-1032-nvidia-64k, aarch64: installed
```

```
root@carlonext:~# apt-mark showhold
linux-headers-6.17.0-1032-nvidia-64k
linux-headers-nvidia-64k-hwe-24.04
linux-image-6.17.0-1032-nvidia-64k
linux-image-nvidia-64k-hwe-24.04
linux-nvidia-64k-hwe-24.04
mlnx-ofed-kernel-utils
nvidia-modprobe
```

Every DKMS module (`nvidia`, `mlnx-ofed-kernel`, `iser`/`isert`/`srp`, `kernel-mft-dkms`, `xpmem`) is already exclusively built against `1032` — nothing registered for `1029`, so no `dkms remove` needed first. Holds only cover `1032`-versioned and meta-packages, none of the `1029`-versioned packages — purge won't fight the hold logic.

**`xpmem` deliberately excluded from the purge.** Its version string (`...kver.6.17.0-1029-nvidia-64k`) makes it look like a per-kernel package the same way the others are, but `xpmem` is a package name with no kernel version baked in — dpkg can only track one installed version at a time, and `dkms status` already shows it built against `1032`, meaning the `1029` in the version string is a stale build-time artifact from whenever that `.deb` was produced, not a marker of what it actually ships. Confirmed via file manifest before excluding it, not just inferred:

```
root@carlonext:~# dpkg -L xpmem | grep -i 1029
(no output)
```

No `1029`-specific files in the package at all — correctly left untouched, remains installed as-is (still `2604.0.2-1.kver.6.17.0-1029-nvidia-64k` in `dpkg -l`, harmlessly).

**Purge:**

```bash
sudo apt purge -y \
  linux-headers-6.17.0-1029-nvidia-64k \
  linux-image-6.17.0-1029-nvidia-64k \
  linux-modules-6.17.0-1029-nvidia-64k \
  linux-nvidia-6.17-headers-6.17.0-1029 \
  linux-nvidia-6.17-tools-6.17.0-1029 \
  linux-tools-6.17.0-1029-nvidia-64k \
  doca-kernel-repo-26.04-1.0.9.0-6.17.0.1029.nvidia.64k
```

Result: 7 packages removed, **475 MB freed**. Postrm hooks ran cleanly — `update-initramfs` deleted `/boot/initrd.img-6.17.0-1029-nvidia-64k`, and `update-grub` regenerated correctly, finding only `/boot/vmlinuz-6.17.0-1032-nvidia-64k` / `initrd.img-6.17.0-1032-nvidia-64k` (no stray `1029` menu entry).

**Two directories dpkg couldn't remove itself** (conservative behavior — dpkg won't `rmdir` a non-empty directory even when the leftover contents are untracked build residue):

```
dpkg: warning: while removing linux-headers-6.17.0-1029-nvidia-64k, directory '.../scripts/kconfig' not empty so not removed
  (+ scripts/ipe/polgen, scripts/dtc/libfdt, scripts/basic, include/config)
dpkg: warning: while removing linux-modules-6.17.0-1029-nvidia-64k, directory '/lib/modules/6.17.0-1029-nvidia-64k' not empty so not removed
```

Most likely stale DKMS build output from when the modules above were still building against `1029`, before everything moved to `1032`. Since `dkms status` already confirmed nothing registered against `1029`, removed manually:

```bash
sudo find /usr/src/linux-headers-6.17.0-1029-nvidia-64k -maxdepth 0   # confirmed present before removing
sudo find /lib/modules/6.17.0-1029-nvidia-64k -maxdepth 0             # confirmed present before removing
sudo rm -rf /usr/src/linux-headers-6.17.0-1029-nvidia-64k
sudo rm -rf /lib/modules/6.17.0-1029-nvidia-64k
```

**Final verification — all three clean:**

```
root@carlonext:~# ls /lib/modules/
6.17.0-1032-nvidia-64k
root@carlonext:~# ls /usr/src/ | grep 1029
(no output)
root@carlonext:~# dpkg -l | grep 1029
ii  xpmem   2604.0.2-1.kver.6.17.0-1029-nvidia-64k   all   kernel module for user-space process remapping - scripts
```

The `xpmem` line is expected and correct — same package, same version string discussed above, not leftover from an incomplete purge.

**`apt autoremove` for the orphaned X11/desktop stack (libgl1, mesa-vulkan-drivers, xserver-xorg-core, xfonts-base, etc., surfaced as "no longer required" during the purge) — deferred, not run.** This list plausibly matches the unwanted desktop stack §25's revised recommendation already flagged as a side effect of the `nvidia-driver-580-open` metapackage, but that connection wasn't confirmed before this session ended — treat as a separate, still-open cleanup opportunity rather than assuming it's the same thing without checking the package list directly against §25's finding first.

**No action needed on `xpmem`'s version-string cosmetic mismatch** — it will keep reading `...6.17.0-1029-nvidia-64k` in `dpkg -l` until that specific `.deb` is rebuilt/reinstalled upstream; purely cosmetic, doesn't affect DKMS registration (already confirmed against `1032`) or function.

*Status: complete and verified. 475 MB (packages) + residual `/usr/src`/`/lib/modules` directories reclaimed. `apt autoremove` for the X11/desktop leftovers tracked as a separate open item, not part of this pass.*

## 23. CUDA Version Fields — Why Three Different Numbers Are All Correct

Recurring point of confusion worth a permanent reference entry, since it came up directly in review. The checklist shows three different CUDA-related version strings, and none of them are wrong or inconsistent with each other:

| Row | Value | What it actually is |
|---|---|---|
| `CUDA Version (driver)` | `13.0` | `nvidia-smi`'s driver-supported API version. Major.minor only, by design — this field has never been capable of showing an update number, regardless of what's installed. |
| `nvcc (CUDA toolkit)` | `V13.0.88` | nvcc's own independently-versioned component build. Per NVIDIA's CUDA Toolkit component-versioning scheme (independent since CUDA 11), this doesn't share a digit with the toolkit's update-release number — confirmed against NVIDIA's official CUDA 13.0 Update 2 release notes, where `CUDA NVCC: 13.0.88` is the documented, correct value for that exact release. |
| `CUDA Toolkit (meta-pkg)` (added v0.4.17) | `13.0.2-1` | The actual toolkit meta-package version (`cuda-toolkit-13-0`), via `dpkg-query`. The only row where the toolkit's "Update 2" designation is literally visible — matches the original `cuda-repo-ubuntu2404-13-0-local_13.0.2-580.95.05-1_arm64.deb` this was installed from. |

Confirmed independent of whether that original local-repo `.deb` is still on disk (it was deleted per the disk-cleanup pass earlier in this log) — the apt repo it registered lives separately under `/var/cuda-repo-ubuntu2404-13-0-local/`, and installed package version metadata comes from dpkg, not the installer file.

*Status: reference entry, not an action item — logging so this doesn't need re-investigating if the same three-numbers-look-inconsistent question comes up again later.*

## 24. SBIOS Version Discrepancy — Resolved, Same Pattern as §23

Follow-up to §22's HMC bundle cross-check: the bundle screenshot listed `SBIOS: 02.06.06`, but the checklist's `BMC/BIOS (dmidecode)` row has consistently read `00.58.03` (via `dmidecode -s bios-version`) — apparent mismatch, worth checking before assuming either was wrong.

Confirmed via a direct Redfish query against the `UEFI` component (`GET /redfish/v1/UpdateService/FirmwareInventory/UEFI`, `Manufacturer: PEGATRON`) — it also reports `Version: 00.58.03`, exactly matching `dmidecode`. Two independent sources (in-band and out-of-band) agree, so `dmidecode` was never wrong. Per Pegatron directly: **`00.58.03` is their own internal combined BIOS/BMC release/build number** — a vendor packaging version, distinct from `02.06.06`, which is the underlying SBIOS component's own version *within* that Pegatron release. Same shape of distinction as §23's CUDA finding: a release/bundle-level version number and a component-level version number, both correct, tracking different layers — not a bug, not a partial update.

No script change made — `BMC/BIOS (dmidecode)` was already reading the correct, consistent value; nothing was actually missing.

*Status: resolved, no action taken. Logged as a reference entry — same "looks like two numbers disagree, actually two different things" pattern as §23, worth recognizing quickly if it recurs.*

## 25. Production Golden-Image Cloning — UUID / machine-id / SSH Host Key Duplication

Raised from a separate conversation and brought back here for tracking: this reference layout is the source image for production units, which are duplicated via a **ROM writer** (block-level disk cloning), not PXE/`curtin` per-node install (PXE is a possible future direction, not the current path). Block-level cloning duplicates everything on the golden disk byte-for-byte — including several pieces of state that are only supposed to be unique per machine.

**Three separate issues identified, not one:**

1. **Root/boot device addressing (`root=UUID=...` in the kernel cmdline).** The original concern: every cloned unit would boot with an identical filesystem UUID, and the goal was specifically to eliminate `UUID=` as a boot dependency so duplicate/ambiguous UUIDs could never be *why* a node fails to find root — not just a cosmetic fleet-management annoyance.
2. **`machine-id`** — identical across every clone unless addressed.
3. **SSH host keys** — identical across every clone unless addressed; the more serious of the three, since a compromised key on one node could be used to MITM connections to any other node sharing it.

**Resolution differs by issue, and it matters which mechanism applies to which:**

- **Root/boot (#1):** Initially considered `tune2fs -U random` + per-node `fstab`/`grub` regeneration on every clone's first boot. Reconsidered once two hardware facts were confirmed: this platform's M.2 NVMe has a **fixed physical slot/BDF with no reseat risk**, and **every node in the rack shares the same unified hardware design**. Given both, `/dev/disk/by-path/pci-0015:01:00.0-nvme-1-part2` is identical *and correct* on every cloned node — unlike UUID, which is identical but meaningless as a per-node identifier. This turns the fix into a **one-time golden-image edit**, not per-node logic:
  ```bash
  sudo sed -i \
    -e 's|/dev/disk/by-uuid/[0-9a-f-]*[[:space:]]*/[[:space:]]|/dev/disk/by-path/pci-0015:01:00.0-nvme-1-part2 /  |' \
    -e 's|/dev/disk/by-uuid/[0-9A-F-]*[[:space:]]*/boot/efi|/dev/disk/by-path/pci-0015:01:00.0-nvme-1-part1 /boot/efi|' \
    /etc/fstab
  sudo sed -i 's/^#GRUB_DISABLE_LINUX_UUID=.*/GRUB_DISABLE_LINUX_UUID=true/' /etc/default/grub
  sudo update-grub
  grep -q 'root=/dev/disk/by-path' /boot/grub/grub.cfg && echo "OK: by-path root confirmed in grub.cfg"
  ```
  **Confirmed working on this reference node** — post-reboot `/proc/cmdline` shows `root=/dev/nvme0n1p2`, no `UUID=` anywhere. Note: the kernel cmdline shows the resolved device node, not the literal by-path string from `fstab` — that's normal `grub-probe` behavior (resolves the mounted device to its real underlying node), not a sign the by-path config didn't take effect. `/dev/nvme0n1p2`'s own stability (as opposed to `by-path`'s) relies specifically on this platform having exactly one NVMe controller — true here, would need revisiting on a multi-NVMe-controller platform.
  **If the hardware-uniformity assumption ever breaks** (board revision changes M.2 placement, hot-swap bays introduced, a drive physically moved between slots during repair) — this needs to revert to UUID-based addressing with real per-node regeneration.

- **`machine-id` (#2):** No custom mechanism needed. `systemd` auto-regenerates it at boot whenever the file is present but *empty* (not missing) — standard convention already used by Ubuntu's own cloud images. Golden-image prep: `sudo truncate -s 0 /etc/machine-id` before capture.

- **SSH host keys (#3):** No custom mechanism needed either. Ubuntu's `ssh.service` dependency chain regenerates any *missing* host key type automatically at boot. Golden-image prep: `sudo rm -f /etc/ssh/ssh_host_*` before capture.

**Fourth pre-capture check added, different category from the three above — config directory presence, not per-node identity.** Raised from a separate BCM-provisioning pipeline (a chroot-built software image there hit a fatal node-installer error because `/etc/network/interfaces.d/` and `/etc/ntpsec/` didn't exist for it to write generated config into). That specific failure mode is tied to how that other pipeline builds its images (a curated chroot install with its own package-exclusion logic) and isn't expected to reproduce on `carlonext`'s normal bare-metal install — but confirming these directories exist here too, before ROM-writer capture, costs nothing and closes off the same failure class as a precaution:

```bash
ls -la /etc/network/interfaces.d/ /etc/ntpsec/
# if either is missing:
sudo mkdir -p /etc/network/interfaces.d
sudo mkdir -p /etc/ntpsec
```

Unlike `machine-id`/SSH host keys, there's no per-clone regeneration needed here — these are static directories, not per-node identity state, so confirming/creating them once on this reference node before capture is sufficient; no `first-boot-regen` logic required.

**Fifth pre-capture check — `nvidia-fabricmanager`, preinstalled and masked, purely as future-proofing, not a functional need on `carlonext` today.**

**Important distinction, worth being explicit about so this isn't mistaken for contradicting v0.4.6 of `gb300_l10_sw_checklist.sh`:** that checklist correctly and deliberately reclassified "Fabric Manager Service"/"Fabric Manager Version" as `N/A` rather than `MISSING`, because on this rack-scale design fabric management genuinely runs on the NVSwitch tray's own NVOS, never on this compute host, at any bring-up stage. **That functional reality doesn't change here** — `note_na()` in the checklist is a static, hardcoded note, not a live probe of whether the package happens to be installed, so pre-installing (and masking) `nvidia-fabricmanager` has zero effect on the checklist's output or correctness either way.

**The actual reason to do this:** if `carlonext`'s captured layout is ever re-tar'd and fed into `cm-create-image` as a BCM software-image source (the way a separate reference host, `maxQ106`, already has been for a different rack's provisioning), the build's `--dgx-type` finalize stage will **unconditionally** attempt `systemctl disable nvidia-fabricmanager` — and fail the entire build if the unit doesn't exist to disable, regardless of source pipeline. This isn't specific to how `maxQ106` was built; it's inherent to `cm-create-image` itself. Pre-installing and masking the package now means that failure (and the chroot-based fix required to resolve it after the fact) never has to be rediscovered against `carlonext` later.

**Version must match this reference layout's actual driver, not be copied from the other rack's fix:** `carlonext` runs driver `580.173.02` (installed via `.run`, §7) — different from the other rack's DKMS-built `580.126.20`. **Concrete source confirmed:** NVOnline's `nvidia-driver-local-repo-ubuntu2404-580.173.02_1.0-1_arm64.deb` local-repo package contains a matching `nvidia-fabricmanager` build for this exact driver branch.

**Actual commands run on `carlonext` (real transcript, not a draft):**

```bash
sudo dpkg -i nvidia-driver-local-repo-ubuntu2404-580.173.02_1.0-1_arm64.deb
# GPG key warning appeared here (see below) — not resolved, install proceeded
# via direct dpkg -i of the individual .deb rather than through apt/the repo.

sudo dpkg -i /var/nvidia-driver-local-repo-ubuntu2404-580.173.02/nvidia-fabricmanager_580.173.02-1ubuntu1_arm64.deb
sudo systemctl mask nvidia-fabricmanager
sudo apt-mark hold nvidia-fabricmanager
ls -la /etc/systemd/system/nvidia-fabricmanager.service   # confirmed -> /dev/null
```

**Note: package name is `nvidia-fabricmanager`, no `-580` suffix** — this local-repo package doesn't follow the BCM-side `nvidia-fabricmanager-580` naming convention (different rack, different install path). `apt-mark hold` should target `nvidia-fabricmanager` only. **Confirmed correctly applied on `carlonext`:** an earlier run of this fix accidentally held the wrong name (`nvidia-fabricmanager-580`, never installed on this host) alongside the correct one; `apt-mark unhold nvidia-fabricmanager-580` cleared it, and `apt-mark showhold` now correctly shows only `nvidia-fabricmanager` (plus three pre-existing, unrelated kernel holds — `linux-headers-nvidia-64k-hwe-24.04`, `linux-image-nvidia-64k-hwe-24.04`, `linux-nvidia-64k-hwe-24.04` — present before this session's work, purpose not documented here, worth confirming intentional next time this reference layout is touched).

**Two things observed worth recording, not yet fully explained:**
- **GPG keyring step was skipped** (the `dpkg -i` of the repo package itself warned that its GPG key wasn't installed, with a suggested `cp .../keyring.gpg /usr/share/keyrings/` fix) — install proceeded anyway via direct `dpkg -i` of the individual package, bypassing `apt`'s repo/signature mechanism entirely rather than resolving the warning. Fine for this one-shot manual install; if this repo is ever used with real `apt-get install`/`apt update` in the future (rather than manual `dpkg -i`), the keyring step should actually be done first.
- **`Could not execute systemctl: ... at /usr/bin/deb-systemd-invoke line 148` during the `nvidia-fabricmanager` package's own postinst.** This is real bare-metal hardware, not a chroot (unlike the known, explained `cm-chroot-sw-img` PID1/D-Bus limitation from 6k/6o) — so this warning is currently unexplained and worth a quick look (shell environment, PATH, or something else affecting `deb-systemd-invoke`'s ability to call `systemctl` in this session specifically) rather than assumed harmless just because the subsequent manual `mask` step worked around it.

**This install also confirms exactly why the checklist's new defense-in-depth check (below) is worth having, not just theoretical:** the package's postinst created `/etc/systemd/system/multi-user.target.wants/nvidia-fabricmanager.service → .../nvidia-fabricmanager.service` **before** the manual mask step ran — i.e., **this package enables itself by default on install.** If the explicit `mask` step is ever skipped or forgotten on a future rebuild of this reference layout, the service would sit enabled and ready to start at boot, which is exactly the real-world misconfiguration risk this check exists to catch.

`gb300_l10_sw_checklist.sh` v0.4.18 adds this check — reports `OK` if installed and correctly masked, flags `CHECK`/"NEEDS REVIEW" (not a hard `MISSING`) if the package is present but *not* masked, and correctly treats the package's absence as fine (`N/A`, precaution is optional) rather than a problem. Run the checklist after applying this fix to confirm it landed correctly, rather than relying on the manual `ls -la` alone.

**Deliverables produced** (not just discussed — actual files, delivered as artifacts):
- `golden-image-prep-checklist.md` — the full one-time prep sequence to run on this reference node immediately before ROM-writer capture (by-path fstab/grub edit, machine-id truncation, SSH host key removal, config directory presence check, fabricmanager preinstall+mask, and why the EFI partition's own volume ID is deliberately left alone), plus what happens automatically on each clone's actual first boot.
- `first-boot-regen.sh` / `first-boot-regen.service` — a self-triggering, self-disabling systemd oneshot unit (`ConditionPathExists=!/var/lib/first-boot-regen-done`) that fires once per cloned node. After the by-path decision, this no longer does anything boot-critical — it only gives each node a genuinely unique filesystem UUID for asset-tracking/tooling clarity (no `fstab`/`grub` edit, no reboot, since boot no longer depends on that value at all).

**Zero production-line touch required** — every regeneration step happens automatically on each unit's own first boot; the only manual work is the one-time golden-image prep on this reference node before the ROM writer captures it.

**Open items — not yet validated end-to-end:**
- Root/boot by-path change is confirmed working on *this* node's own reboot — but the full first-boot sequence (regen service, `machine-id`, SSH host keys) hasn't yet been exercised against an actual ROM-writer-cloned unit. First real clone should be watched through the whole sequence before trusting this at scale.
- Whether the ROM writer performs an offline block-level copy (assumed) vs. some other mechanism that might behave differently — not independently confirmed.
- "Unified hardware design across the rack" — the load-bearing assumption for the entire by-path approach — hasn't been explicitly confirmed by whoever owns the hardware BOM/board revisions, only assumed reasonable.
- Config directory presence (`interfaces.d/`, `ntpsec/`) — added as a precaution, not because a failure was observed on `carlonext` itself; not yet independently confirmed whether these were ever actually missing here.

*Status: designed, partially validated (root/boot confirmed on this node), not yet validated end-to-end against a real clone. Do not treat as production-proven until the first actual ROM-writer unit has been walked through the full first-boot sequence.*

## 25a. BCM Image Export — `maxQ20rc4-1029-doca341-baseos.tgz` (2026-09-02)

**Deliberate divergence from §25's design, logged explicitly so this isn't mistaken for an oversight later:** §25 designed a golden-image path that truncates `machine-id` and removes SSH host keys pre-capture, relying on `systemd`/`ssh.service` to regenerate unique values on each clone's first boot. This capture **does not do that** — `machine-id` and all six `ssh_host_*` key files were deliberately left live in the archive, and `/home` was left in its current state rather than stripped, because this reference layout also carries diag-team preset accounts and diagnostic test data under `/home` that need to persist across the capture. This is a conscious choice for this specific image, not a reversal of §25's general design — if a future image built from this same pipeline needs the unique-per-clone identity behavior, apply §25's `golden-image-prep-checklist.md` steps before capture; they weren't run here.

**Capture command:**
```bash
sudo mkdir -p /root/bcm-image-export
sudo tar --numeric-owner --xattrs --acls -czpf /root/bcm-image-export/maxQ20rc4-1029-doca341-baseos.tgz \
  --exclude='./proc' --exclude='./sys' --exclude='./dev' --exclude='./run' \
  --exclude='./tmp' --exclude='./mnt' --exclude='./media' --exclude='./lost+found' \
  --exclude='./root/bcm-image-export' \
  -C / .
```
Result: `10,585,047,328` bytes (~9.9 GiB) compressed, `172,523` archive members, from a `/` that `df` showed at ~17.4G used pre-capture — a reasonable compression ratio for a mixed binary/text root filesystem.

**Pre-capture consistency check — by-path root config confirmed intact end-to-end, not just at the `fstab` level (§25):**
```
/etc/fstab                       → /dev/disk/by-path/pci-...-nvme-1-part2  /
/etc/default/grub                → GRUB_DISABLE_LINUX_UUID=true
/boot/grub/grub.cfg (generated)  → linux /boot/vmlinuz-... root=/dev/nvme0n1p2 ro console=tty0
```
All three agree — no `UUID=` anywhere in the boot chain. This confirms §25's by-path decision is fully baked into the *generated* GRUB config that ships inside this tarball, not just the source `fstab`/`grub` files — worth checking specifically since `grub.cfg` is generated at `update-grub` time and could in principle drift from the source config if regenerated under different conditions.

**Post-capture validation:**
| Check | Command | Result |
|---|---|---|
| Archive not corrupt / member count sane | `tar -tzf ... \| wc -l` | `172523` members, listed cleanly, no read errors |
| `machine-id` present as intended (not excluded) | `tar -tzf ... \| grep '^\./etc/machine-id'` | Present ✅ |
| SSH host keys present as intended (not excluded) | `tar -tzf ... \| grep '^\./etc/ssh/ssh_host'` | All 6 files (3 key types × priv/pub) present ✅ |

**Checked and found to need no action — `/var/cache/apt/archives`:** confirmed already empty (`ls` shows only `lock` and an empty `partial/`) as a result of the `apt clean` run during §22a's disk-cleanup pass. No exclude needed for this path on this capture; would only matter if `apt clean` hadn't already been run beforehand.

**Not excluded, not yet independently confirmed as intentional-and-reviewed beyond the diag-account rationale above:**
- `/var/log` (234M at last check) — this node's own bring-up-session logs are baked into the image as-is. Not wrong, but every clone will carry `carlonext`'s own dmesg/auth/syslog history from the bring-up process. Acceptable for now; worth excluding on a future re-capture if that ever matters (e.g. log-size creep across many clones, or wanting a genuinely blank audit trail per unit).

**Open items:**
- This tarball has been captured and internally validated (tar integrity, expected-file presence, by-path consistency) but **not yet run through `cm-create-image`** or provisioned onto an actual node — that end-to-end pass is still outstanding.
- Because `machine-id`/SSH host keys are static in this image (by design, see above), **every node cloned from this image will share the same `machine-id` and SSH host keys** unless something downstream (BCM's own provisioning, a different finalize step) regenerates them per node. This is the opposite tradeoff from §25's design and needs to be a conscious decision at the provisioning-pipeline level, not just this capture step — confirm whether `cm-create-image`/the node-install process has its own regeneration mechanism before cloning multiple units from this image, since relying on shared SSH host keys across many production nodes is a real MITM/fingerprint-collision exposure if uncaught.

*Status: image captured and validated at the tar level. Not yet fed into `cm-create-image` or tested against a real provisioned node — treat as a candidate image, not a confirmed-working one, until that pass completes.*

## 25b. `cm-create-image` Finding — NVIDIA Driver Packages Install Unpinned, Silently Drift Off the §0 Target Version (2026-09-08)

**Symptom:** running `cm-create-image` end-to-end against `maxQ20rc4-1029-doca341-baseos.tgz` produces a chroot where `nvidia-open-580`, `nvidia-driver-580-open`, `libnvidia-compute-580`, and the rest of the `580`-branch package set install correctly in terms of dependency resolution, but land at whatever NVIDIA's CUDA network repo currently considers the newest `580.x` build (observed: `580.178.04`) — **not** the `580.173.02` required by the NVOnline 2.0.0RC4 matrix in §0. This is a silent drift, not an install failure: `cm-create-image` reports `[OK]` at every stage, and nothing in the log distinguishes a correctly-pinned install from an accidentally-latest one.

**Root cause, confirmed by reading `/var/log/cm-create-image-<image>.log` line-by-line:** the CM package install step invokes `apt-get install` with a **bare package-name list, no version pins**, e.g.:
```
apt-get install --yes --assume-yes --allow-unauthenticated -o DPkg::Options::="--force-confnew" \
  nvidia-open-580 libnvidia-nscq nvidia-driver-580-open nvidia-imex nvidia-persistenced \
  libnvidia-compute-580 libnvidia-gl-580 libnvidia-cfg1-580 ... [full list in log]
```
The CUDA repo (`cm-cuda-ubuntu2404-sbsa.list`) is added immediately before this step and its keyring (`cm-cuda-archive-keyring.gpg`) is deliberately deleted immediately after (`Removing CUDA repo` / `rm -rf .../cm-cuda-archive-keyring.gpg` in the log) — meaning **whichever version apt resolves as "candidate" at that exact moment becomes permanently baked into the image**, with no re-check, no pin, and no way to reproduce the same result on a later rebuild if NVIDIA has published a newer `580.x` patch in the interim. This is a moving target disguised as a deterministic build step.

**Validated separately on bare-metal (`carlonext`, this same day) that version pinning must account for more than a simple `=580.173.02` suffix** — the naive approach fails with cross-repo dependency conflicts. Confirmed working method:

1. Ubuntu-ports and NVIDIA's own CUDA repo package the *same* nominal driver version with **different suffixes** (`580.173.02-0ubuntu0.24.04.1` from ports vs. `580.173.02-1ubuntu1` from NVIDIA's repo). Mixing suffixes across dependent packages (e.g. `libnvidia-compute-580` from one source depending on `nvidia-persistenced >= X-1ubuntu1` but only the ports build being installed) produces unmet-dependency errors that look like version conflicts but are really source-mismatch conflicts. **Fix: pin every `580`-branch package to the NVIDIA-repo suffix (`-1ubuntu1` for this release) consistently, not just the bare version number.**
2. `libnvidia-nscq` and `nvidia-imex` are available as **both** Ubuntu-ports `-580`/`-580-server`-suffixed virtual packages *and* as bare-named packages directly from NVIDIA's own repo. The `-580-server` variant `Conflicts:` with the `-580` (non-server/open) branch's `nvidia-kernel-common-580` — installing the wrong one blocks the whole open-branch install with a `Conflicts: nvidia-kernel-common` error that doesn't obviously point at `libnvidia-nscq`/`nvidia-imex` as the cause. **Fix: use the bare `libnvidia-nscq=580.173.02-1ubuntu1` / `nvidia-imex=580.173.02-1ubuntu1` package names from NVIDIA's repo, not the Ubuntu-ports `-580`-suffixed virtual-package providers.**
3. `nvidia-persistenced` and `nvidia-compute-utils-580` are the same underlying package under two names (the former is a virtual package provided by the latter) — pin `nvidia-compute-utils-580` explicitly; pinning only `nvidia-persistenced` by itself does not reliably pin the version.
4. `dkms` itself has a minimum-version dependency from `nvidia-dkms-580-open` (`>= 3.1.8` for this release) that Ubuntu's stock `noble` `dkms` package (`3.0.11-1ubuntu13`) does not satisfy. Pin `dkms` explicitly to the lowest available version that clears the minimum (`1:3.2.1-1` from NVIDIA's repo) rather than accepting whatever the dependency solver reaches for, to avoid an unnecessary jump to `dkms`'s newest release (`1:3.4.1-1ubuntu1` at time of writing) as a side effect.

**Full validated pin list** (confirmed installing cleanly via `aptitude install` with no unmet dependencies, on `carlonext` bare-metal, 2026-09-08):
```
nvidia-open-580=580.173.02-1ubuntu1
nvidia-firmware-580=580.173.02-1ubuntu1
libnvidia-gpucomp-580=580.173.02-1ubuntu1
libnvidia-egl-xcb1=1.0.5-1ubuntu1
libnvidia-egl-xlib1=1.0.5-1ubuntu1
libnvidia-egl-wayland1          # unversioned/no 580-branch coupling, latest is fine
libnvidia-egl-gbm1              # unversioned/no 580-branch coupling, latest is fine
nvidia-compute-utils-580=580.173.02-1ubuntu1   # also satisfies nvidia-persistenced
libnvidia-nscq=580.173.02-1ubuntu1             # bare NVIDIA-repo package, not libnvidia-nscq-580
nvidia-imex=580.173.02-1ubuntu1                # bare NVIDIA-repo package, not nvidia-imex-580
libnvidia-compute-580=580.173.02-1ubuntu1
libnvidia-gl-580=580.173.02-1ubuntu1
libnvidia-cfg1-580=580.173.02-1ubuntu1
libnvidia-common-580=580.173.02-1ubuntu1
libnvidia-extra-580=580.173.02-1ubuntu1
libnvidia-decode-580=580.173.02-1ubuntu1
libnvidia-encode-580=580.173.02-1ubuntu1
libnvidia-fbc1-580=580.173.02-1ubuntu1
xserver-xorg-video-nvidia-580=580.173.02-1ubuntu1
nvidia-dkms-580-open=580.173.02-1ubuntu1
nvidia-driver-580-open=580.173.02-1ubuntu1
nvidia-kernel-source-580-open=580.173.02-1ubuntu1
nvidia-kernel-common-580=580.173.02-1ubuntu1
nvidia-modprobe=580.173.02-1ubuntu1
libxnvctrl0=580.173.02-1ubuntu1
dkms=1:3.2.1-1
```
followed by locking every pinned package in place so a later `apt upgrade` (see §26 open item on this) can't silently move any of them:
```bash
sudo apt-mark hold \
  nvidia-open-580 \
  nvidia-firmware-580 \
  libnvidia-gpucomp-580 \
  libnvidia-egl-xcb1 \
  libnvidia-egl-xlib1 \
  nvidia-compute-utils-580 \
  libnvidia-nscq \
  nvidia-imex \
  libnvidia-compute-580 \
  libnvidia-gl-580 \
  libnvidia-cfg1-580 \
  libnvidia-common-580 \
  libnvidia-extra-580 \
  libnvidia-decode-580 \
  libnvidia-encode-580 \
  libnvidia-fbc1-580 \
  xserver-xorg-video-nvidia-580 \
  nvidia-dkms-580-open \
  nvidia-driver-580-open \
  nvidia-kernel-source-580-open \
  nvidia-kernel-common-580 \
  nvidia-modprobe \
  libxnvctrl0 \
  dkms
```
(`libnvidia-egl-wayland1` and `libnvidia-egl-gbm1` deliberately excluded — per the comments above, they have no `580`-branch version coupling, so holding them isn't necessary.)

**Verify the holds actually took:**
```bash
apt-mark showhold | grep -E "nvidia|^dkms$|libxnvctrl0"
```
Should list all 23 package names above, nothing more, nothing missing.

**No action needed on this reference layout, `carlonext`, or the `maxQ20rc4-1029-doca341-baseos.tgz` tarball itself** — `carlonext` is already correctly pinned at `580.173.02` (§7, §16a), and the tarball's own contents are not where the drift originates. Confirmed from the `cm-create-image` log timestamps: the NVIDIA driver packages are **not** part of the tarball's captured filesystem state — they get installed fresh, from scratch, every time `cm-create-image` runs, via the "Installing CM packages" step's own `apt-get install nvidia-open-580 ...` command. That command is generated from a config file that lives entirely on the BCM head node (`bcm11-headnode`), separate from anything this build log or the tarball controls — most likely `/cm/local/apps/cluster-tools/config/UBUNTU2404-config-cm.xml` or an equivalent CM package list, which is out of scope for this document and needs a different owner to action.

**Recommendation — action needed in that head-node pipeline config, tracked here only as a cross-reference:** each `nvidia-*`/`libnvidia-*`/`xserver-xorg-video-nvidia-580`/`dkms` entry in that config needs updating to carry the exact pinned version string above, so that re-running `cm-create-image` at any future date reproducibly lands on `580.173.02`, matching §0, instead of whatever NVIDIA's repo happens to consider newest at build time. Until that config changes, **every future `cm-create-image` run against this or any similarly-built tarball will need the same manual post-build correction** — this finding doesn't self-resolve just because `carlonext`/the tarball are correct.

**Not addressed here — kernel version:** this finding is scoped to driver/module *package version* pinning only. The kernel version target (`6.17.0-1029-nvidia-64k` per §0) is unchanged by this finding and is being tracked separately.

**Revised recommendation (2026-09-08, supersedes the head-node-config-pin recommendation above as the primary fix):** after a full day spent chasing this exact class of problem inside the `cm-create-image` chroot — cross-repo suffix mismatches, virtual-package traps (`libnvidia-nscq`/`nvidia-imex` vs. their `-580`/`-580-server` variants), the `nvidia-persistenced`/`nvidia-compute-utils-580` alias confusion, `dkms` minimum-version pins, and the `nvidia-driver-580-open` metapackage unexpectedly pulling in a full desktop/X11 stack — pinning apt versions *inside the BCM chroot* has proven fragile and expensive in wall-clock time, repeatedly, not just once. The head-node-config pin fix above would still work if implemented, but it keeps this whole fragile mechanism in the critical path of every future image build.

**The more robust fix: don't install the NVIDIA driver via apt at `cm-create-image` time at all.** Ensure `580.173.02` (or whatever the current target is) is already correctly installed on the reference host (`carlonext`) via the `.run`-installer method (§7) **before** the next `-a` capture/re-tar, so the driver — kernel module, DKMS registration, and userspace libraries — is already present and correct in the tarball's filesystem state itself. If the driver is already there when `cm-create-image` unpacks the tarball, whatever the `UBUNTU2404-dist-extrapackages.xml`/CM package list's unpinned `apt-get install nvidia-open-580 ...` step does or doesn't successfully install becomes irrelevant — at worst it's wasted build time on packages the image doesn't actually need to function, not a correctness risk.

**This pattern is already independently validated elsewhere** — the parallel `maxQ106`/`baseos-1014-doca321` reference layout (a separate rack, tracked in `session-summary.md`) uses exactly this approach: its validated driver (`580.126.20`) is baked into the tarball from the original `.run`-installer bring-up, and its `cm-create-image` build has never needed to depend on the apt-based NVIDIA package list succeeding. Today's `baseos-1029-doca341` line is the outlier, not the norm, in trying to get the driver installed via apt inside the BCM pipeline.

**Practical next step:** before the next capture of this reference layout, confirm `carlonext`'s `580.173.02` install (already done and validated, §7/§16a) is what gets tar'd, and treat the CM/dist package list's `nvidia-*-580` install attempt inside `cm-create-image` as a harmless no-op to ignore going forward — not something to fix or pin. The head-node config pin fix remains a valid *secondary* improvement if someone wants build logs to stop showing version-drift noise, but it's no longer the recommended primary path.

**How to actually do this, step by step:**

1. **On `carlonext`, re-verify the driver/kernel state matches the target before touching anything else** — don't assume it's still correct just because it was validated earlier in this document; today's own session showed how easily this drifts:
   ```bash
   uname -r                          # expect 6.17.0-1029-nvidia-64k (or current target, see §0)
   modinfo nvidia | grep ^version    # expect 580.173.02
   nvidia-smi                        # confirm all GPUs healthy, no NVML errors
   dkms status                       # confirm single-kernel, no stray entries
   dpkg -l | grep -E "nvidia-open-580|nvidia-driver-580-open"  # expect: not installed via apt at all —
                                                                 # driver should only exist via the .run/DKMS path (§7), matching maxQ106's pattern
   ```
   If any of these are wrong, fix them on `carlonext` directly (re-run the `.run` installers per §7, or whatever correction is needed) and re-run the full `gb300_l10_sw_checklist.sh` checklist before proceeding — do not capture a tarball from a known-drifted state.

2. **Run the disk-cleanup pass (§22a) again if it's been a while since the last one** — stale local-repo packages, apt cache, and swap-file bloat all get baked into the tarball verbatim if skipped:
   ```bash
   apt-get clean
   # + whatever else §22a's specific cleanup steps cover
   ```

3. **Capture the tarball using the same method as §25a** (adjust the filename/version tag for whatever this capture represents — e.g. bump `rc4` or the date if this is meant to be a distinct, trackable artifact from the original):
   ```bash
   sudo mkdir -p /root/bcm-image-export
   sudo tar --numeric-owner --xattrs --acls -czpf /root/bcm-image-export/<new-tarball-name>.tgz \
     --exclude='./proc' --exclude='./sys' --exclude='./dev' --exclude='./run' \
     --exclude='./tmp' --exclude='./mnt' --exclude='./media' --exclude='./lost+found' \
     --exclude='./root/bcm-image-export' \
     -C / .
   ```

4. **Run §25a's post-capture validation** (tar integrity, member count, `machine-id`/SSH-host-key presence per whatever identity policy is intended this time) before trusting the new archive.

5. **Feed the new tarball into `cm-create-image`** exactly as before (this time dropping `--no-cm-cuda-repo`, per this morning's original finding, unless §8.2's caveat in `session-summary.md` changes that decision):
   ```bash
   cm-create-image -a /root/bcm-image-export/<new-tarball-name>.tgz \
     -n <new-image-name> \
     --dgx-type dgx_gb300 \
     -s
   ```

6. **After the build completes, verify the driver survived intact** — this is the actual proof the strategy worked:
   ```bash
   cm-chroot-sw-img /cm/images/<new-image-name>
   dkms status                       # expect nvidia/580.173.02 (or current target) against the target kernel, untouched
   dpkg -l | grep -E "nvidia-open-580|nvidia-driver-580-open"  # if these got installed via the CM/dist package
                                                                 # list's unpinned apt step, that's the expected
                                                                 # harmless no-op from §25b — check the DKMS-registered
                                                                 # version above is still correct regardless
   exit
   ```
   If `dkms status` still shows the correct, `carlonext`-validated version after the build, the strategy is confirmed working — the tarball's baked-in driver survived `cm-create-image`'s own apt activity untouched, exactly as `maxQ106` already demonstrates.

**Operational note (2026-09-08): `cm-chroot-sw-img` exit does not reliably unmount everything.** After exiting a chroot session (`exit`/Ctrl-D), always check `mount | grep <image-name>` before running further `cm-create-image`/`cm-chroot-sw-img` operations — `dev`, `run`, `proc`, `sys`, `efivarfs`, and a per-session `/var/tmp/<random>` tmpfs scratch dir (created by apt) have all been observed still mounted after exit, more than once today. Unmount manually if found. The `/var/tmp/<random>` one can report "target is busy" if a leftover process still has it open (`fuser -vm <path>` to check); low-risk to leave if nothing obviously wrong is holding it — it doesn't affect the image's actual filesystem content, just head-node housekeeping.

## 25c. Provisioned Rack Validated — `rack08` (18× nodes), 2026-09-08 — ✅ full health-check pass

Full `maxQ-1029-doca341` category (`baseos-1029-doca341`) provisioned across `rack08node01`–`rack08node18`. All 18 nodes show `[UP]` with no health-check failure flag, in contrast to the same-day `rack01`/`maxQ-1014-doca321` deployment, which shows all 18 nodes flagged `health check failed` (expected — that's the separate, already-documented `nsswitch.conf`/chrony gaps tracked in `session-summary.md`, unrelated to this image).

Spot-checked `rack08node01` via `latesthealthdata`: **every measurable PASS**, including the three that were the actual focus of today's work:
- `ntp`: PASS — chrony fix (installed fresh in this image, §26) confirmed working on real hardware, not just in the chroot
- `ldap`: PASS — no `nsswitch.conf`-style regression on this image (never applied here)
- `gpu_health_nvlink` / `gpu_health_overall`: PASS on all 4 GPUs — this rack's NVSwitches already GFM-configured; also confirms `580.173.02` + `6.17.0-1029-nvidia-64k` is solid on production hardware (all `gpu_health_driver`/`_mem`/`_thermal`/`_pcie`/`_sm`/`_nvswitch_fatal`/`_nvswitch_non_fatal` checks PASS across gpu0-gpu3), closing the loop on the `os_get_euid` kernel-crash investigation from earlier in this document — that was specific to the `carlonext` bring-up host's own churned state that day, not a property of this driver/kernel pairing in general.

**This is the first end-to-end real-hardware confirmation that `baseos-1029-doca341`, built via `cm-create-image` per §25a-§25b's process (unpinned NVIDIA apt install left as a harmless no-op, driver correctness relying on whatever DKMS state the tarball/build produced), works correctly at scale.** Recommend re-running `latesthealthdata` across the remaining 17 nodes (not just node01) before considering the rack fully signed off, but this single spot-check plus the clean `[UP]`/no-failure summary across all 18 is a strong result.

## 25d. Post-Handoff Trade-offs (Not Yet Resolved) — 2026-09-11

Two separate issues found while getting `rack03`/`rack08` (`baseos-1029-doca341`) ready for diag testing after handoff to the diag team's own network. Both share the same shape: **the correct fix for one problem breaks a different, real signal** — neither is a clean win, and neither should be closed out without a deliberate decision.

**1. LDAP/`nslcd` timeout fix breaks the `ldap` health check.**
Root cause (confirmed, `rack08node01`/`.137`, 2026-09-11): `nslcd` stays configured to bind `ldaps://ldapserver/` (the BCM head node), unreachable once the rack is off the cluster network. Every SSH login/PAM check triggers a live LDAP bind attempt that fails slowly (~15s), since `pam_ldap.so` is wired into `common-account`/`common-auth`/`common-session`. Fix (stop `nslcd`, strip `pam_ldap.so`, `nsswitch.conf` → `files`-only, preserving `cmsupport` as a local account first) eliminates the delay — but same class of regression as §8.8/`session-summary.md`: anything that specifically checks LDAP-backed resolution (not just `cmsupport`'s existence, which the local-account preservation covers) will read as broken. **Considered, not yet decided: disable the `ldap` health check itself for handed-off racks**, rather than leaving it falsely red. Real trade-off, not a fix — the check would report healthy without LDAP integration actually being present or working, which is accurate to the (deliberately) off-cluster state, but removes a genuine signal for anyone who might expect it. Needs a decision: does anything actually consume this health signal for handed-off racks, or is it purely cosmetic dashboard noise once a rack leaves the cluster? Mechanism (once decided): BCM likely supports per-category/per-node health-check exclusion (`healthconf` object) — exact `cmsh` syntax not yet verified against this cluster's BCM version, confirm with `help set` inside the object rather than assuming.

**2. `cuda-dcgm.service` blocks `onediagfieldmn`'s module-unload step.**
Root cause (confirmed, `rack08node15`, 2026-09-11): `nv-hostengine` (DCGM's daemon, `cuda-dcgm.service`, auto-starts via systemd on this image) calls `nvmlInit()` on startup and holds `/dev/nvidiactl`+`/dev/nvidia0-3` open for as long as it runs — true whether idle or busy. `onediagfieldmn.r9.343.7`'s setup step does a hard `rmmod nvidia_uvm` with no DCGM-awareness and no graceful release request; when it fails, the whole diag client process dies via `die()`/`exit 1` **before ever attempting to register with the GDM sync server** — which is what actually caused the `SYNC_CLIENT_NOT_REGISTERED` failures chased at length earlier this session (multiple wrong theories ruled out first: multi-NIC binding, protocol fingerprint mismatch, firewall/ufw, AppArmor — all dead ends; this was the real cause). Fix: stop `cuda-dcgm.service` on all nodes before each diag run, restart after (now automated, see `rack_lifecycle.sh` `pre-diag`/`post-diag`). **Trade-off:** the `cuda-dcgm` health check (and any real GPU monitoring) is genuinely down for the duration of every diag run, not just falsely reported — this one isn't cosmetic like #1, it's an actual monitoring gap while diag is active. `post-diag` restarting it closes the gap afterward, but anyone relying on continuous DCGM monitoring needs to know it's intentionally offline during diag windows.

**Validated end-to-end on `rack01node01` (still BCM-reachable, useful as a safe practice target), 2026-09-11.** `pre-diag`: `cuda-dcgm` → `FAIL` (`"nv-hostengine is not running, while there is /dev/nvidia0"` — a well-built check, distinguishes "correctly absent" from "should be running"). **Wider blast radius than initially scoped:** `gpu_health_hostengine` and `gpu_health_overall` (the aggregate rollup) both drop to `UNKNOWN` too (`"Unknown value from DCGM: 1"`) — they query DCGM directly for GPU status and simply can't get an answer with `nv-hostengine` down, rather than failing outright. So the real monitoring gap during a diag window is 3 checks, not 1. `post-diag`: all three cleanly returned to `PASS` after restart, confirming the automation's stop/restore cycle is correct.

**Operational note from this practice run: `latesthealthdata` immediately after `pre-diag`/`post-diag` can show a stale, pre-change snapshot** (BCM's health-check daemon runs on its own periodic cycle, not on-demand) — an immediate check after `pre-diag` showed `cuda-dcgm: PASS, Age: 1m 34s` even though the service had genuinely just been stopped, which would have looked like the fix silently failed if taken at face value. Wait for a fresh cycle (`Age` reset to a small number) before trusting the result either direction. A force-immediate-recheck `cmsh` command may exist for this BCM version but wasn't found/confirmed this session — worth checking `help` under the device object if faster verification is needed later.

**Open question for both:** does the earlier "known-good" state (DCGM apparently didn't block an ubergemm test run previously) mean `cuda-dcgm.service` wasn't yet configured to auto-start on whatever system that test ran on, or was that test invoked through `dcgmi` itself (DCGM-aware, no external device-handle conflict) rather than a separate tool like `onediagfieldmn`? Not confirmed — see conversation notes; worth checking `systemctl status cuda-dcgm.service` uptime/enabled-state history if this needs a definitive answer.

**Not yet decided, either item:** whether these trade-offs are acceptable as standing behavior for every future rack handoff, or whether one/both need a different resolution (e.g., getting `onediagfieldmn` to gracefully request DCGM release its device handles instead of a hard `rmmod`, rather than stopping DCGM as a blunt workaround). Track alongside the `finalize` lifecycle stage in `rack_lifecycle.sh`, which is also still undecided pending clarification on what "ready for production/customer" actually requires.

## 25d. GA Reference Layout Recapture — `maxQ20GA-1032-doca341-baseos.tgz` (2026-09-16)

**Why:** the original `maxQ20rc4-1029-doca341-baseos.tgz` (§25a) reflects the RC4-era `580.173.02` driver on kernel `1029`. Since §0a/§7g's full GA reconciliation, `carlonext` itself has moved to `580.173.10` on kernel `1032` plus the CX8/BF3 firmware fix (§10a) and three disk-hygiene passes (§22a/§22b/§22c). This capture brings the reference tarball in line with what's actually validated on the reference host, rather than continuing to hand out an RC4-era image.

**Capture command — identical to §25a's method, same output path, effectively replacing the original file in place:**
```bash
sudo tar --numeric-owner --xattrs --acls -czpf /root/bcm-image-export/maxQ20rc4-1029-doca341-baseos.tgz \
  --exclude='./proc' --exclude='./sys' --exclude='./dev' --exclude='./run' \
  --exclude='./tmp' --exclude='./mnt' --exclude='./media' --exclude='./lost+found' \
  --exclude='./root/bcm-image-export' \
  -C / .
```
Renamed immediately after to reflect what it actually is:
```bash
mv /root/bcm-image-export/maxQ20rc4-1029-doca341-baseos.tgz /root/bcm-image-export/maxQ20GA-1032-doca341-baseos.tgz
```
**Post-capture validation — confirmed, same checks as §25a:**
```
tar -tzf .../maxQ20GA-1032-doca341-baseos.tgz | wc -l                          → 186,001 members, listed cleanly, no read errors
tar -tzf .../maxQ20GA-1032-doca341-baseos.tgz | grep '^\./etc/machine-id'      → present ✅
tar -tzf .../maxQ20GA-1032-doca341-baseos.tgz | grep '^\./etc/ssh/ssh_host'    → all 6 files present ✅
```
Member count is up from the original's `172,523` — expected, given everything accumulated since (GA driver/IMEX/FM reinstall, disk-hygiene passes that also *added* artifacts like this session's `hosts.ini` template, not just removed things).

**Correction: this ended up as two captures, not one — worth being precise about which is authoritative.** The first capture (further above) was taken, then renamed via `mv` from the original `1029`-named path. A second, genuinely fresh `tar` run was then executed directly against the final `maxQ20GA-1032-doca341-baseos.tgz` path — **after** §7h's boot-verification of `nvidia-persistenced` — which overwrote the renamed file. This second capture is authoritative: it has the confirmed-good, actually-boot-tested persistence behavior baked in directly, rather than being true of this file only by inference from a test run against the live host after the file already existed. The validation above is against this second, final capture.

**Note on the original file:** this reused §25a's exact original path before renaming, which means the original RC4-era tarball at that path was overwritten during capture, not preserved as a separate artifact. `rack08` (§25c) is unaffected — it was already provisioned from the original weeks earlier — but if the original `1029`-era tarball itself is ever needed again (e.g. to diff against, or re-verify exactly what `rack08` was built from), it no longer exists at this path. Not confirmed whether a separate copy survives inside BCM's own imported-image store independent of this raw file.

**Follows §25b's validated strategy, not the drift risk it originally found.** §25b's hard-won conclusion was: bake the driver in via the `.run` installer before capture, so `cm-create-image`'s own unpinned `apt-get install nvidia-open-580 ...` step becomes a harmless no-op instead of a silent version drift. Confirmed this capture does exactly that, checked directly rather than assumed:
```
uname -r                                                      → 6.17.0-1032-nvidia-64k ✅
modinfo nvidia | grep ^version                                → 580.173.10 ✅
nvidia-smi                                                     → all 4 GPUs healthy, no NVML errors ✅
dkms status                                                    → nvidia/580.173.10 against 1032 only, no stray entries ✅
dpkg -l | grep -E "nvidia-open-580|nvidia-driver-580-open"    → no output - NOT apt-installed ✅
```
Also an improvement over the original capture in one respect: `nvidia-imex` is confirmed `.run`-installed this time (§7g Step 4), not mysteriously `dpkg`-tracked the way it was found to be on the original build (root cause of that never resolved, see §7g).

**Pre-capture, a real finding almost missed: `nvidia-persistenced` was found stopped** (not disabled — see §7h) due to partner diagnostics run the prior day. Confirmed this doesn't affect the tarball (systemd enablement state, the only part that gets captured, was untouched), then boot-verified end-to-end via an actual `reboot` that persistence comes back on automatically with zero manual steps — see §7h for full detail. This capture is therefore boot-tested for this specific property, not just config-reviewed.

**Post-capture validation — not yet run, needed before trusting this as the new reference:**
```bash
tar -tzf /root/bcm-image-export/maxQ20GA-1032-doca341-baseos.tgz | wc -l
tar -tzf /root/bcm-image-export/maxQ20GA-1032-doca341-baseos.tgz | grep '^\./etc/machine-id'
tar -tzf /root/bcm-image-export/maxQ20GA-1032-doca341-baseos.tgz | grep '^\./etc/ssh/ssh_host'
```
§25a's `machine-id`/SSH-host-key design choice (left live, not stripped, for the diag-account rationale) has not been explicitly re-confirmed as still the right call for this recapture — carried forward by default since nothing in this session changed that reasoning, not because it was re-evaluated.

**Open items:**
- ~~Post-capture tar-integrity validation~~ — done, see above.
- Not yet fed through `cm-create-image` — same as §25a's original status, this is a candidate image until that end-to-end pass completes, including re-confirming §25b's driver-survival check (`dkms status` inside the resulting chroot) after the build.
- Original `1029`-era tarball's fate (overwritten vs. preserved elsewhere) not confirmed.
- §0b's NVLink Recovery rack-wide upgrade requirement (all components ≥1.0.5, including NVSwitch) still needs verifying against whatever rack this new image eventually provisions — not specific to this capture, but relevant before treating any node built from it as production-ready.

*Status: captured (twice — see correction above, second capture is authoritative), renamed, and tar-level validation passed. Driver/IMEX baking strategy confirmed correct per §25b's validated approach. Persistence-at-boot property specifically boot-tested (§7h) *before* this final capture, not just assumed. `cm-create-image` pass still outstanding.*

## 26. Next Steps (not yet started)

- [x] NVIDIA kernel build packages (gcc, dkms, make) — see §5
- [x] NVIDIA datacenter driver install — 580.173.02 confirmed via `nvidia-smi`, see §7
- [x] IMEX service enabled + verified (expected inactive/clean-exit at L10, see §7)
- [x] Enable/start `rshim` service (see §6 open follow-ups) — done in §10
- [x] ConnectX-8 firmware burn — executed as bare-metal validation pass, confirmed 40.49.1118 on all 4 cards, see §10
- [x] BlueField-3 firmware flash — executed as bare-metal validation pass, confirmed 32.49.1118, see §10
- [x] Configure NVIDIA packages (§7a: profiling, IMEX control channel) — executed, see §7a
- [x] Persistence daemon enabled + verified (survives reboot) — see §7b
- [x] IMEX daemon confirmed enabled (already done in §7) — see §7c
- [x] Extended GPU memory — skipped, not applicable (no partner diagnostics) — see §7d
- [x] Post-§3.3.3.6 reboot + verification — see §7e
- [ ] IMEX peer config — deferred to rack-level (see §7a)
- [~] CUDA toolkit install — installed (13.0.2), verification (`nvcc --version`, post-install `nvidia-smi`) still pending, see §8
- [ ] Fabric Manager install + service enable
- [ ] NVLink/NVSwitch topology validation (`nvidia-smi topo -m`)
- [x] MOFED install — bundled via `doca-all` (`mlnx-ofed-kernel-dkms`, see §6)
- [x] DOCA / BlueField DPU bring-up — see §6, complete
- [x] ConnectX-8 firmware staged + PSID verified — see §6a (burn owned by production line, out of scope here)
- [x] BlueField-3 firmware staged — see §6c (flash owned by production line, out of scope here)
- [ ] DCGM install + `dcgmi diag` run
- [ ] Container runtime (`nvidia-container-toolkit`) + default runtime config
- [x] Clean up stale generic kernel packages (see §3)
- [ ] Run `gb300_l10_sw_checklist.sh` for full pass/fail against NVIDIA 2.0 matrix
- [ ] Consider making `mst start` a genuine persistent boot-time service rather than relying on the checklist-script workaround in §20
- [ ] Confirm System Product Name / VBIOS changes from the `00.58.03` BIOS/BMC update (§20) against release notes, especially if `System Product Name` is depended on by any downstream inventory/asset tooling
- [ ] Validate field-site offline kernel upgrade procedure (§21) against a real field unit; confirm dkms/build-essential presence assumption
- [x] IMEX Service inactive finding (§19) — resolved, expected L10 behavior (no fabric peers pre-rack), not a defect. No provisioning blocker.
- [x] Run L10 partner mfg diag (partnerdiag) — MaxQ-specific spec/SKU config (§18, §18a) run against this unit, `Final Result: PASS`, see §18b
- [x] Disk-cleanup pass — purged stale `cuda-repo-*`/`nvidia-driver-local-repo-*` local-repo packages and removed unused 8G `/swap.img`, ~12.4G reclaimed, CUDA/driver/DOCA confirmed intact — see §22a
- [ ] Review `apt list --upgradable` (130 packages, surfaced by §22a) before ever running `apt upgrade` on this reference layout — check specifically for `linux-image-*`/`nvidia-*`/`doca-*` version bumps against the pinned NVIDIA 2.0 matrix (§0)
- [ ] Audit other nodes in category `maxQ-1014-doca321` for the same manually-added, unused `/swap.img` (§22a open item) — not part of the BCM disk-setup definition, so likely a per-node manual addition rather than fleet-standard
- [x] Remove stale `6.17.0-1029-nvidia-64k` kernel packages + residual `/usr/src`/`/lib/modules` directories, 475 MB reclaimed, `xpmem` correctly left in place — see §22b
- [ ] Run `apt autoremove` for the orphaned X11/desktop packages surfaced during §22b's purge (libgl1, mesa-vulkan-drivers, xserver-xorg-core, xfonts-base, etc.) — check first whether this is the same unwanted-desktop-stack side effect §25 flagged from `nvidia-driver-580-open`, don't assume it without confirming
- [x] Capture reference-layout tarball (`maxQ20rc4-1029-doca341-baseos.tgz`) for BCM image export — validated at the tar level (integrity, expected-file presence, by-path consistency), see §25a
- [x] Recapture the reference layout tarball reflecting GA (`580.173.10`, kernel `1032`, CX8/BF3 firmware fix, three disk-hygiene passes) — done, `maxQ20GA-1032-doca341-baseos.tgz`, see §25d
- [x] Run post-capture tar-integrity validation on `maxQ20GA-1032-doca341-baseos.tgz` (member count, `machine-id`/SSH-host-key presence) — done: `186,001` members, both present, see §25d
- [ ] Feed `maxQ20GA-1032-doca341-baseos.tgz` through `cm-create-image` end-to-end and re-confirm §25b's driver-survival check inside the resulting chroot — not yet done, this capture is a candidate image until then
- [ ] Confirm whether the original `1029`-era tarball survives anywhere (BCM's own image store) now that its raw file at `/root/bcm-image-export/` was overwritten during the §25d recapture
- [x] Feed `maxQ20rc4-1029-doca341-baseos.tgz` into `cm-create-image` — end-to-end run completed 2026-09-08; surfaced a real finding, see §25b
- [x] Provision a real 18-node rack (`rack08`) from `baseos-1029-doca341` and confirm health — done 2026-09-08, all 18 nodes `[UP]` with no failure flag, `rack08node01` full `latesthealthdata` spot-check all-PASS, see §25c
- [ ] Spot-check `latesthealthdata` on the remaining 17 `rack08` nodes (only node01 confirmed in detail so far) before considering the rack fully signed off
- [ ] (secondary, deprioritized per §25b's revised recommendation) Update `cm-create-image`'s CM package list (head-node config, not this tarball) to pin every `nvidia-*`/`libnvidia-*`/`dkms` entry to the exact `580.173.02` version strings validated in §25b — only worth doing to quiet build-log noise, not required for correctness once the driver is baked into the tarball directly
- [x] Decided: driver correctness will come from the reference layout (`carlonext`, §7) being correct **before** the next tarball capture, not from apt-pinning inside `cm-create-image` — see §25b's revised recommendation (2026-09-08). Chasing pins in the BCM chroot repeatedly cost more time than it saved.
- [x] Before the next `-a` capture/re-tar of this reference layout, re-confirm `carlonext`'s driver state is still `580.173.02`/kernel `6.17.0-1029-nvidia-64k` (or whatever the current target is) so it's what actually gets baked into the new tarball — done for the §25d recapture: confirmed `580.173.10`/kernel `1032`/`.run`-installed (not apt) before capturing
- [ ] Same timing concern as the item above, applied to §22b: a future kernel HWE point-update will leave a new stale `linux-*-<old-version>-nvidia-64k` set behind the same way `1029` was — this cleanup isn't a one-time fix, it's a step to repeat on every kernel bump before the next tarball capture, not yet automated or added to any checklist
- [ ] Confirm whether `cm-create-image`/BCM's node-install process has its own `machine-id`/SSH-host-key regeneration mechanism, since §25a's image deliberately ships both static (diverging from §25's per-clone-regen design) — needs to be a conscious pipeline-level decision before cloning multiple production nodes from this image
- [ ] **New per §0a (2026-09-14):** bump `carlonext` driver + IMEX from RC4-era `580.173.02` to GA-pinned `580.173.10`, then re-run `nvidia-smi`/`modinfo nvidia`/`dkms status` verification (same checks as §7/§16a) before the next tarball capture
- [ ] Re-validate `nvidia-fabricmanager` (host package, §25) tracks the new `580.173.10` driver branch once bumped — confirm via the local-repo `.deb` naming, not by assuming the old `580.173.02`-tied install carries forward
- [ ] Confirm the actual NVSwitch-tray/NVOS-side Fabric Manager version against GA release notes directly (not assumed equal to the driver version or to the old RC4 `580.173.04` value — see §0a)
- [ ] Add the GA BMC/MCU/HMC out-of-band firmware baseline (§0a) to whatever process validates a rack post-handoff; confirm the checklist script's Redfish component-id filter actually surfaces an SMA/MCU entry
- [ ] Re-verify `nvidia-persistenced` (§7f) survives the *next* reboot — especially the one following the pending driver bump to `580.173.10` — and root-cause why it was found `disabled` on 2026-09-14 despite §7e's original confirmation, before treating the fix as durable
- [x] Bump driver + IMEX to GA-pinned `580.173.10` on `carlonext` — see §7g
- [x] Confirm/deny the `CX8_BF3_config.yml` Ansible-driven dependency-pull theory for how `nvidia-imex` became `dpkg`-tracked (§7g) — grepped, ruled out; actual trigger still unexplained
- [x] Review the `/usr/share/nvidia` and `/etc/nvidia-imex` leftover directories from the §7g package purges — confirmed current/from-this-session, not stale; no removal needed
- [x] Bring `nvidia-modprobe` in line with the `580.173.10` bump — done, confirmed via `nvidia-modprobe --version`, re-held
- [x] Decide: stay pinned at `cuda-toolkit-13-0` `13.0.2`, or take the available `13.0.3` point release (§7g) — decided: stay pinned, `13.0.3` isn't part of the GA-qualified pairing at all (general CUDA repo, not this release train); hold applied
- [x] Re-flash CX8/BF3 firmware after discovering both had reverted to the pre-§10 baseline — see §10a; re-verified at both `ibstat` and kernel `dmesg` level
- [ ] Root-cause the CX8/BF3 firmware revert itself (§10a) — SEL/dmesg came back clean, leading theory is a process-level revert possibly tied to §25's tarball/BCM work, not confirmed
- [ ] Treat BF3/CX8 firmware verification as a standing pre-handoff/post-reimage check (§10a), not a one-time confirmation, until the revert mechanism is actually understood
- [ ] Copy the updated `gb300_l10_sw_checklist.sh` (currently v0.4.26, adds real GA-sourced BMC/EROT/VBIOS comparison) onto `carlonext` — the v0.4.23 copy still there doesn't yet flag the known-stale `HGX_FW_BMC_0`/`HGX_FW_ERoT_*`/VBIOS readings
- [ ] **New, highest priority per §0b:** verify `rack08` (and every compute node + NVSwitch tray in it) meets GA's "upgrade all rack components to 1.0.5+" requirement for NVLink Recovery compatibility — not yet checked, and failure mode may not surface in the existing `[UP]`/health-check spot-checks already done in §25c
- [ ] Investigate the VBIOS mismatch reopened in §0a/§16: installed `97.10.59.00.13` vs GA-documented `97.10.7D.00.16` (same `7D` segment as the earlier RC4 value) — determine whether this needs an actual VBIOS flash and what that procedure/risk looks like on this hardware, separate from anything already done in §7g/§10a
- [x] Add FPGA checklist check for the HMC baseline (§0b: `1.66`) — done in v0.4.28, also fixed a real false-positive bug (E1S CPLD wrongly compared against the wrong component's target) found in the same pass
- [ ] SBIOS still has no checklist check (§0b: `02.06.06`) — not yet wired in, no corresponding `nvidia-smi`/dpkg-queryable field identified yet
- [ ] HMC FPGA now also confirmed drifted (`1.60` live vs `1.66` GA target, §0b) — add to the same firmware-update pass as CX8/BF3 (§10a), BMC/EROT, and VBIOS rather than treating as a fourth separate one-off
- [ ] Re-pull NVOnline `1162808` (GA's Source of Truth Metadata File, replaces RC4's `1160245`) and diff against what's already in §0/§0a if a fully authoritative cross-check is ever needed

---

*This log is updated as each stage of the bring-up completes. Pair with `gb300_l10_sw_checklist.sh` for live version verification at any point in the process.*

