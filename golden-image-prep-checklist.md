# Golden-Image Prep Checklist (Before ROM-Writer Capture)

Run once on the reference node, right before the ROM writer captures the disk image.
**Do not reboot this node after these steps** — a reboot here would consume the
"first boot" uniqueness on the golden master itself, and every clone would
inherit an already-regenerated (and therefore already-shared-again) state,
defeating the whole point.

## 1. Switch root/boot to by-path addressing (one-time, applies to every clone as-is)

```bash
sudo sed -i \
  -e 's|/dev/disk/by-uuid/[0-9a-f-]*[[:space:]]*/[[:space:]]|/dev/disk/by-path/pci-0015:01:00.0-nvme-1-part2 /  |' \
  -e 's|/dev/disk/by-uuid/[0-9A-F-]*[[:space:]]*/boot/efi|/dev/disk/by-path/pci-0015:01:00.0-nvme-1-part1 /boot/efi|' \
  /etc/fstab
sudo sed -i 's/^#GRUB_DISABLE_LINUX_UUID=.*/GRUB_DISABLE_LINUX_UUID=true/' /etc/default/grub
sudo update-grub
grep -q 'root=/dev/disk/by-path' /boot/grub/grub.cfg && echo "OK: by-path root confirmed in grub.cfg"
```

**Why this is safe as a one-time, cloned-as-is edit rather than needing
per-node regeneration:** this platform's M.2 NVMe has a fixed physical
slot/BDF with no reseat risk, and every node in the rack shares the same
unified hardware design — so `pci-0015:01:00.0-nvme-1` is the identical,
correct path on every single cloned node, not something that needs to be
rediscovered or regenerated per unit. This is different in kind from the
UUID problem below: UUID is filesystem-content-derived and therefore
identical-but-*meaningless-as-an-identifier* across clones, while by-path
is hardware-derived and therefore identical-and-*correct* across clones.

**If this ever stops being true** (a board revision changes M.2 placement,
hot-swap bays get introduced, a node's NVMe gets physically moved between
slots during repair) — this assumption breaks and root needs to go back to
UUID-based addressing, at which point `first-boot-regen.sh` would need its
`fstab`/`update-grub`/reboot steps restored (removed in step 2 below,
still visible in this script's git history / earlier version if needed).

## 2. Install the first-boot regeneration mechanism (tooling-clarity only, not boot-critical)

```bash
sudo cp first-boot-regen.sh /usr/local/sbin/first-boot-regen.sh
sudo chmod 755 /usr/local/sbin/first-boot-regen.sh
sudo cp first-boot-regen.service /etc/systemd/system/first-boot-regen.service
sudo systemctl enable first-boot-regen.service
```

With root/boot addressed by-path (step 1), this no longer does anything
boot-critical — it now only gives each node a genuinely unique filesystem
UUID for asset-tracking/tooling clarity (inventory systems, backup
catalogs, anything that indexes disks by UUID). No `fstab`/`grub` edit, no
reboot. Optional in principle; kept because it's low-cost and harmless, not
because boot depends on it anymore.

## 3. Empty machine-id (don't delete the file — empty it)

```bash
sudo truncate -s 0 /etc/machine-id
```

No custom script needed. `systemd` auto-regenerates `machine-id` at boot
whenever the file is present but empty — this is the standard convention
used by Ubuntu's own cloud images for exactly this purpose. Truncating
rather than deleting matters: some systemd versions only check for "empty",
not "missing".

## 4. Remove SSH host keys

```bash
sudo rm -f /etc/ssh/ssh_host_*
```

No custom script needed here either — Ubuntu ships a `ssh-keygen`
regeneration path (via `ssh.service`'s dependencies) that generates any
missing host key type automatically at boot. Deleting the files is enough;
each cloned node ends up with genuinely distinct host keys on first boot.

## 5. EFI system partition UUID — deliberately not handled

The `/boot/efi` FAT32 volume ID (`364C-989E`) is left as-is, and no longer
matters for boot at all now that step 1 addresses `/boot/efi` by-path too.
If it mattered for some other reason later, regenerating it safely would
require non-destructive `mtools` (`mlabel -N`), not `mkfs.vfat -i` (which
reformats and would destroy the bootloader files on that partition — do not
run that against a live ESP).

## 6. Capture

With the above done and **no reboot in between**, hand the disk to the ROM
writer for imaging now. The captured image will have: root/boot pinned via
by-path in `fstab`/`grub.cfg`, empty `machine-id`, absent SSH host keys, and
the regeneration service enabled but not yet fired (no marker file present).

## What happens on each cloned unit's actual first boot

1. Boots normally via by-path root/boot — identical, correct path on every unit by hardware design, nothing to resolve or regenerate.
2. `systemd` sees empty `machine-id` → regenerates it uniquely, automatically.
3. `ssh.service`'s dependency sees missing host keys → generates fresh unique ones, automatically.
4. `first-boot-regen.service` fires (marker absent) → `tune2fs -U random` on root for tooling-clarity purposes only, writes the marker. No `fstab`/`grub` edit, no reboot — boot doesn't depend on this value anymore.
5. Node is now running with a unique `machine-id`, unique SSH host keys, and a unique (but boot-irrelevant) filesystem UUID — all from a single first boot, no per-node manual step, no production-line touch.

## Open items — not yet validated end-to-end

- **Step 1 (by-path root/boot) confirmed working** on the reference node — post-reboot `/proc/cmdline` shows `root=/dev/nvme0n1p2` with no `UUID=` anywhere. Note: the kernel cmdline shows the resolved device node, not the literal by-path string from `fstab` — that's normal `grub-probe` behavior (it resolves the mounted device down to its real node), not a sign the by-path config didn't take effect. `fstab`'s by-path entries did their job; they just don't appear verbatim in the final `root=`.
- Steps 2–5 (first-boot-regen service, machine-id, SSH host keys, ESP UUID decision) still untested against an actual ROM-writer-cloned unit — first real clone should be watched through the full "what happens on first boot" sequence above before trusting this at scale.
- Confirm the ROM writer performs an offline block-level copy (not a live-running snapshot) — the "don't reboot before capture" requirement in step 6 assumes that.
- The by-path assumption (step 1) depends entirely on "unified hardware design across the rack" holding true for the life of this fleet. Worth a one-line confirmation from whoever owns the hardware BOM/board revisions that this isn't expected to change.
- Also worth noting: `root=/dev/nvme0n1p2`'s stability (as opposed to the by-path form) relies specifically on this platform having exactly one NVMe controller. Fine for this fleet's unified single-NVMe design; would need revisiting if ever copied to a platform with multiple NVMe controllers.
