# GB300 NVL L10 Reference Layout — Build Log

**Reference:** NVIDIA 2.0 release, GB300 L10 reference layout — MNNVL Bring-Up Guide, Release 1.15
**Checklist script version:** `gb300_l10_sw_checklist.sh` v0.4.4

## 0. Host Software Components — Version Matrix (source of truth)

Pinned versions per NVIDIA 2.0 release matrix. Confirmed `DOCA_Host` here (3.4.1-010000) is correct, overriding the public DOCA downloads page's current default landing version (3.4.0) — public page just hadn't surfaced the pinned point release by default.

**CUDA Toolkit corrected to `13.0.2`** (was previously `12.8` in this table, based on an earlier assumption — not an NVOnline-sourced confirmation). Verified via NVOnline **1160245** ("GB300 NVL72 MAXQ Software and Firmware Source of Truth Metadata File, 2.0.0RC4"), Table 2 (Public Release Links Associated with this Release), which pairs `Datacenter Driver Version 580.173.02` with `CUDA Toolkit 13.0.2` — the driver version is an exact match to what's already installed and confirmed via `nvidia-smi` in §7, giving high confidence this is the correct pairing.

| Component | Version |
|---|---|
| Kernel Module Source (NVIDIA driver) | `NVIDIA-kernel-module-source-580.173.02.tar.xz` |
| CUDA Toolkit | `13.0.2` |
| MFT Tools | `4.36.0-147` |
| WinOF-2 | `26.4.27095` |
| DOCA_Host | `3.4.1-010000` |
| Fabric Manager (GFM) | `580.173.04` |
| NMX-M | `20v85.1.1100_85.1.1100.pdf` |
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

*Status: firmware staged and verified, burn commands documented for production line. Executed as a bare-metal validation pass in §11 (not a production-line flash) — confirmed 40.49.1118 on all 4 cards.*

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

*Status: BF3 firmware staged (firmware-only bundle, correct per diag). Leading explanation: NIC-mode design; final confirmation with diag still pending — flashed successfully in §11 as a bare-metal validation pass (confirmed 32.49.1118 via `ibstat mlx5_8`), but that confirms the firmware-only bundle installs and runs correctly, not that the NIC-mode explanation itself is diag-confirmed.*

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

*Status: deferred — see partner diag prep (§13+) rather than treated as resolved/skipped.*

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

## 9. CUDA Toolkit Install

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

*Status: toolkit installed successfully. Verification pending — run `nvcc --version` and `nvidia-smi` before marking §9 fully complete.*

## 10. Linux Kernel Tool Install List

Per internal "Installation - Linux kernel tool install list" slide. Two items needed disambiguation before install:

