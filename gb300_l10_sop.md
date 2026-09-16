# GB300 Max-Q NVL72 — L10 Compute Tray Bring-Up SOP

**Applies to:** GB300 Max-Q NVL72, Release 2.0.0GA (RN-11874-001_2.0.0GA)
**Scope:** Single compute tray, pre-rack (L10). Rack-level (L11) steps are out of scope.
**Source:** Distilled from `gb300_l10_build_log.md` — that document is the full engineering
record (every issue found, root-caused, and fixed); this SOP is the validated procedure
only. If something here doesn't match what you're seeing, the build log has the detail.

---

## 1. Target Versions (2.0.0GA)

Confirm every install against this table. Don't substitute "latest" for any of these —
several have caused real problems this build (see Known Issues at the end of this document).

| Component | Target Version |
|---|---|
| Ubuntu | 24.04 |
| Kernel | `6.17.0-1032-nvidia-64k` (HWE, 64K page size) |
| GPU Driver | `580.173.10` |
| IMEX | `580.173.10` (matches driver) |
| CUDA Toolkit | `13.0.2` — **not** `13.0.3` or newer; not part of this qualified release |
| MFT Tools | `4.36.0-147` |
| MSTflint | `v4.36.0-1` (separate component from MFT Tools — both correct, not a version conflict) |
| DOCA_Host | `3.4.1-010000` |
| BF3 Firmware | `32.49.1118` |
| CX8 Firmware | `40.49.1118` |
| NMX-M | `85.1.1100` |
| DCGM | `4.6.0` (NVOnline 1139880) |
| Host-side `nvidia-fabricmanager` package | tracks GPU Driver version — `580.173.10` (inert on this host, see §6) |
| NVSwitch-tray GFM (NVOS-side) | `580.173.04` — independent of driver version, verify on the switch tray once racked |

**Not yet current on this reference build** (host software above is correct; this is
out-of-band/board firmware that needs its own update pass, separate from this SOP):
BMC, EROT, HMC FPGA, VBIOS.

---

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

**`PermitRootLogin yes` allows root password auth over SSH** — acceptable on an isolated
bring-up network, but consider `prohibit-password` (key-only) instead if this unit will
be reachable from anywhere less trusted.

If an interactive editor (`nano`, etc.) fails with `Error opening terminal: unknown` on
a console session, that's a missing/unsupported `TERM` — either `export TERM=xterm` for
that session, or use non-interactive tools (`sed`, `tee`) to sidestep it entirely, which
every command in this SOP already does.

---

## 3. Prerequisites

- Ubuntu 24.04 already installed; §2 above completed.
- Staged installer files (get current versions from NVOnline, IDs below):
  - `NVIDIA-Linux-aarch64-580.173.10.run`
  - `nvidia-imex-aarch64-580.173.10*.run`
  - `nvidia-driver-local-repo-ubuntu2404-580.173.10_1.0-1_arm64.deb`
  - ConnectX-8 / BlueField-3 firmware bundles (see §5)
  - `gb300_l10_sw_checklist.sh` (verification tool, run after every major step)
- NVOnline IDs for this release:
  | ID | Contents |
  |---|---|
  | `1162802` | Compute Tray Firmware, 2.0.0GA |
  | `1162850` | GPU Drivers, 2.0.0GA |
  | `1162808` | Source of Truth Metadata File, 2.0.0GA |
  | `1159833` | CX8/BF3 Firmware, Drivers, Tools |
  | `1143691` | Partner Diagnostics, Compute Tray (L10) |

---

## 4. Kernel & Package Hygiene

**GB300's Grace CPU requires the 64KB-page HWE kernel, not the stock 4KB-page generic
Ubuntu kernel that ships by default.** This is the actual switch, not just a check:

```bash
sudo DEBIAN_FRONTEND=noninteractive apt purge \
  linux-image-$(uname -r) linux-headers-$(uname -r) linux-modules-$(uname -r) -y
sudo apt update
sudo apt install linux-nvidia-64k-hwe-24.04 -y
sudo reboot
```

**Verify post-reboot:**
```bash
uname -r          # expect 6.17.0-1032-nvidia-64k
getconf PAGE_SIZE # expect 65536
```

