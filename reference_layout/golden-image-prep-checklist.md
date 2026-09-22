# Golden-Image Prep Checklist (Before ROM-Writer Capture)

Split into two phases, and the split matters — mixing them up is how this
mechanism silently breaks itself.

- **Phase A** — persistent config changes. Safe to do anytime, survive any
  number of reboots in between without consequence. Already reboot-tested
  on the reference node.
- **Phase B** — state that gets *consumed* by a reboot. Must be the very
  last thing done, with **zero reboots between Phase B and the ROM writer
  actually capturing the disk**. If a reboot happens in that window, the
  golden image gets captured in an already-regenerated state, and every
  future clone inherits that single value — silently reproducing the exact
  problem this whole checklist exists to prevent.

---

## Phase A — do anytime, reboot-safe

### A1. Switch root/boot to by-path addressing (one-time, applies to every clone as-is)

```bash
sudo sed -i \
  -e 's|/dev/disk/by-uuid/[0-9a-f-]*[[:space:]]*/[[:space:]]|/dev/disk/by-path/pci-0015:01:00.0-nvme-1-part2 /  |' \
  -e 's|/dev/disk/by-uuid/[0-9A-F-]*[[:space:]]*/boot/efi|/dev/disk/by-path/pci-0015:01:00.0-nvme-1-part1 /boot/efi|' \
  /etc/fstab
sudo sed -i 's/^#GRUB_DISABLE_LINUX_UUID=.*/GRUB_DISABLE_LINUX_UUID=true/' /etc/default/grub
sudo update-grub
grep -q 'root=/dev/disk/by-path' /boot/grub/grub.cfg && echo "OK: by-path root confirmed in grub.cfg"
```

**Confirmed working** on the reference node — post-reboot `/proc/cmdline`
shows `root=/dev/nvme0n1p2`, no `UUID=` anywhere. (Cmdline shows the
resolved device node, not the literal by-path string — that's normal
`grub-probe` behavior, not a sign the config didn't take effect.)

**Why this is safe as a one-time, cloned-as-is edit rather than needing
per-node regeneration:** this platform's M.2 NVMe has a fixed physical
slot/BDF with no reseat risk, and every node in the rack shares the same
unified hardware design — so `pci-0015:01:00.0-nvme-1` is the identical,
correct path on every single cloned node. Different in kind from the UUID
problem: UUID is filesystem-content-derived and therefore
identical-but-*meaningless* across clones; by-path is hardware-derived and
therefore identical-and-*correct*.

**If this ever stops being true** (board revision changes M.2 placement,
hot-swap bays introduced, a drive physically moved between slots during
repair) — revert to UUID-based addressing with real per-node regeneration.

This is Phase A, not Phase B, because it's a config file edit with no
"consumed by boot" behavior — reboot it a hundred times before capture and
it stays exactly as configured.

### A2. Install the first-boot regeneration mechanism (tooling-clarity only, not boot-critical)

```bash
sudo cp first-boot-regen.sh /usr/local/sbin/first-boot-regen.sh
sudo chmod 755 /usr/local/sbin/first-boot-regen.sh
sudo cp first-boot-regen.service /etc/systemd/system/first-boot-regen.service
sudo systemctl enable first-boot-regen.service
```

With root/boot addressed by-path (A1), this no longer does anything
boot-critical — it now only gives each node a genuinely unique filesystem
UUID for asset-tracking/tooling clarity. No `fstab`/`grub` edit, no reboot.

**This one is deceptively NOT fully Phase-A-safe on its own — read this
carefully.** `systemctl enable` is persistent and reboot-safe by itself.
But the service's trigger condition is `ConditionPathExists=!/var/lib/first-boot-regen-done`
— if this reference node reboots even once *after* this step but *before*
capture, the service will fire **on this node**, write the marker file,
and that marker gets captured into the golden image. Every future clone
would then already have the marker present and the service would **never
fire on any unit again, ever** — not just skipped once, permanently inert
fleet-wide, silently.

**Mitigation:** before handing off to the ROM writer (end of Phase B),
explicitly confirm the marker does NOT exist:
```bash
ls /var/lib/first-boot-regen-done 2>&1   # MUST report "No such file or directory"
```
If it exists, the mechanism has already fired on this reference node and
needs to be reset (`sudo rm -f /var/lib/first-boot-regen-done`) before
capture — otherwise every clone ships pre-disabled.

---

## Phase B — FINAL steps only, zero reboots after this point until the ROM writer has captured the disk

### B1. Empty machine-id (don't delete the file — empty it)

```bash
sudo truncate -s 0 /etc/machine-id
```

`systemd` auto-regenerates `machine-id` at boot whenever the file is
present but *empty* — standard convention used by Ubuntu's own cloud
images. **Consumed by the next reboot**, which is exactly why this is
Phase B: truncate it, then go straight to capture, don't leave the node
sitting in this state while other work continues.

### B2. Remove SSH host keys

```bash
sudo rm -f /etc/ssh/ssh_host_*
```

Ubuntu's `ssh.service` dependency chain regenerates any *missing* host key
type automatically at boot. Same Phase-B reasoning as B1 — a reboot in
between means this node's own keys become the ones every clone shares.

### B3. Verify the first-boot-regen marker is still absent (see A2's mitigation)

```bash
ls /var/lib/first-boot-regen-done 2>&1   # MUST report "No such file or directory"
```

### B4. Capture — hand off to the ROM writer now, no further commands on this node until it's done

The captured image will have: root/boot pinned via by-path (A1), the
regeneration service enabled with its marker confirmed absent (A2/B3),
empty `machine-id` (B1), and no SSH host keys (B2).

---

## EFI system partition UUID — deliberately not handled

The `/boot/efi` FAT32 volume ID (`364C-989E`) is left as-is, and no longer
matters for boot now that A1 addresses `/boot/efi` by-path too. If it
mattered for some other reason later, regenerating it safely would require
non-destructive `mtools` (`mlabel -N`), not `mkfs.vfat -i` (which reformats
and would destroy the bootloader files on that partition).

## What happens on each cloned unit's actual first boot

1. Boots normally via by-path root/boot — identical, correct path on every unit by hardware design, nothing to resolve or regenerate.
2. `systemd` sees empty `machine-id` → regenerates it uniquely, automatically.
3. `ssh.service`'s dependency sees missing host keys → generates fresh unique ones, automatically.
4. `first-boot-regen.service` fires (marker absent, confirmed in B3 before capture) → `tune2fs -U random` on root for tooling-clarity purposes only, writes the marker. No `fstab`/`grub` edit, no reboot — boot doesn't depend on this value.
5. Node is now running with a unique `machine-id`, unique SSH host keys, and a unique (but boot-irrelevant) filesystem UUID — all from a single first boot, no per-node manual step, no production-line touch.

## Open items — not yet validated end-to-end

- Phase A (by-path root/boot) confirmed working via an actual reboot on the reference node.
- Phase B has NOT yet been exercised against an actual ROM-writer-cloned unit — first real clone should be watched through the full "what happens on first boot" sequence above before trusting this at scale.
- Whether the ROM writer performs an offline block-level copy (assumed) vs. some other mechanism that might behave differently — not independently confirmed.
- "Unified hardware design across the rack" — the load-bearing assumption for the by-path approach — hasn't been explicitly confirmed by whoever owns the hardware BOM/board revisions, only assumed reasonable.
- `root=/dev/nvme0n1p2`'s own stability (as opposed to `by-path`'s) relies specifically on this platform having exactly one NVMe controller — true here, would need revisiting on a multi-NVMe-controller platform.