- **`mstvp`** — not a real package name; identified as a truncated/typo'd reference to `mstvpd` (Mellanox VPD-read tool), which ships bundled inside the `mstflint` package rather than as its own apt package. Installed `mstflint` only; `mstvpd` came along with it.
- **`mstflint`** — this is the open-source Ubuntu-repo package (distinct from NVIDIA's own MFT `mft`/`mft-mlx5`/`mft-nvredfish` 4.36.0-147 already installed via `doca-all` in §6). Both can coexist on disk, so before logging this complete, checked whether apt's `mstflint` (4.26.0) shadows the NVIDIA MFT `flint` binary (4.36.0-147) that §6a's PSID-check/burn commands depend on — **confirmed no shadowing**, `flint` on `PATH` still resolves to the correct `4.36.0-147` MFT build.

```bash
sudo apt install -y fio sysstat smartmontools numactl net-tools unzip \
  jq ipmitool nvme-cli expect stress-ng sshpass mstflint
```

**Already present before this run** (no-op, previously installed): `sysstat` (12.6.1-2), `numactl` (2.0.18-1ubuntu0.24.04.1), `jq` (1.7.1-3ubuntu0.24.04.2). `gcc` and `make` (also on the slide's implied baseline) were already installed in §5 and not re-specified here.

**Newly installed (35 packages total incl. dependencies):** `fio`, `smartmontools`, `net-tools`, `unzip`, `ipmitool`, `nvme-cli`, `expect`, `stress-ng`, `sshpass`, `mstflint` — plus transitive deps (`freeipmi-common`, `openipmi`, `libglusterfs0`/`librados2`/`librbd1` stack pulled in by `fio`'s optional storage-backend support, etc.). No errors, no service restart required.

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

*Status: complete. §10 done.*

## 11. ConnectX-8 / BlueField-3 Firmware Flash — Bare-Metal Validation Pass

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

## 12. Ansible Install

```bash
apt install ansible-core
```

Installed `ansible-core` (2.16.3-0ubuntu2) and the full `ansible` metapackage (9.2.0+dfsg-0ubuntu5), 15 packages total, no errors. Installed ahead of the remaining bring-up tasks; not yet tied to a specific playbook or automation target — noted here for completeness rather than as a scoped bring-up step.

*Status: complete.*

## 13. CX8 / BF3 Ethernet Mode Configuration (Ansible)

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
2. `sudo mlxfwreset -d /dev/mst/mt41692_pciconf0 -y reset` — **stalled**, ran far longer than expected with no completion. Likely cause (not confirmed via `ps`/`dmesg` before cutting over): `rshim` was still active from §11 and may have held the device open, blocking `mlxfwreset`'s exclusive-access requirement. Worth checking `systemctl stop rshim` before `mlxfwreset` on BF3 in future runs.
3. `sudo ipmitool chassis power cycle` (DC power cycle via BMC) — **worked.** Same mechanism required for the firmware load in §11.

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

## 14. gb300_l10_sw_checklist.sh — First Full Run + Bugfixes

**Run 1 (as `pega`, no sudo):** `22 OK | 3 NEEDS REVIEW | 12 MISSING`. Several `MISSING` results were false negatives from lacking root — `BMC/BIOS`, `System Product Name`, `IOMMU Enabled`, `MFT Tools Version`, `BF3 Firmware Version` — `dmidecode`/`mst`/`flint` all silently fail without privilege.

**Run 2 (as root):** `26 OK | 2 NEEDS REVIEW | 9 MISSING`. Confirmed:
- `BMC/BIOS`: `00.56.02`
- `System Product Name`: `Carlo_Next MaxQ`
- `MFT Tools Version`: `4.36.0-147` — matches §0/§6a target
- `BF3 Firmware Version`: `32.49.1118` — matches §11's confirmed flash

**Remaining `MISSING` after root run — expected, matches known open work:** Fabric Manager Service/Version, DCGM Version, Docker/containerd/nvidia-container-toolkit/Default Runtime, `nvcc` (CUDA toolkit — see below).

**`NVSwitch Devices`: still `MISSING`** even as root. Not yet resolved either way — plausibly expected for a single un-racked L10 unit with no switch tray/fabric attached (same reasoning applied elsewhere in this log to IMEX/NVLink), but not confirmed. Flagged as open, not assumed benign.

**Two script bugs found and fixed (now v0.4.2):**

1. **`IOMMU Enabled` — false negative on this platform.** Script checked `dmesg | grep -m1 -i 'IOMMU enabled'`, an x86-style log string that Grace/ARM never emits (SMMU is enabled via ACPI IORT tables, not a boot-time log line). Investigated directly before concluding it was a script bug rather than a real gap:
   - `dmesg | grep -iE 'smmu|arm.*iommu'` → confirmed 27+ `arm-smmu-v3-pmcg` PMU instances registered across multiple PCIe root complexes (hardware present/probed, but PMCG alone doesn't prove translation is active)
   - `ls /sys/kernel/iommu_groups/ | wc -l` → **90** populated groups — definitive confirmation IOMMU/SMMU translation is genuinely active and enforcing isolation, not just probed.
   - Fixed: check now uses the `/sys/kernel/iommu_groups/` population count directly (architecture-agnostic) instead of a platform-specific log string.

2. **`CUDA Version (driver)` — invalid query field.** `nvidia-smi --query-gpu=cuda_version` returned `Field "cuda_version" is not a valid field to query.` on this driver/nvidia-smi build. Fixed: now parses `CUDA Version: X.Y` out of plain `nvidia-smi`'s header output instead of the `--query-gpu` field list.

**Not yet fixed — flagged for follow-up:**
- **`nvcc (CUDA toolkit)`: `MISSING`.** This is the deferred CUDA verification from §9 finally surfacing a real result: `nvcc` is not on `PATH`. Toolkit installed correctly (`update-alternatives` set `/usr/local/cuda` → `/usr/local/cuda-13.0` per §9), but `/usr/local/cuda/bin` was never added to `PATH`. Fix identified, not yet applied:
  ```bash
  echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
  ```
- **`MOFED Version` shows `CHECK`** — actual installed value `OFED-internal-26.04-1.0.9` vs. script's `EXPECTED_MOFED="24.10"`. Same stale-matrix pattern as the CUDA 12.8→13.0.2 correction in §0 — `24.10` was never verified against NVOnline 1160245 the way driver/CUDA/DOCA/MFT/BF3-FW were. **Resolved in §17.**

*Status: script bugs fixed (v0.4.2). Real findings (`nvcc` PATH, `EXPECTED_MOFED` staleness, `NVSwitch Devices`) still open, not yet resolved.*

## 15. nvcc PATH Fix (system-wide, for reference hand-off)

`nvcc` was MISSING in checklist runs — toolkit installed correctly (§9), but `/usr/local/cuda/bin` was never added to `PATH`. Used a system-wide `/etc/profile.d/` drop-in rather than `~/.bashrc`, since this build is meant for hand-off:

```bash
echo 'export PATH=/usr/local/cuda/bin:$PATH' | sudo tee /etc/profile.d/cuda.sh
sudo chmod 644 /etc/profile.d/cuda.sh
```

`ldconfig -p | grep cudart` confirmed runtime libs were already correctly registered, no extra fix needed there. Confirmed both via `nvcc --version` (`release 13.0, V13.0.88`, matching the installed toolkit) and a full checklist re-run (`nvcc` now `OK`, `29 OK | 1 CHECK | 7 MISSING`).

**Aside — checklist hang during active MODS session:** separately, `gb300_l10_sw_checklist.sh` was found to hang indefinitely if run while a MODS-related setup step from the partner diagnostics package was already active (MODS unloads/blacklists the `nvidia` driver for exclusive GPU access, and the checklist has no timeout on its checks). Not a defect — the checklist can't produce meaningful GPU results while the driver is deliberately out of the picture. Resolved once the MODS session cleared. Missing-timeout-on-checks noted as a real, separate script follow-up.

*Status: complete.*

## 16. nvcc PATH — Round 2: Non-Interactive/sudo Invocation

**Symptom:** after §15's fix (`/etc/profile.d/cuda.sh`) and re-login, `nvcc` was reported lost again.

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

## 17. EXPECTED_MOFED / EXPECTED_FM Resolved via NVOnline 1160245 Raw JSON

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

```bash
# gb300_l10_sw_checklist.sh changes (v0.4.3 -> v0.4.4)
EXPECTED_FM="580.173.04"       # was "570"
# EXPECTED_MOFED removed
```

*Status: complete. `EXPECTED_FM` corrected and added to §0. `EXPECTED_MOFED` removed (no longer a valid independent target per source of truth); `MOFED Version` check is now informational. `NVSwitch Devices` remains the one still-open item from §14, unconfirmed either way (expected for un-racked L10 vs. real gap).*

## 17a. Checklist Confirmation Run — Post §17 Fix

```
 MOFED Version                    : OFED-internal-26.04-1.0.9:             [OK]
 ...
 Summary: 30 OK | 0 NEEDS REVIEW | 7 MISSING
```

`MOFED Version` now `[OK]` (informational, no stale-target false flag). `CHECK` column at zero for the first time. Remaining `MISSING` rows are all legitimately pending installs (Fabric Manager, DCGM, Docker/containerd/nvidia-container-toolkit/default runtime) plus `NVSwitch Devices`, the one still-unresolved item.

*Status: complete.*

## 18. CPLD / EROT / HMC / FPGA Readout — In-Band vs. Out-of-Band

Checked whether CPLD, EROT, HMC, FPGA (per NVOnline component table) are readable in-band, same as SBIOS (`dmidecode -t 0`) and GPU/VBIOS (`nvidia-smi`).

**Finding:** only SBIOS is genuinely in-band — CPLD/EROT/HMC/FPGA are BMC-domain firmware, not exposed to the host as PCIe/DMI devices. The standard tool for reading them (`nvfwupd`) is explicitly documented as out-of-band, requiring a BMC IP target (`-t ip=<bmc-ip> ...`) regardless of whether that IP is reached over the datacenter network or a local host↔BMC link. Decided not to pursue further since a BMC IP is required either way.

**Separately confirmed as an accepted, known gap (not investigated further):** HMC version mismatch against the NVOnline reference table — firmware update not yet available for this component.

*Status: closed — BMC IP required for these four; not pursued further per decision above.*

## 8. Next Steps (not yet started)

- [x] NVIDIA kernel build packages (gcc, dkms, make) — see §5
- [x] NVIDIA datacenter driver install — 580.173.02 confirmed via `nvidia-smi`, see §7
- [x] IMEX service enabled + verified (expected inactive/clean-exit at L10, see §7)
- [x] Enable/start `rshim` service (see §6 open follow-ups) — done in §11
- [x] ConnectX-8 firmware burn — executed as bare-metal validation pass, confirmed 40.49.1118 on all 4 cards, see §11
- [x] BlueField-3 firmware flash — executed as bare-metal validation pass, confirmed 32.49.1118, see §11
- [x] Configure NVIDIA packages (§7a: profiling, IMEX control channel) — executed, see §7a
- [x] Persistence daemon enabled + verified (survives reboot) — see §7b
- [x] IMEX daemon confirmed enabled (already done in §7) — see §7c
- [x] Extended GPU memory — skipped, not applicable (no partner diagnostics) — see §7d
- [x] Post-§3.3.3.6 reboot + verification — see §7e
- [ ] IMEX peer config — deferred to rack-level (see §7a)
- [~] CUDA toolkit install — installed (13.0.2), verification (`nvcc --version`, post-install `nvidia-smi`) still pending, see §9
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

---

*This log is updated as each stage of the bring-up completes. Pair with `gb300_l10_sw_checklist.sh` for live version verification at any point in the process.*