**Watch for stale generic-kernel packages surviving the swap** — on this build, both the
new Grace kernel and the old generic kernel (plus its `linux-image-generic` meta-package,
which re-pulls the generic kernel if left installed) were present simultaneously after
the switch. Confirm and clean up if so:
```bash
dpkg -l | grep linux-image   # should show ONLY the nvidia-64k kernel + its meta-package
# if a stale generic kernel is still present:
sudo apt purge -y linux-image-<old-generic-version> linux-image-generic linux-headers-<old-generic-version>
sudo rm -rf /lib/modules/<old-generic-version>/   # only if dpkg's own rmdir fails and no
                                                    # third-party (DKMS) modules live there
sudo apt autoremove -y
sudo update-grub
```

**Fix `TERM` for interactive console tools** (only needed if you hit `Error opening
terminal: unknown` with `nano`/`watch`/etc. on this console):
```bash
echo 'export TERM=xterm-256color' >> ~/.bashrc
source ~/.bashrc
```

**Hold the kernel meta-packages and disable anything that could pull a newer kernel or
run apt mid-install for the rest of this procedure:**
```bash
sudo apt-mark hold \
  linux-nvidia-64k-hwe-24.04 \
  linux-image-nvidia-64k-hwe-24.04 \
  linux-headers-nvidia-64k-hwe-24.04

sudo systemctl stop unattended-upgrades
sudo systemctl disable unattended-upgrades
sudo systemctl stop apt-daily.timer apt-daily-upgrade.timer
sudo systemctl disable apt-daily.timer apt-daily-upgrade.timer
```
Stopping the timers matters, not just the service — a background unattended-upgrade run
holding the dpkg lock has directly blocked the `apt-mark hold` command above on this
build. **Re-enable both once this reference layout is handed off for production use**, if
automatic security updates are wanted there — leaving them off is specifically to avoid
apt racing the driver/CUDA/DOCA installs during bring-up.

**Install kernel build tooling before any DKMS-based install:**
```bash
sudo apt update -y && sudo apt install -y gcc dkms make
```

---

## 5. DOCA Host + ConnectX-8 / BlueField-3

**DOCA-Host `3.4.1-010000` is not on the public DOCA downloads page.** Public downloads
only go up to `3.4.0`, which NVIDIA's own docs state is *not intended for Grace-Blackwell
customers*. `3.4.1-010000` is a GB/B-designated build, obtained via NVOnline (support
channel), not `apt install doca-host` from any public repo.

```bash
# .deb obtained via NVOnline - place in working dir first
sudo dpkg -i doca-host_3.4.1-010000-26.04-ubuntu2404_arm64.deb
sudo apt-get update      # picks up the local repo this package installs
sudo apt install -y doca-extra

# Build kernel modules via DKMS against the current kernel
sudo rm -rf /tmp/DOCA*
sudo /opt/mellanox/doca/tools/doca-kernel-support
# Generates /tmp/DOCA.<hash>/doca-kernel-repo-<ver>.deb - install it:
sudo dpkg -i /tmp/DOCA.<hash>/doca-kernel-repo-*.deb

# Pin the DOCA-HOST repo so apt prioritizes it correctly
cat <<'EOF' | sudo tee /etc/apt/preferences.d/doca-host-repository-pin-600
Package: *
Pin: release l=DOCA-HOST
Pin-Priority: 600
EOF

sudo apt update
sudo apt -y install doca-all
```

Confirm `doca-runtime`/`doca-devel`/`doca-all` all resolved to `3.4.1-010000` (not a
different version apt picked up from elsewhere), and that the DKMS modules built cleanly
against the running kernel (`dkms status`).

**Enable `rshim`** — required for the BlueField-3 firmware flash steps below; easy to
miss since `doca-all` installs the package but does not enable or start it:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now rshim
```

**Start MST before any firmware or config work:**
```bash
sudo mst start
mst status -v   # confirm all expected CX8 (mt4131_*) and BF3 (mt41692_*) devices appear
```

**MST device tree does not persist across reboot — `mst start` must be re-run after every
reboot** (including after BIOS/BMC firmware updates), **before any command that touches
`/dev/mst/*` paths.** If `flint`-based checks (BF3/CX8 firmware version) suddenly show
`MISSING` after a reboot while everything else (`ibstat`, `mst status` device presence)
still looks fine, this is almost certainly why — not a real regression.

**Firmware flash** (get current bundle filenames/PSIDs from NVOnline 1159833):

```bash
# PSID sanity check FIRST — confirm every card matches the PSID the staged
# firmware file is built for before burning anything
sudo flint -d 0000:03:00.0 q | grep -i psid
sudo flint -d 0002:03:00.0 q | grep -i psid
sudo flint -d 0010:03:00.0 q | grep -i psid
sudo flint -d 0012:03:00.0 q | grep -i psid
# All 4 should report the same PSID. Do NOT proceed if the staged firmware
# file's PSID doesn't match what these report — flashing a mismatched PSID
# firmware image is a real bricking risk.

FW=<path-to-CX8-firmware-bundle>
sudo flint -d 0000:03:00.0 -i "$FW" burn
sudo flint -d 0002:03:00.0 -i "$FW" burn
sudo flint -d 0010:03:00.0 -i "$FW" burn
sudo flint -d 0012:03:00.0 -i "$FW" burn

sudo systemctl start rshim
sudo bfb-install --rshim rshim0 --bfb <path-to-BF3-fwbundle.bfb>

# Firmware does not take effect on reboot alone — a full power cycle is required.
# One power cycle covers both devices: CX8 needs a full reboot (not mlxfwreset,
# since it acts as a PCIe switch), and BF3's bfb-install explicitly states
# "Host power cycle is required" — a power cycle satisfies both.
sudo ipmitool chassis power cycle
```

**After the power cycle, verify at two independent layers, not just one:**
```bash
ibstat mlx5_5   # CX8 - expect Firmware version: 40.49.1118
ibstat mlx5_8   # BF3 - expect Firmware version: 32.49.1118
dmesg -T | grep firmware   # confirm the kernel driver also sees the new version, not just userspace tooling
```

---

## 6. NVIDIA GPU Driver, IMEX, Fabric Manager

**Install the driver via the `.run` installer — not apt.** This is a hard requirement, not
a preference: installing via apt inside a BCM `cm-create-image` pipeline has caused
silent version drift to whatever NVIDIA's repo considers newest at build time, bypassing
this table's pinned versions entirely. Bake the driver in via `.run` before any image
capture and this risk doesn't apply.

**Install driver and IMEX together, in this order** — matches the original bring-up
guide's own section grouping (driver+IMEX install, then a distinct later section for
package configuration); no functional dependency forces this order, but there's no
reason to deviate from what was actually validated:
```bash
sudo sh ./NVIDIA-Linux-aarch64-580.173.10.run --dkms -q -s -m=kernel-open
sudo sh ./nvidia-imex-aarch64-580.173.10*.run

# Verify both before proceeding
nvidia-smi                        # expect Driver Version: 580.173.10
dkms status                       # expect nvidia/580.173.10 against the current kernel only
```

**Configure NVIDIA packages:**
```bash
sudo rm -f /etc/modprobe.d/nvidia-graphics-drivers-kms.conf   # may not exist - harmless
echo 'options nvidia NVreg_RestrictProfilingToAdminUsers=0' | sudo tee /etc/modprobe.d/nvprofiling.conf
echo 'options nvidia NVreg_CreateImexChannel0=1' | sudo tee /etc/modprobe.d/nvidia.conf
sudo update-initramfs -u -k all
```
> IMEX peer configuration (`/etc/nvidia-imex/nodes_config.cfg`) is an L11/rack-integration
> step — leave deferred until this unit has real peer node IPs.

**Enable the persistence daemon.** The `.run` installer does not ship this unit file —
create it manually:
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

sudo systemctl enable --now nvidia-persistenced
nvidia-smi --query-gpu=persistence_mode --format=csv,noheader   # expect Enabled on every GPU
```

**Enable the IMEX daemon** (already installed above; this is a distinct guide step, not
a re-install):
```bash
sudo systemctl enable --now nvidia-imex
```
> `nvidia-imex` service will show `inactive` on a single, pre-rack unit — this is
> **expected**, not a fault. It requires an active NVSwitch-tray GFM and populated peer
> config, neither of which apply until L11 rack integration.

**Install Fabric Manager** — this host's own `nvidia-fabricmanager` package is a
future-proofing precaution only; actual fabric management runs on the NVSwitch tray, not
this host:
```bash
sudo dpkg -i nvidia-driver-local-repo-ubuntu2404-580.173.10_1.0-1_arm64.deb
sudo cp /var/nvidia-driver-local-repo-ubuntu2404-580.173.10/nvidia-driver-local-*-keyring.gpg /usr/share/keyrings/
sudo apt update
sudo dpkg -i /var/nvidia-driver-local-repo-ubuntu2404-580.173.10/nvidia-fabricmanager_580.173.10-1ubuntu1_arm64.deb
sudo systemctl mask nvidia-fabricmanager
sudo apt-mark hold nvidia-fabricmanager

# Remove the repo immediately after — don't leave it installed
sudo apt purge -y nvidia-driver-local-repo-ubuntu2404-580.173.10
```

**Pin every driver-adjacent package that could otherwise silently jump to a different
major branch on a routine `apt upgrade`:**
```bash
sudo apt-mark hold libnvidia-nscq nvidia-modprobe
```

**Reboot and do a full re-verification** — don't assume config alone guarantees
boot-time behavior:
```bash
sudo reboot
# after reboot:
systemctl status nvidia-persistenced   # expect active (running), started automatically
nvidia-smi --query-gpu=persistence_mode --format=csv,noheader   # expect Enabled, no manual steps
```

---

## 7. CUDA Toolkit

```bash
# Install CUDA 13.0.2 specifically - do not take a newer point release from the
# general public CUDA repo; it isn't part of this qualified release
sudo apt install cuda-toolkit-13-0=13.0.2-1   # adjust package name/pin per current repo state
sudo apt-mark hold cuda-toolkit-13-0
nvcc --version   # expect release 13.0, V13.0.88
```

**If `nvcc` isn't found even though the toolkit installed cleanly** — the package doesn't
put itself on `PATH` automatically. Add it system-wide, in the two places that turn out
to matter for different invocation contexts (login shell vs. non-login interactive shell):
```bash
echo 'export PATH=/usr/local/cuda/bin:$PATH' | sudo tee /etc/profile.d/cuda.sh
sudo chmod 644 /etc/profile.d/cuda.sh

grep -q '/usr/local/cuda/bin' /etc/bash.bashrc || \
  echo 'export PATH=/usr/local/cuda/bin:$PATH' | sudo tee -a /etc/bash.bashrc
```
A plain `nvcc --version` in a fresh interactive shell should now work regardless of
login/non-login status. (The verification checklist in §11 has its own internal `PATH`
fix and doesn't depend on any of this — but anyone using `nvcc` directly needs the above.)

---

## 8. System Tools Install

```bash
sudo apt install -y fio sysstat smartmontools numactl net-tools unzip \
  jq ipmitool nvme-cli expect stress-ng sshpass mstflint ifupdown
```

**`ifupdown` matters more than it looks like it should — this is not optional on Ubuntu
24.04.** `ifupdown` was fully removed from default 24.04 installs (Netplan +
`systemd-networkd` is the only supported path out of the box). Without it explicitly
installed, anything dropped into `/etc/network/interfaces.d/` — including whatever
§12's config-directory check creates or a provisioning pipeline writes there — is
**silently ignored** by the kernel/systemd. This wasn't on the original tool-list
reference; add it anyway on 24.04.

**`mstflint` here is the open-source Ubuntu-repo package — a different thing from
NVIDIA's own MFT tooling (`mft`/`mft-mlx5`/`mft-nvredfish`, `4.36.0-147`) already
installed via `doca-all` in §5.** Both coexist on disk without conflict, but verify the
`flint` binary on `PATH` still resolves to the NVIDIA MFT build, not the apt package's
own `flint` — §5's PSID-check/firmware-burn commands depend on the NVIDIA one
specifically:
```bash
which flint && flint -v   # expect: flint, mft 4.36.0-147 - NOT mstflint's own version string
which mstvpd && mstvpd -v # confirms mstflint installed correctly (mstvpd ships bundled with it)
```

---

## 9. Ansible — CX8/BF3 Ethernet Mode

Required before partner diagnostics — both CX8 and BF3 need Ethernet mode set.

```bash
sudo apt install ansible-core

cat <<'EOF' > inventory.ini
[compute_nodes]
localhost ansible_connection=local
EOF

# Run from a root shell (sudo -i) - become:true under a non-root user with no
# cached sudo password will fail non-interactively
ansible-playbook -i inventory.ini CX8_BF3_config.yml
```

**Expect 8 "changed" entries for CX8 even though there are only 4 physical cards** — a
known, harmless quirk in this playbook's device-discovery regex (it matches both PCIe
functions per card, so each card's config gets applied twice). Idempotent, no actual harm,
just don't mistake it for something being wrong.

**Applying the config requires a power cycle — and a specific one, not just any reset:**
```bash
# Stop rshim FIRST if it's running - it can hold BF3's device open and cause
# mlxfwreset/reset attempts to stall indefinitely with no error, no completion
sudo systemctl stop rshim

sudo ipmitool chassis power cycle   # DC power cycle via BMC - a plain "sudo reboot" is
                                     # NOT sufficient; the new config stages but does not
                                     # actually load until this happens
sudo systemctl start rshim           # restart once the cycle completes
```

**Verify:**
```bash
ibstat mlx5_8   # BF3 - expect Link layer: Ethernet (was InfiniBand by default)
# CX8 is Ethernet-mode by default - no link-layer flip needed there, just confirm params:
sudo mlxconfig -d /dev/mst/mt4131_pciconf0 q | grep -iE 'num_of_pf|num_of_planes'
```

---

## 10. Disk Hygiene (before any image capture)

```bash
sudo apt-get clean                          # clear the apt package cache
sudo apt purge -y <stale-driver-local-repo-if-still-present>
sudo apt autoremove                         # review the list before confirming
```

Also remove any stale kernel packages for a kernel version no longer in use — confirm via
`dpkg -l | grep <old-kernel-version>` and `dkms status` (make sure nothing is still
registered against the version being removed) before purging.

**Check for a manually-added, unused swap file** — confirmed on this build's reference
layout to be a leftover from manual setup, not something BCM's category disk-setup
definition creates:
```bash
swapon --show
free -h
```
If swap is present and BCM's category disk-setup definition doesn't actually call for
one (check `get disksetup` on the relevant category via `cmsh` if unsure), and current
usage is `0B` despite normal load — it's not doing anything and can be removed:
```bash
sudo swapoff -v /swap.img
sudo rm /swap.img
sudo sed -i '/swap.img/s/^/#/' /etc/fstab   # comment out rather than delete, for auditability
```
Verify: `free -h` shows `Swap: 0B / 0B / 0B`, `swapon --show` returns empty.

---

## 11. Verification — Run the Checklist

```bash
sudo mst start   # required after every reboot before this
bash ./gb300_l10_sw_checklist.sh
```

**Expected result on a correctly built, pre-rack L10 unit:**
- `OK` on every host-software, driver, CUDA, and CX8/BF3-firmware row.
- `N/A` (not `FAIL`) on: `Fabric Manager Service`, `Fabric Manager Version`, `IMEX Active
  State` — all three are structurally not applicable pre-rack, not faults.
- `MISSING` is expected for anything not yet installed at this stage of bring-up
  (`NVSwitch Devices`, `DCGM`, `Docker`, `containerd`, `nvidia-container-toolkit`,
  default runtime) — not a failure unless that install step should already be done.
- `CHECK` on out-of-band BMC/EROT/FPGA/VBIOS rows is a known, currently-open item on
  this reference build (see §1) — not something this SOP's steps above will fix; that's
  a separate firmware-update pass, not a bring-up defect.

**If you see anything else marked `CHECK` or `MISSING` that isn't in the lists above,
stop and consult the full build log before proceeding** — it's likely either a real
regression or a known issue with a documented fix already on record.

**If the checklist appears to hang indefinitely**, check whether a partner-diagnostics
(MODS) session is already running — MODS takes exclusive control of the GPUs for its own
tests, and the checklist has no timeout on checks that depend on driver access. Not a
checklist defect; wait for the diagnostics session to finish, or don't run both at once.

---

## 12. Image Capture (BCM / `cm-create-image`)

**Everything in this section happens *before* the `tar` command below — a tarball
can only contain what already exists on disk at capture time.** Checking these after
capturing is too late; if something's missing, the archive already reflects that.

**0. Root/boot device: convert from UUID to `by-path` — applies specifically to
ROM-writer/block-level cloning, not PXE per-node installs.** Block-level cloning
duplicates the filesystem UUID identically onto every unit. `by-path` addressing
(`/dev/disk/by-path/pci-<bdf>-nvme-1-part2`) is a valid one-time golden-image fix
**only if two hardware facts hold**: the NVMe has a fixed physical slot/BDF (no
reseat/hot-swap risk), and every unit in the fleet shares the same unified hardware
design. **If either assumption doesn't hold for your hardware, do not use this — fall
back to UUID-based addressing with real per-node regeneration on first boot instead.**
```bash
sudo sed -i \
  -e 's|/dev/disk/by-uuid/[0-9a-f-]*[[:space:]]*/[[:space:]]|/dev/disk/by-path/pci-<bdf>-nvme-1-part2 /  |' \
  -e 's|/dev/disk/by-uuid/[0-9A-F-]*[[:space:]]*/boot/efi|/dev/disk/by-path/pci-<bdf>-nvme-1-part1 /boot/efi|' \
  /etc/fstab
sudo sed -i 's/^#GRUB_DISABLE_LINUX_UUID=.*/GRUB_DISABLE_LINUX_UUID=true/' /etc/default/grub
sudo update-grub
grep -q 'root=/dev/disk/by-path' /boot/grub/grub.cfg && echo "OK: by-path root confirmed in grub.cfg"
```
Replace `<bdf>` with this platform's actual NVMe PCI address (confirm via `lspci` /
`ls -la /dev/disk/by-path/`, don't assume it matches another build's value). Reboot and
confirm no `UUID=` remains anywhere in the boot chain:
```bash
grep -i uuid /etc/fstab /etc/default/grub /boot/grub/grub.cfg   # expect no matches
cat /proc/cmdline   # expect root=/dev/nvme0n1p2 (or equivalent) - the kernel cmdline
                     # shows the *resolved* device node, not the literal by-path string;
                     # that's normal grub-probe behavior, not a sign it didn't take
```

**1. Confirm the driver was captured via `.run`, not apt:**
```bash
dpkg -l | grep -E "nvidia-open-580|nvidia-driver-580-open"   # expect NO output
```
If this shows anything, the driver was apt-installed at some point and `cm-create-image`
may silently reinstall an unpinned, newer version on rebuild — regardless of what §6
above did correctly. Fix this before capturing, not after.

**2. Config directory presence** — static directories, not per-node identity state, so
confirm/create once, no per-clone regeneration needed. Some BCM-provisioning pipelines
fail hard if these don't exist for their node-installer to write generated config into.
Not observed as a failure on this build's own bare-metal install, but costs nothing to
confirm before capture:
```bash
ls -la /etc/network/interfaces.d/ /etc/ntpsec/
# if either is missing:
sudo mkdir -p /etc/network/interfaces.d
sudo mkdir -p /etc/ntpsec
```

**3. Golden-image identity decision (make deliberately, don't default silently):**
decide whether `machine-id` and SSH host keys should be:
- **Stripped pre-capture** (each clone regenerates unique values on first boot), or
- **Left live** (every clone shares the same identity until something downstream
  regenerates them — acceptable only if the provisioning pipeline has its own
  regeneration mechanism, or if this is a single-purpose reference image, not a
  multi-clone golden image).

If stripping: `sudo truncate -s 0 /etc/machine-id` and `sudo rm -f /etc/ssh/ssh_host_*`
(both auto-regenerate at next boot via systemd/`ssh.service` — no other action needed).

**Now capture:**
```bash
sudo mkdir -p /root/bcm-image-export
sudo tar --numeric-owner --xattrs --acls -czpf /root/bcm-image-export/<image-name>.tgz \
  --exclude='./proc' --exclude='./sys' --exclude='./dev' --exclude='./run' \
  --exclude='./tmp' --exclude='./mnt' --exclude='./media' --exclude='./lost+found' \
  --exclude='./root/bcm-image-export' \
  -C / .
```

**Post-capture validation — confirm what actually got captured, not just what was
intended:**
```bash
tar -tzf /root/bcm-image-export/<image-name>.tgz | wc -l               # sane member count, no read errors
tar -tzf /root/bcm-image-export/<image-name>.tgz | grep '^\./etc/machine-id'
tar -tzf /root/bcm-image-export/<image-name>.tgz | grep '^\./etc/ssh/ssh_host'
```
The last two should show a present-but-empty `machine-id` and no host key files if you
stripped identity in step 3, or the live values if you deliberately chose to leave them.

---

## Known Issues Quick Reference

| Symptom | Cause | Fix |
|---|---|---|
| `nvidia-persistenced` inactive | Manually stopped (e.g. by diagnostics) or never started this boot | `sudo systemctl start nvidia-persistenced` |
| `nvidia-persistenced` disabled | Not currently root-caused on this build — has occurred without explanation | `sudo systemctl enable --now nvidia-persistenced`; escalate if it recurs |
| `mst status` shows no devices, or BF3/CX8 firmware version rows suddenly show `MISSING` after a reboot | MST not started this boot — the device tree is ephemeral and does not survive a reboot, including after BIOS/BMC updates | `sudo mst start` |
| CX8/BF3 firmware shows an old version after previously confirming the update | Confirmed to happen at least once this build, root cause unconfirmed | Re-flash per §5 above; check `ipmitool sel list` for anything unusual first |
| `mstflint`/`mstfwreset` fail with a device-parse error against `/dev/mst/*` paths | Tooling-version mismatch between `flint` and `mstflint`/`mstfwreset` on this build | Use `flint -d <pci-address>` (plain PCI address) instead |
| Fabric Manager / IMEX show inactive or N/A pre-rack | Expected — both require NVSwitch-tray-side components not present until L11 | No action; not a fault |
| `apt list --upgradable` shows a driver-adjacent package (e.g. `libnvidia-nscq`) jumping to a different major version | Package wasn't held | `sudo apt-mark hold <package>`; review the full list before ever running a bare `apt upgrade` on this stack |
| `gb300_l10_sw_checklist.sh` hangs indefinitely | A partner-diagnostics (MODS) session is already running and holding the GPUs exclusively | Wait for diagnostics to finish; don't run both at once |

**Numbers that look inconsistent but aren't — don't escalate these without checking here
first.** This platform surfaces several pairs of version-like fields that measure
genuinely different things and will never match each other, by design:

| You'll see | And also | Why they legitimately differ |
|---|---|---|
| `nvidia-smi`'s `CUDA Version: 13.0` | `nvcc --version` → `V13.0.88` | Different components, versioned independently since CUDA 11 — `13.0.88` is `nvcc`'s own build number for CUDA 13.0 Update 2, not a mismatch |
| `nvcc`/driver's `13.0`/`13.0.88` | `dpkg -l cuda-toolkit-13-0` → `13.0.2-1` | This is the only one of the three that shows the actual "Update 2" point release — the meta-package version, from `dpkg`, independent of whether the original installer `.deb` is still on disk |
| `dmidecode -s bios-version` (e.g. `00.58.03`) | An HMC/GA firmware bundle's own `SBIOS:` field (e.g. `02.06.06`) | Per Pegatron: the `dmidecode` value is their internal combined BIOS/BMC release number; the bundle's `SBIOS:` field is the underlying SBIOS component's own version *within* that release. Both correct, different layers |
| Redfish `FW_BMC_0` (e.g. `carlonext-bmc_0.80.07`) | Redfish `HGX_FW_BMC_0` (e.g. `GB200Nvl-26.07-1`) | Two separate BMC identities on this platform — this compute tray's own BMC vs. the HGX baseboard's BMC-domain firmware. Different components, don't share a version number |
| Checklist's `Fabric Manager Package Version` (tracks driver, e.g. `580.173.10`) | Checklist's `Fabric Manager Version` / NVOS-side GFM (e.g. `580.173.04`) | The former is this host's own inert package; the latter is the NVSwitch tray's actual Global Fabric Manager, on a completely independent release train — see §1's version table |

---

*For root-cause detail, full command output, and everything not included above,
see `gb300_l10_build_log.md`.*
