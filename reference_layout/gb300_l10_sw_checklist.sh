#!/usr/bin/env bash
#
# gb300_l10_sw_checklist.sh
#
# Purpose : Display an L10 system-software checklist (component + installed
#           version) for a GB300 NVL reference layout bring-up, aligned to
#           the NVIDIA 2.0 release stack.
#
# Usage   : sudo ./gb300_l10_sw_checklist.sh [-o /path/to/logfile]
#
# Notes   : - Run as root (or with sudo) for full BIOS/BMC/PCIe visibility.
#           - Missing components are reported as [ MISSING ] rather than
#             causing the script to fail, so you can run this at any stage
#             of the bring-up process.
#           - Fill in EXPECTED_* variables below to match your NVIDIA 2.0
#             release note / compatibility matrix and get PASS/FAIL diffing.
#
# ------------------------------------------------------------------------
# Changelog
#   0.1.0  2026-08-05  Initial version. OS/kernel, driver/CUDA/GPU,
#                       NVLink/NVSwitch/FM, MOFED/DOCA, DCGM/container
#                       runtime sections. Bring-up still in progress -
#                       expect MISSING rows until later install stages.
#   0.2.0  2026-08-05  EXPECTED_KERNEL updated to match the Grace 64k-page
#                       HWE kernel (linux-nvidia-64k-hwe-24.04) instead of
#                       stock generic kernel. Added explicit PAGE_SIZE=65536
#                       check, since 64k pages are a hard requirement on
#                       Grace and worth catching automatically.
#   0.3.0  2026-08-05  Added "Kernel Package Held" and "unattended-upgrades"
#                       checks to catch apt-mark hold status and confirm
#                       automatic updates are disabled during bring-up.
#   0.3.1  2026-08-05  Split kernel-hold check into 3 rows (meta/image/
#                       headers) to match holding all three packages, not
#                       just the meta-package, since apt can otherwise
#                       still drift the underlying image/headers.
#   0.4.0  2026-08-05  EXPECTED_DRIVER, EXPECTED_DOCA updated to match the
#                       confirmed Host Software Components version matrix
#                       (driver 580.173.02, DOCA_Host 3.4.1-010000). Added
#                       MFT Tools and BF3 firmware version checks + expected
#                       values (4.36.0-147 / 32.49.1118). BF3 firmware check
#                       uses a placeholder mst device path - confirm actual
#                       path via `mst status` once MFT tools are installed.
#   0.4.1  2026-08-07  EXPECTED_CUDA corrected 12.8 -> 13.0 (matches Toolkit
#                       13.0.2). Previous value was an unverified assumption;
#                       confirmed via NVOnline 1160245 Table 2, which pairs
#                       CUDA Toolkit 13.0.2 with Datacenter Driver 580.173.02
#                       - an exact match to the already-installed/confirmed
#                       driver, giving high confidence in the pairing.
#   0.4.2  2026-08-07  Fixed two false-negative checks found during first
#                       full run: (1) "IOMMU Enabled" checked for an x86-style
#                       dmesg log string ('IOMMU enabled') that Grace/ARM never
#                       emits - platform uses SMMU instead, enabled via ACPI
#                       IORT rather than a boot-time log line. Replaced with a
#                       populated-/sys/kernel/iommu_groups/ count check, which
#                       is architecture-agnostic and reflects actual translation
#                       state rather than a specific kernel log message.
#                       (2) "CUDA Version (driver)" used
#                       `nvidia-smi --query-gpu=cuda_version`, which errors
#                       ("Field \"cuda_version\" is not a valid field to query")
#                       on this driver/nvidia-smi build. Replaced with parsing
#                       the "CUDA Version: X.Y" string from plain `nvidia-smi`
#                       header output instead.
#   0.4.3  2026-08-10  "nvcc (CUDA toolkit)" still reported MISSING when the
#                       script itself was run as `sudo ./gb300_l10_sw_checklist.sh`
#                       (its own documented Usage), even after adding
#                       /usr/local/cuda/bin to PATH via /etc/profile.d and
#                       /etc/bash.bashrc. Root cause: `sudo script.sh` is a
#                       non-interactive invocation, which never sources those
#                       files regardless of shell config - and sudo's own
#                       secure_path resets PATH independently besides. Fixed
#                       by adding /usr/local/cuda/bin to PATH defensively
#                       inside the script itself rather than relying on the
#                       caller's environment.
#   0.4.4  2026-08-10  Two corrections against NVOnline 1160245's full raw
#                       JSON component list (GB300MaxQNVL_72x1 2.0.0-build25),
#                       not just the Table 2 excerpt used for CUDA/driver in
#                       v0.4.1: (1) EXPECTED_FM corrected "570" -> "580.173.04"
#                       to match the confirmed GFM entry. (2) EXPECTED_MOFED
#                       removed entirely - confirmed via the full component
#                       list (every versioned item in the milestone checked,
#                       not just OFED-related ones) that MOFED/OFED has no
#                       independent version entry in this release; it's
#                       absorbed into DOCA_Host (already correct). The MOFED
#                       check is now informational-only, no PASS/FAIL target,
#                       since holding it to a target that doesn't exist in the
#                       source of truth would just reintroduce a different
#                       false "CHECK"/stale-value problem.
#   0.4.5  2026-08-10  Added "CX8 Firmware Version" check (EXPECTED_CX8_FW =
#                       40.49.1118, per Host Software Components matrix /
#                       NVOnline 1160245 "CX8" entry) - previously only BF3
#                       firmware had a version check, with no ConnectX-8
#                       equivalent despite CX8 FW being tracked elsewhere in
#                       the build log. Queries mt4131_pciconf0 (card 1 of 4;
#                       same placeholder-path caveat as the existing BF3
#                       check applies - confirm via `mst status` and adjust,
#                       or extend to loop over all 4 cards if per-card
#                       drift matters).
#                       Deliberately NOT adding a "BF3 DPU OS version" check:
#                       this build uses the firmware-only BF3 bundle (not the
#                       OS+firmware bundle) because BF3 is configured in NIC
#                       mode, where the DPU's Arm cores don't run a
#                       customer-facing OS. There is no OS version to read on
#                       this design, so the row would always read MISSING
#                       with no fix available. Waived for now; revisit only
#                       if BF3 mode changes to embedded/DPU mode.
#   0.4.6  2026-08-10  "Fabric Manager Service"/"Fabric Manager Version"
#                       reclassified from MISSING to a new N/A status (added
#                       note_na() helper + blue [N/A] row, excluded from the
#                       MISSING tally). Root cause: on the GB300 NVL72
#                       rack-scale design, the NVLink switch trays are
#                       self-contained managed switches running their own
#                       NVOS - fabric management lives there, not on the
#                       compute tray host. This host will never run
#                       `nvidia-fabricmanager`/`nv-fabricmanager` regardless
#                       of bring-up stage, racked or not, so treating it as
#                       MISSING was a structural false-negative, not
#                       deferred work (same category as "NVSwitch Devices",
#                       left as-is for now since it's a single-row informal
#                       case rather than a second N/A conversion in this
#                       pass). Simply dropping the EXPECTED_FM comparison
#                       (the MOFED v0.4.4 pattern) was considered and
#                       rejected - MOFED was present with no target to check
#                       against, so it resolved to OK; Fabric Manager is
#                       structurally absent here, so it would still read
#                       MISSING regardless of any target comparison. Needed
#                       an actual new status, not just a dropped target.
#                       EXPECTED_FM retained (not removed like EXPECTED_MOFED)
#                       since GFM 580.173.04 is still a real, valid component
#                       version per the NVOnline source of truth - it's just
#                       verified on the NVSwitch/NVOS side of bring-up, not by
#                       this script. Value is now referenced in the N/A row's
#                       message as a pointer for whoever does that check.
#   0.4.7  2026-08-10  Added explicit root-privilege check (exits with a
#                       clear error if EUID != 0) instead of relying solely
#                       on the "Run as root (or with sudo)" line in the
#                       Usage/Notes header comment. Several checks fail
#                       silently without root (dmidecode, mstflint/flint,
#                       DCGM, some /sys and PCIe config-space reads) and
#                       previously would just report as [MISSING] with no
#                       indication that privilege - not an actual absent
#                       component - was the cause.
#   0.4.8  2026-08-11  Added "IMEX Service"/"IMEX Version" checks - this had
#                       never been in the script at any prior version, not
#                       dropped by an earlier edit. Placed in the NVLink/
#                       NVSwitch/Fabric Manager section, right after the
#                       Fabric Manager N/A rows. EXPECTED_IMEX="580.173.02",
#                       same value as EXPECTED_DRIVER, since IMEX is installed
#                       via nvidia-imex-aarch64-580.173.02.run alongside the
#                       driver .run (build log §7) rather than as an
#                       independently-versioned package.
#                       Unlike Fabric Manager, this is a real check() row, not
#                       note_na(): the daemon/service genuinely install and
#                       run on this compute-tray host at any bring-up stage -
#                       IMEX just can't do anything *useful* without NVLink
#                       domain peers to export/import GPU memory with on a
#                       single un-racked L10 tray. "Can't work alone" affects
#                       what IMEX *does*, not whether it's installed/queryable
#                       here, so MISSING here would be a real problem, not a
#                       structural non-applicability like Fabric Manager.
#                       Version parsed from `nvidia-imex --version` output
#                       ("IMEX version is: X.Y") per NVIDIA's MNNVL User
#                       Guide verification doc.
#   0.4.9  2026-08-11  Fixed "IMEX Service" to compare against "active"
#                       instead of accepting any non-empty output. Same bug
#                       shape as the pre-v0.4.6 Fabric Manager rows, just
#                       inverted: a live run came back `inactive [OK]` -
#                       check() marks any non-empty systemctl output OK when
#                       no expected value is given, same as the intentional
#                       "unattended-upgrades" pattern where inactive IS the
#                       desired state. For IMEX it isn't; the omission was a
#                       genuine oversight, not a deliberate N/A/informational
#                       choice like Fabric Manager. Root cause of the
#                       inactive service itself (why it stopped after the
#                       §7 install) is a separate, real investigation - this
#                       fix only makes the checklist actually catch it going
#                       forward instead of silently reporting OK.
#   0.4.10 2026-08-11  v0.4.9's fix didn't actually work - re-ran with the
#                       same expected="active" and IMEX Service still showed
#                       `inactive [OK]`. Root cause: check() does a SUBSTRING
#                       match (`$out == *"$expected"*`), and "inactive"
#                       literally contains "active" as a substring (in +
#                       active). Any expected="active" comparison against an
#                       inactive/failed/activating systemd state beginning or
#                       containing that substring will silently pass. Fixed
#                       by rewriting the command itself to do an exact
#                       comparison and only echo "active" on a true match,
#                       same boolean-echo pattern already used for "IOMMU
#                       Enabled" - empty output (MISSING) on anything else,
#                       rather than relying on check()'s substring compare at
#                       all. Verified against the actual check() function
#                       (not just eyeballed) with active/inactive/failed
#                       systemctl states before shipping this fix - v0.4.9
#                       was shipped without that verification, which is how
#                       the substring bug got through.
#                       Not fixed globally in check() itself (leaving
#                       substring matching as the default) since several
#                       existing rows depend on substring matching on purpose
#                       (e.g. version strings with surrounding text like
#                       "Cuda compilation tools, release 13.0, V13.0.88").
#                       Worth revisiting if another exact-match-sensitive
#                       case like this one shows up.
#   0.4.11 2026-08-11  v0.4.10's fix was technically correct but checking the
#                       wrong thing. Build log §7/§7c already documented,
#                       before this checklist row even existed, that
#                       `inactive (dead)` is IMEX's *expected* clean-exit
#                       state at L10 - it finds no NVSwitch/GFM fabric peers
#                       on a single un-racked tray and exits rather than
#                       staying resident, same underlying reason as Fabric
#                       Manager. Requiring "active" meant this row would
#                       report MISSING forever on any un-racked L10 unit,
#                       even when everything is working exactly as designed -
#                       a false negative, not a real problem.
#                       Split "IMEX Service" into two separate checks that
#                       ask different questions instead of one conflated
#                       one: "IMEX Service (enabled)" checks systemd
#                       enablement (`systemctl is-enabled`, expects
#                       "enabled") - this IS meaningful at any bring-up
#                       stage and a real MISSING here would be a real
#                       problem, unlike Fabric Manager. "IMEX Active State"
#                       is now note_na(), same treatment as Fabric Manager,
#                       since "active" genuinely isn't meaningful pre-rack.
#   0.4.12 2026-08-11  Refined the "IMEX Active State" N/A message: "active"
#                       requires two separate conditions, not just "racked" -
#                       GFM actually functioning on the NVSwitch tray, AND
#                       this node's IMEX peer config populated with the
#                       NVLink domain member IPs (nodes_config.cfg). Message-
#                       only change, no logic difference from v0.4.11.
#   0.4.13 2026-08-11  Fixed BF3/CX8 Firmware Version showing MISSING after
#                       a routine reboot (this time triggered by a BIOS/BMC
#                       update, but root cause is unrelated to that content).
#                       Root cause: build log §10 ran `mst start` for the
#                       firmware burn, then explicitly `mst stop`'d
#                       afterward - the /dev/mst/* device tree it creates is
#                       ephemeral and was never set up to persist across a
#                       reboot. The script itself never called `mst start`
#                       either; it just assumed /dev/mst/* already existed
#                       from residual manual state (someone running it
#                       during §12's Ansible work, etc.) - explains why
#                       earlier runs showed OK and this one didn't, with
#                       nothing to do with the BIOS/BMC content itself. Will
#                       recur after ANY reboot, not just this one, until
#                       fixed. Added an idempotent `mst start` immediately
#                       before the BF3/CX8 checks so the script is
#                       self-sufficient instead of depending on leftover
#                       state from something else.
#   0.4.14 2026-08-11  Added "Out-of-Band Firmware (Redfish)" section -
#                       CPLD/EROT/HMC/FPGA, confirmed out-of-band-only per
#                       §17/§20. Discovers BMC IP in-band via `ipmitool lan
#                       print 1`; if empty (not configured, or IPMI hidden
#                       from host), stops and reports N/A rather than
#                       attempting a doomed Redfish call. Uses raw curl+jq
#                       against .../FirmwareInventory?expand=.$levels=1
#                       (single call for all components+versions) rather
#                       than the nvfwupd tool, per NVIDIA's own DGX GB Rack
#                       Scale Systems Redfish command reference - avoids an
#                       nvfwupd-binary dependency. BMC_USER/BMC_PASS default
#                       to the MaxQ factory account (root/0penBmc, per this
#                       unit), overridable via env var for units with
#                       rotated credentials. Component Id strings filtered
#                       by keyword (CPLD|EROT|HMC|FPGA|BMC) rather than
#                       exact match, since confirmed examples varied by BMC
#                       vendor/platform (CPLDMB_0 vs FW_CPLD_0 vs
#                       HGX_FW_CPLD_0) and this platform's actual Id strings
#                       aren't yet confirmed - tighten once known. -k (skip
#                       TLS verify) used since BMCs commonly run self-signed
#                       certs - flagged in comments, not silently bypassed.
#   0.4.15 2026-08-11  v0.4.14's single-call ?expand=.$levels=1 confirmed NOT
#                       honored by this unit's actual Pegatron-built BMC
#                       (Redfish 1.17.0) - it silently returned the plain
#                       unexpanded Members list (only @odata.id, no Id/
#                       Version), which would have made the jq filter always
#                       find nothing and fall through to a false "query
#                       failed" N/A on every run. NVIDIA's doc syntax was
#                       apparently AMI-BMC-specific, not universal - rather
#                       than guess at another vendor-specific expand syntax
#                       that might differ yet again elsewhere in the rack,
#                       switched to a guaranteed-correct two-step approach:
#                       GET the plain Members list, filter candidate URIs by
#                       keyword, then GET each matched component
#                       individually for its Version. ~12 HTTP calls on this
#                       unit instead of 1 - acceptable for a one-time
#                       checklist run, prioritizing correctness over call
#                       count. Real component Id strings confirmed against
#                       this unit's BMC: no Id literally contains "HMC" -
#                       exposed as FW_BMC_0/HGX_FW_BMC_0 instead, already
#                       caught by the BMC keyword.
#   0.4.16 2026-08-11  Confirmed working on a real unit (12/12 components
#                       resolved) but the single semicolon-joined row was
#                       hard to read - split into one ROWS entry per
#                       component ("Out-of-Band FW: <Id>" / version / OK)
#                       instead of concatenating all 12 into one wide value
#                       string. Summary OK count now reflects each component
#                       individually rather than counting the whole out-of-
#                       band block as a single row.
#   0.4.17 2026-08-13  Added "CUDA Toolkit (meta-pkg)" row, reading the
#                       cuda-toolkit-13-0 meta-package version via
#                       dpkg-query (13.0.2-1). Distinct from the two
#                       existing CUDA-related rows: "CUDA Version (driver)"
#                       is nvidia-smi's major.minor-only field (13.0, no
#                       update number by design), "nvcc" is nvcc's own
#                       independently-versioned component build (13.0.88).
#                       Neither of those could ever show "13.0.2" - this row
#                       is the only place that update-release number
#                       actually lives in the checklist. Confirmed
#                       independent of the original cuda-repo-*.deb still
#                       being present on disk - reads from dpkg/apt package
#                       metadata, not the installer file.
#   0.4.18 2026-08-XX  Added "Fabric Manager Package (if present)" check.
#                       Does NOT change the two existing v0.4.6 Fabric
#                       Manager N/A rows above it, and does not weaken that
#                       finding - fabric management still genuinely runs on
#                       the NVSwitch tray's own NVOS, never this host,
#                       functionally unchanged. This is a *new, additional*
#                       row for a *new* reason: build log §25 now has
#                       `nvidia-fabricmanager` (NOTE: no "-580" suffix -
#                       this local-repo package's naming differs from the
#                       "-580"-suffixed package used on a different rack's
#                       BCM pipeline; an earlier draft of this check queried
#                       the wrong name, corrected here) matched to this
#                       layout's 580.173.02 driver, sourced from NVOnline's
#                       nvidia-driver-local-repo-ubuntu2404-580.173.02
#                       package, deliberately pre-installed and masked on
#                       this reference layout, purely as future-proofing
#                       against a `cm-create-image` BCM finalize-stage
#                       failure if this layout is ever used as a BCM
#                       software-image source (unconditional `systemctl
#                       disable nvidia-fabricmanager` fails the whole build
#                       if no unit exists to disable - unrelated to whether
#                       FM is functionally needed on this host, see §25 for
#                       full reasoning). This new check is defense-in-depth
#                       against that precaution being applied incorrectly -
#                       specifically, installed but left un-masked, which
#                       would be a real (if inert-until-started) problem
#                       worth flagging, not something to bury in an N/A row.
#                       Confirmed NOT theoretical: the package's own postinst
#                       enables itself by default on install (creates a
#                       multi-user.target.wants symlink) before any manual
#                       mask step runs - if that step is ever skipped on a
#                       future rebuild, this check is what would catch it.
#                       Three-way result, NOT tallied as MISSING/N/A in
#                       either the "not installed" or "masked correctly"
#                       cases, since neither represents a problem:
#                       package absent -> note_na() (fine, precaution is
#                       optional, not required for this host's own
#                       bring-up); present + masked -> OK; present but NOT
#                       masked -> CHECK/"NEEDS REVIEW" (yellow, not
#                       MISSING/red - package existing-but-misconfigured is
#                       a different situation than something genuinely
#                       absent, and conflating the two would make the
#                       MISSING tally less trustworthy as a signal).
#   0.4.19 2026-08-31  Fixed v0.4.18's "Fabric Manager Package (if present)"
#                       check reporting N/A/"not installed" on a real host
#                       where nvidia-fabricmanager WAS genuinely installed
#                       and correctly masked. Root cause: the check used
#                       `dpkg -l ... | grep '^ii'`, which only matches the
#                       unheld "install, installed" status - but this same
#                       package is meant to be `apt-mark hold`-ed per §25
#                       (to prevent drift), which flips dpkg's status column
#                       to `hi` ("hold, installed"), not `ii`. This is the
#                       exact same status-parsing pitfall already worked
#                       around elsewhere in this project's BCM-image
#                       verification steps (`^[hi]i` used there for the
#                       same reason, on held kernel packages) - reintroduced
#                       here by not applying the same lesson consistently.
#                       Fixed properly this time by switching to
#                       `dpkg-query -W -f='${Status}' | grep "ok installed"`,
#                       which checks the package's Status field directly and
#                       is correct regardless of hold state, rather than
#                       pattern-matching `dpkg -l`'s fixed-width, hold-
#                       sensitive table columns (which `dpkg`'s own
#                       documentation notes isn't intended for scripting in
#                       the first place).
#   0.4.20 2026-09-02  Added "Disk Hygiene / Repo Cleanup" section (build log
#                       §22a). Purpose: this checklist previously only ever
#                       checked for PRESENCE of expected components, never
#                       ABSENCE of things deliberately removed - so if
#                       cuda-repo-ubuntu2404-13-0-local (3.6G) or
#                       nvidia-driver-local-repo-ubuntu2404-580.173.02 (573M)
#                       ever get reinstalled (e.g. someone re-runs the CUDA
#                       install steps from §8 on a rebuild/re-clone without
#                       re-reading §22a), the ~4.4G they reclaim would quietly
#                       come back with nothing here to catch it. Reports OK if
#                       purged, CHECK (not MISSING - the package existing
#                       isn't a functional defect, just a footprint one) if
#                       still/again installed, noting the size and pointing at
#                       §22a. Uses the same `dpkg-query -W -f='${Status}'`
#                       pattern as the v0.4.19 Fabric Manager fix, for the
#                       same hold-state-safety reason.
#                       Also added a swap check: BCM's own category disk-setup
#                       XML (confirmed in §22a) defines no swap partition/file
#                       at all for this reference layout, so any active swap
#                       device is reported CHECK (informational, not
#                       PASS/FAIL - a genuinely reprovisioned node with
#                       different RAM might legitimately want swap; this just
#                       flags it for a human to confirm intentional rather
#                       than silently ignoring it).
#   0.4.21 2026-09-14  2.0.0GA reconciliation (build log §0a). NVIDIA's
#                       official GA release notes (RN-11874-001) supersede
#                       the RC4 metadata file (NVOnline 1160245) everything
#                       through v0.4.20 was pinned against.
#                       (1) EXPECTED_DRIVER 580.173.02 -> 580.173.10.
#                       (2) EXPECTED_IMEX now derived as "$EXPECTED_DRIVER"
#                       instead of a separate literal, so it can't be left
#                       stale by omission on a future driver bump the way
#                       it nearly was here.
#                       (3) EXPECTED_FM corrected from a stale, and on
#                       reflection never-correct, "580.173.04" (NVOnline
#                       1160245's RC4 "GFM:" field) to "$EXPECTED_DRIVER".
#                       Root cause: the host-side `nvidia-fabricmanager`
#                       package (build log §25) is sourced from
#                       nvidia-driver-local-repo-ubuntu2404-<driver-version>
#                       and versioned <driver-version>-1ubuntu1 - it tracks
#                       the driver branch, not an independent release train.
#                       The v0.4.4 "Finding 2" correction (570 -> 580.173.04)
#                       fixed a stale value but attributed it to the wrong
#                       component; 580.173.04 most likely describes the
#                       NVSwitch tray's own NVOS-side Fabric Manager, which
#                       this script cannot see and which is NOT confirmed to
#                       equal either the old or new value - the
#                       "Fabric Manager Version" note_na message was
#                       rewritten to stop implying otherwise.
#                       (4) Added an actual version check ("Fabric Manager
#                       Package Version") for the installed
#                       nvidia-fabricmanager package against EXPECTED_FM -
#                       previously only masked-state was checked, so a
#                       package installed against a stale driver branch
#                       would have silently read OK.
#                       (5) Parameterized the "Stale NVIDIA Driver Repo Pkg"
#                       check's package name on EXPECTED_DRIVER instead of a
#                       hardcoded 580.173.02 suffix, for the same
#                       stale-by-omission reason as (2).
#                       (6) No NMX-M check exists in this script (build-log-
#                       only tracking) - no code change needed there, but
#                       the GA notes give a clean 85.1.1100 vs. the RC4-era
#                       build log's malformed filename-as-version string;
#                       see build log §0a.
#                       (7) EXPECTED_CUDA/_CUDA_TOOLKIT/_DOCA/_MFT/_BF3_FW/
#                       _CX8_FW confirmed unchanged by GA - comments updated
#                       to say so explicitly rather than leaving silence
#                       that could read as "not yet checked."
#   0.4.22 2026-09-14  Added "Persistence Daemon (enabled)" check (build log
#                       §7f) after nvidia-persistenced was found silently
#                       `disabled` (systemd enablement) on carlonext despite
#                       §7e's original enabled+reboot-survived confirmation -
#                       root cause not established. The existing "Persistence
#                       Mode" row only reads nvidia-smi's current runtime
#                       state, which can show Enabled right up until the next
#                       reboot even with the daemon disabled underneath it -
#                       this new row checks `systemctl is-enabled` directly,
#                       so a repeat of this regression won't hide behind a
#                       still-passing runtime check.
#   0.4.23 2026-09-14  Added "Held: libnvidia-nscq" / "Held: nvidia-modprobe" /
#                       "Held: nvidia-fabricmanager" checks (build log §7g).
#                       Found live, during the GA driver bump: libnvidia-nscq
#                       was completely unheld and showed an available "apt
#                       upgrade" target on a different major driver branch
#                       (615.x) entirely, not a point release - a real
#                       mismatch risk against the pinned 580.x stack, and
#                       nothing in this script would have caught it. The
#                       other two happened to already be protected by
#                       existing process, not by anything this script
#                       checked - closing that gap now rather than relying
#                       on it being noticed by hand again next time.
#   0.4.24 2026-09-14  Out-of-Band Firmware (Redfish) section now compares
#                       BMC/EROT/CPLD/SMA/HMC-GPU component versions against
#                       real GA-sourced targets (build log §0a) instead of
#                       reporting everything found as an unconditional OK.
#                       This wasn't theoretical: this same run's own earlier
#                       output showed HGX_FW_BMC_0 at GB200Nvl-25.09-2 and
#                       all 5 HGX_FW_ERoT_* entries at 01.04.0031.0000_n04,
#                       both stale against GA's GB200Nvl-26.07-1 /
#                       01.04.0055.0000_n04 - and the old code would have
#                       kept reporting all of it OK forever, since there was
#                       no comparison value available when this section was
#                       first written. Also expanded the discovery filter
#                       (CPLD|EROT|HMC|BMC|FPGA -> added SMA|GPU) since §0a's
#                       MCU/HMC baseline includes SMA and GPU-under-HMC
#                       fields that never appeared in any run's output under
#                       the old filter - not yet confirmed whether that's
#                       because this unit's BMC has no separately-exposed
#                       member for them or because they exist under some
#                       other unmatched name.
#   0.4.25 2026-09-14  Corrected a mapping error from v0.4.24, caught before
#                       it could cause a false negative: EXPECTED_HGX_GPU_FW
#                       was added assuming the GA release notes' HMC "GPU"
#                       field was a separate out-of-band Redfish-queryable
#                       firmware component. It isn't - it's VBIOS, in
#                       NVIDIA's raw-hex notation, same field "VBIOS Version"
#                       already reads via nvidia-smi. Removed the *GPU* match
#                       arm from the Redfish component-comparison case
#                       (dead code anyway - no run this session ever
#                       surfaced a GPU-matching Redfish component, consistent
#                       with this correction) and from the discovery filter.
#                       Added EXPECTED_VBIOS="97.10.7D.00.16" and wired it
#                       into the existing "VBIOS Version" check, which has
#                       had no comparison target at all since it was first
#                       added - a real gap, not just a missed wiring. This
#                       also reopens an unresolved thread from build log §16
#                       (RC4 era): that section logged VBIOS as
#                       "97.10.7D.00.0D" as a "may just be notation, not
#                       confirmed" awareness note with no EXPECTED_VBIOS to
#                       act on. GA's value shares the exact same "7D" segment
#                       (only the last segment moved, 0D->16, a plausible
#                       RC4->GA build increment) - the same segment agreeing
#                       across two independent NVIDIA metadata sources weeks
#                       apart, while this host's actual installed VBIOS
#                       (97.10.59.00.13) has stayed unchanged throughout,
#                       is stronger evidence of a real mismatch than §16's
#                       original framing gave it credit for.
#   0.4.26 2026-09-14  Fixed a real bug in v0.4.24/v0.4.25's own change,
#                       caught on first live run on carlonext: script exited
#                       with "EXPECTED_VBIOS: unbound variable" before
#                       reaching the Out-of-Band Firmware section at all.
#                       Root cause: EXPECTED_HGX_BMC_FW / _EROT_FW / _CPLD_FW
#                       / _MCU_SMA_FW / _VBIOS were declared down near §6b's
#                       Redfish section instead of in the main "§0. Config:
#                       expected versions" block at the top where every other
#                       EXPECTED_* variable lives - under `set -u`, the
#                       "VBIOS Version" check (which runs much earlier, in
#                       the NVIDIA Driver/CUDA/GPU section) referenced
#                       EXPECTED_VBIOS before that later assignment had ever
#                       executed, which is a hard error regardless of where
#                       else in the file the variable eventually gets set.
#                       Fixed by moving all 5 declarations up to the correct
#                       location - values unchanged, only the location moved.
#                       Verified with a static use-before-definition scan
#                       across every EXPECTED_* variable in the script (not
#                       just the ones just touched) to confirm no other
#                       instance of this same class of bug exists elsewhere.
#   0.4.27 2026-09-14  Two real corrections from reading the full GA release
#                       notes PDF (RN-11874-001_2.0.0GA) for the first time,
#                       rather than the individual page images used earlier
#                       in this build:
#                       (1) EXPECTED_DCGM corrected "3.3" -> "4.6.0". "3.3"
#                       had been an unsourced placeholder since v0.1.0 - never
#                       verified against anything. GA's Table 9 gives the
#                       real target (DCGM 4.6.0, NVOnline 1139880).
#                       (2) Added EXPECTED_GFM_NVOS="580.173.04", CONFIRMED
#                       via the GA notes' "GB300 Switch Tray > NVOS" table -
#                       this is a real, independent version for the
#                       NVSwitch-tray-side Global Fabric Manager, separate
#                       from EXPECTED_FM (this host's own inert
#                       nvidia-fabricmanager package, which tracks the
#                       driver). The v0.4.24 hedge ("580.173.04 most likely
#                       refers to the NVOS-side FM, not confirmed") was
#                       correct and is now directly confirmed, not just
#                       inferred. "Fabric Manager Version" N/A message
#                       updated accordingly - was incorrectly saying
#                       "not confirmed against GA" when it now is.
#   0.4.28 2026-09-14  Fixed a real false-positive bug, caught on a live run:
#                       "FW_E1S_CPLD_0/1: 0b.04.02 (expected 0.22)" showed
#                       CHECK, but 0.22 is the HGX baseboard CPLD's target
#                       (§0a) - FW_E1S_CPLD_0/1 is the E1S NVMe drive-carrier
#                       board's own, unrelated CPLD. The v0.4.24 case match
#                       used a bare "*CPLD*" substring pattern, which caught
#                       both components and compared one against the other's
#                       spec - not a missed check, an actively wrong one.
#                       Fixed by anchoring every pattern (EROT/CPLD/FPGA/SMA/
#                       BMC) to the confirmed "HGX_FW_" prefix instead of
#                       loose substrings, so only the components this build
#                       log has actually confirmed the naming convention for
#                       get compared at all. Also added HGX_FW_FPGA_* ->
#                       EXPECTED_HGX_FPGA_FW="1.66" (GA release notes HMC
#                       FPGA field, §0b) - this host's live "1.60" reading
#                       had been silently reported OK with no target at all
#                       until now; it's real drift, same shape as the
#                       already-known BMC/EROT staleness. Explicitly NOT
#                       "0.24" - that's the physically separate NVSwitch-
#                       tray's own FPGA (§0b's Switch Tray BMC+FPGA+EROT
#                       bundle), not applicable to this un-racked compute
#                       host regardless of naming similarity.
#   0.4.29 2026-09-16  Added "Golden-Image / Pre-Capture Readiness" section
#                       (build log §25 / SOP §12) - two checks that were
#                       previously manual-only SOP steps, easy to forget
#                       right before an image capture:
#                       (1) "Config Dirs (interfaces.d/ntpsec)" - straight
#                       PASS/FAIL presence check, some BCM-provisioning
#                       pipelines fail hard without these existing.
#                       (2) "Boot Device Addressing" - deliberately
#                       INFORMATIONAL, not PASS/FAIL, unlike everything
#                       else added to this section. UUID-based addressing
#                       is completely normal during ordinary bring-up and
#                       only becomes a decision point right before image
#                       capture (and only then if the by-path fix's
#                       hardware-uniformity assumption actually holds) -
#                       this script has no way to know "are we about to
#                       capture right now" vs "mid bring-up", so it reports
#                       current state only rather than asserting a target
#                       that would false-flag every normal build.
# ------------------------------------------------------------------------

SCRIPT_VERSION="0.4.29"

set -uo pipefail

# Ensure the CUDA toolkit is discoverable even when this script is invoked
# non-interactively (e.g. `sudo ./gb300_l10_sw_checklist.sh`, per the Usage
# line above) or via cron/CI. Non-interactive shells don't source
# /etc/profile.d/, /etc/bash.bashrc, or ~/.bashrc, and sudo's own secure_path
# resets PATH regardless - so relying on the caller's shell environment for
# this is not reliable. Handled defensively here instead.
[[ -d /usr/local/cuda/bin ]] && PATH="/usr/local/cuda/bin:$PATH"

# ----------------------------------------------------------------------------
# Root check: many rows (dmidecode, mstflint/flint, DCGM, some /sys and PCIe
# config-space reads) silently return empty rather than erroring when run
# unprivileged, so a non-root run doesn't fail loudly - it just quietly
# reports a wall of false [MISSING] rows instead. Enforce here rather than
# leaving this as a comment in the Usage/Notes header, since that's easy to
# skim past.
# ----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: this script must be run as root (sudo)." >&2
  echo "       Several checks (dmidecode, mstflint/flint, DCGM, PCIe config-space" >&2
  echo "       reads) fail silently without root and will misreport as [MISSING]." >&2
  echo "       Re-run as: sudo $0 $*" >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# 0. Config: expected versions (edit to match your NVIDIA 2.0 release matrix)
# ----------------------------------------------------------------------------
EXPECTED_OS="24.04"
EXPECTED_KERNEL="nvidia-64k"   # Grace requires the 64k-page HWE kernel flavor;
                                # substring match only (exact build # will drift
                                # with HWE point updates, e.g. 6.17.0-1029)
EXPECTED_DRIVER="580.173.10"   # per 2.0.0GA release notes (RN-11874-001), corrected
                                # 2026-09-14 from the RC4-era 580.173.02 - see build
                                # log §0a. (NVIDIA-kernel-module-source-580.173.10)
EXPECTED_CUDA="13.0"          # corrected from stale 12.8 - confirmed via NVOnline 1160245;
                                # unchanged by the GA reconciliation (§0a) - still 13.0.2
EXPECTED_CUDA_TOOLKIT="13.0.2" # cuda-toolkit-13-0 meta-package version, per the
                                # local-repo .deb this was installed from
                                # (cuda-repo-...-13-0-local_13.0.2-580.95.05-1)
                                # paired with Datacenter Driver 13.0.2 in both RC4 and
                                # GA sources - unchanged by the driver version bump
# EXPECTED_MOFED removed - confirmed via NVOnline 1160245 (full component list
# checked) that MOFED/OFED is NOT independently versioned in this release; it
# is absorbed into DOCA_Host (3.4.1-010000, already correct above). The
# "MOFED Version" check below is now informational-only (no PASS/FAIL target).
EXPECTED_DOCA="3.4.1"          # per Host Software Components matrix (3.4.1-010000);
                                # unchanged by GA (§0a)
EXPECTED_DCGM="4.6.0"          # corrected 2026-09-14: was "3.3" since v0.1.0, an
                                # unsourced placeholder guess that was never
                                # actually verified against anything. GA release
                                # notes Table 9 gives the real target: DCGM 4.6.0,
                                # NVOnline 1139880.
EXPECTED_MFT="4.36.0"          # per Host Software Components matrix (4.36.0-147);
                                # unchanged by GA (§0a)
EXPECTED_BF3_FW="32.49.1118"   # per Host Software Components matrix; unchanged by GA (§0a)
EXPECTED_CX8_FW="40.49.1118"   # per Host Software Components matrix (CX8 entry,
                                # NVOnline 1160245); confirmed via ibstat mlx5_5;
                                # unchanged by GA - also matches GA notes' "CX8 N/S" section
EXPECTED_IMEX="$EXPECTED_DRIVER" # matches EXPECTED_DRIVER - installed via
                                # nvidia-imex-aarch64-<ver>.run (build log §7), same
                                # version as the driver .run, not a separate release
                                # train. Now derived from the variable instead of a
                                # separate literal so a future driver bump can't leave
                                # this one stale by omission.
EXPECTED_FM="$EXPECTED_DRIVER" # corrected 2026-09-14 (build log §0a): the host-side
                                # `nvidia-fabricmanager` package (§25) is sourced from
                                # nvidia-driver-local-repo-ubuntu2404-<driver-version>
                                # and versioned <driver-version>-1ubuntu1 - it tracks
                                # the Datacenter Driver branch, not an independent
                                # release train. The prior "580.173.04" value (from
                                # NVOnline 1160245's RC4 "GFM:" field) was never this
                                # host's actual target - see EXPECTED_GFM_NVOS below,
                                # now confirmed as a separate, real component.
EXPECTED_GFM_NVOS="580.173.04" # CONFIRMED 2026-09-14 via the full GA release notes PDF
                                # (RN-11874-001_2.0.0GA), "GB300 Switch Tray > NVOS"
                                # table - this is the actual NVSwitch-tray-side Global
                                # Fabric Manager version, a functionally separate
                                # component from EXPECTED_FM above (which is this
                                # compute host's own inert nvidia-fabricmanager
                                # package). The earlier §0a hedge ("most likely refers
                                # to the NVOS-side FM, not confirmed") was correct and
                                # is now directly confirmed by NVIDIA's own document,
                                # not just inferred. Independent of EXPECTED_DRIVER -
                                # does NOT track the compute-host driver version, has
                                # its own release train tied to NVOS (25.02.4463 here).
                                # Not checkable from this compute-tray host (no NVOS
                                # access) - retained as a documented target for
                                # whoever verifies the NVSwitch tray directly.
# Moved here in v0.4.26 (were incorrectly declared down near the §6b Redfish
# section in v0.4.24/v0.4.25, which broke under `set -u` since checks earlier
# in the script - "VBIOS Version" in particular - referenced them before
# that later assignment ever ran). Values unchanged, only the location moved.
EXPECTED_HGX_BMC_FW="GB200Nvl-26.07-1"     # GA release notes BMC bundle, §0a
EXPECTED_HGX_EROT_FW="01.04.0055.0000_n04" # GA release notes BMC bundle + HMC EROT, §0a
EXPECTED_HGX_CPLD_FW="0.22"                # GA release notes HMC CPLD, §0a - HGX baseboard
                                             # CPLD specifically, NOT the E1S drive-carrier
                                             # board's CPLD (FW_E1S_CPLD_0/1), which has no
                                             # documented GA target and is a different part
                                             # entirely - see the case-match fix below (v0.4.28)
EXPECTED_HGX_FPGA_FW="1.66"                 # GA release notes HMC FPGA field (§0b) - the
                                             # compute-tray/HMC's own FPGA, NOT the physically
                                             # separate NVSwitch-tray FPGA (0.24, §0b's Switch
                                             # Tray BMC+FPGA+EROT bundle) - this host has no
                                             # switch tray, so 0.24 would never be the right
                                             # comparison here regardless of naming similarity
EXPECTED_MCU_SMA_FW="0003.00.0278.0000"    # GA release notes MCU SMA Firmware, §0a
EXPECTED_VBIOS="97.10.7D.00.16"            # GA release notes HMC "GPU" field (§0a) -
                                             # confirmed via two independent metadata
                                             # snapshots weeks apart: RC4 (§16) logged
                                             # 97.10.7D.00.0D, GA logs 97.10.7D.00.16 -
                                             # same 7D segment both times, only the last
                                             # segment moved (plausible RC4->GA build
                                             # increment). This host has reported
                                             # 97.10.59.00.13 via nvidia-smi unchanged
                                             # for the entire build - a real, unresolved
                                             # mismatch, never compared automatically
                                             # until now (§16 left it as awareness-only).

LOGFILE=""
while getopts "o:v" opt; do
  case "$opt" in
    o) LOGFILE="$OPTARG" ;;
    v) echo "gb300_l10_sw_checklist.sh version $SCRIPT_VERSION"; exit 0 ;;
    *) echo "Usage: $0 [-o logfile] [-v]"; exit 1 ;;
  esac
done

# ----------------------------------------------------------------------------
# 1. Helpers
# ----------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

declare -a ROWS=()   # accumulates rows for final summary table

check() {
  # check "Component" "command" "expected_substr(optional)"
  local name="$1" cmd="$2" expected="${3:-}"
  local out status

  out=$(eval "$cmd" 2>/dev/null | head -n1 | tr -d '\r')
  if [[ -z "$out" ]]; then
    status="MISSING"
    out="-"
  elif [[ -n "$expected" && "$out" != *"$expected"* ]]; then
    status="CHECK"
  else
    status="OK"
  fi
  ROWS+=("${name}|${out}|${status}")
}

note_na() {
  # note_na "Component" "reason" - for components that are structurally not
  # present on this host (e.g. owned by a different tray/OS), rather than
  # genuinely-pending bring-up work. Excluded from the MISSING count so it
  # doesn't read as a false-negative failure.
  local name="$1" reason="$2"
  ROWS+=("${name}|${reason}|N/A")
}

print_row() {
  local name="$1" val="$2" status="$3" color
  case "$status" in
    OK)      color="$GREEN" ;;
    MISSING) color="$RED" ;;
    N/A)     color="$BLUE" ;;
    *)       color="$YELLOW" ;;
  esac
  printf " %-32s : %-38s [${color}%s${NC}]\n" "$name" "$val" "$status"
}

section() {
  echo
  echo -e "${BOLD}== $1 ==${NC}"
}

# ----------------------------------------------------------------------------
# 2. Collect: OS / Kernel / Platform
# ----------------------------------------------------------------------------
section "OS / Kernel / Platform"
check "Ubuntu Release"        "lsb_release -rs" "$EXPECTED_OS"
check "Kernel Version"        "uname -r" "$EXPECTED_KERNEL"
check "Kernel Page Size"      "getconf PAGE_SIZE" "65536"
check "Architecture"          "uname -m"
check "BMC/BIOS (dmidecode)"  "dmidecode -s bios-version"
check "System Product Name"   "dmidecode -s system-product-name"
check "IOMMU Enabled"         "[ $(ls /sys/kernel/iommu_groups/ 2>/dev/null | wc -l) -gt 0 ] && echo yes"
check "Kernel Pkgs Held (meta)"    "apt-mark showhold | grep -m1 '^linux-nvidia-64k-hwe'"
check "Kernel Pkgs Held (image)"   "apt-mark showhold | grep -m1 '^linux-image-nvidia-64k-hwe'"
check "Kernel Pkgs Held (headers)" "apt-mark showhold | grep -m1 '^linux-headers-nvidia-64k-hwe'"
# Added 2026-09-14 (build log §7g). None of these three were checked anywhere
# in this script before today, and it took a live incident to notice:
# libnvidia-nscq sat completely unheld through this session's driver bump and
# showed an available "upgrade" to a different major driver branch entirely
# (615.x vs the pinned 580.x line) - not a point release, a real mismatch
# risk. nvidia-fabricmanager and nvidia-modprobe happened to already be
# covered (the former by the §25/§7g install procedure itself, the latter by
# a pre-existing hold from earlier in the build) - libnvidia-nscq was the one
# gap in an otherwise-working defense. Adding all three here so the next
# driver bump doesn't have to rediscover this by hand.
check "Held: libnvidia-nscq"       "apt-mark showhold | grep -m1 '^libnvidia-nscq$'"
check "Held: nvidia-modprobe"      "apt-mark showhold | grep -m1 '^nvidia-modprobe$'"
check "Held: nvidia-fabricmanager" "apt-mark showhold | grep -m1 '^nvidia-fabricmanager$'"
check "unattended-upgrades"   "systemctl is-active unattended-upgrades" "inactive"

# ----------------------------------------------------------------------------
# 3. Collect: NVIDIA Driver / CUDA / GPU
# ----------------------------------------------------------------------------
section "NVIDIA Driver / CUDA / GPU"
check "NVIDIA Driver Version" "nvidia-smi --query-gpu=driver_version --format=csv,noheader -i 0" "$EXPECTED_DRIVER"
check "CUDA Version (driver)" "nvidia-smi | grep -oP 'CUDA Version:\s*\K[0-9.]+' | head -n1" "$EXPECTED_CUDA"
check "nvcc (CUDA toolkit)"   "nvcc --version | grep release"
# Distinct from both rows above: "CUDA Version (driver)" is nvidia-smi's
# major.minor-only driver-supported API version (never carries an update
# number, by design - not a gap, just what that field is). "nvcc" carries
# nvcc's own independently-versioned component build (13.0.88 for Update 2,
# per NVIDIA's CUDA 13.0 Update 2 component table - doesn't share a digit
# with the update number, that's normal). This row is the actual toolkit
# meta-package version (13.0.2-1) - reads from dpkg, independent of whether
# the original cuda-repo-*.deb is still present on disk (that .deb only
# registers a local apt repo under /var/cuda-repo-.../, separate from the
# installed package's own version metadata).
check "CUDA Toolkit (meta-pkg)" "dpkg-query -W -f='\${Version}' cuda-toolkit-13-0 2>/dev/null" "$EXPECTED_CUDA_TOOLKIT"
check "GPU Count"             "nvidia-smi --query-gpu=count --format=csv,noheader -i 0"
check "GPU Name"              "nvidia-smi --query-gpu=name --format=csv,noheader -i 0"
check "VBIOS Version"         "nvidia-smi --query-gpu=vbios_version --format=csv,noheader -i 0" "$EXPECTED_VBIOS"
check "Persistence Mode"      "nvidia-smi --query-gpu=persistence_mode --format=csv,noheader -i 0"
# Added 2026-09-14 (build log §7f): "Persistence Mode" above reads current
# GPU-level state via nvidia-smi, which can read Enabled right now even if
# the daemon that maintains it won't survive the next reboot. Found this gap
# the hard way - nvidia-persistenced was silently flipped to `disabled`
# (systemd enablement, not the running state) sometime after §7e's original
# enabled+verified confirmation, root cause not established. This checks the
# thing "Persistence Mode" can't: whether it'll still be there after a
# reboot, not just whether it's on right now.
check "Persistence Daemon (enabled)" "systemctl is-enabled nvidia-persistenced" "enabled"
check "GPU Kernel Module"     "modinfo nvidia | grep -m1 ^version"

# ----------------------------------------------------------------------------
# 4. Collect: NVLink / NVSwitch / Fabric Manager
# ----------------------------------------------------------------------------
section "NVLink / NVSwitch / Fabric Manager"
# Fabric Manager: reclassified N/A as of v0.4.6, not a MISSING/failure. On the
# GB300 NVL72 rack-scale design, fabric management runs on the NVSwitch
# tray's own NVOS, not this compute host - `nvidia-fabricmanager`/
# `nv-fabricmanager` are not expected to exist here at any bring-up stage,
# racked or not.
# Corrected 2026-09-14 (build log §0a): EXPECTED_FM now tracks EXPECTED_DRIVER
# and describes this host's own (non-functional, future-proofing-only)
# nvidia-fabricmanager package - it is NOT a confirmed target for the
# NVSwitch tray's actual NVOS-side Fabric Manager, which is a separate
# component this script can't see and whose GA version isn't confirmed here.
note_na "Fabric Manager Service" "runs on NVSwitch tray (NVOS), not this host"
note_na "Fabric Manager Version" "NVOS-side target confirmed via GA release notes: ${EXPECTED_GFM_NVOS} - not checkable from this compute host, verify directly on the NVSwitch tray once racked"
# v0.4.18: defense-in-depth for the build log §25 precaution (pre-install +
# mask nvidia-fabricmanager here, purely as future-proofing against a
# cm-create-image BCM finalize-stage failure if this layout is ever used as
# a BCM image source - see §25 for full reasoning). Does NOT change the
# functional finding above: FM still never runs on this host either way.
# Absence of the package is fine (precaution is optional); presence
# without masking is the one state actually worth flagging. Package name
# here is `nvidia-fabricmanager` (no "-580" suffix) - this local-repo
# package does NOT follow the "-580"-suffixed naming used on a different
# rack's BCM pipeline; confirm the real installed name with `dpkg -l | grep
# fabricmanager` if this is ever adapted for a differently-sourced package.
if dpkg-query -W -f='${Status}' nvidia-fabricmanager 2>/dev/null | grep -q "ok installed"; then
  fm_unit_state=$(systemctl is-enabled nvidia-fabricmanager 2>&1)
  fm_installed_ver=$(dpkg-query -W -f='${Version}' nvidia-fabricmanager 2>/dev/null | grep -oP '^[0-9.]+')
  if [[ "$fm_unit_state" == "masked" ]]; then
    ROWS+=("Fabric Manager Package (if present)|installed, correctly masked|OK")
  else
    ROWS+=("Fabric Manager Package (if present)|installed but NOT masked (state: ${fm_unit_state}) - see build log §25|CHECK")
  fi
  # New 2026-09-14 (build log §0a): this package tracks the driver branch, so
  # a mismatch here means it was installed against a different driver than
  # what's currently on the box - a real drift worth catching, separate from
  # the masking check above.
  if [[ -n "$fm_installed_ver" ]]; then
    if [[ "$fm_installed_ver" == "$EXPECTED_FM" ]]; then
      ROWS+=("Fabric Manager Package Version|${fm_installed_ver}|OK")
    else
      ROWS+=("Fabric Manager Package Version|${fm_installed_ver} (expected ${EXPECTED_FM} - does not match current driver, see §0a)|CHECK")
    fi
  fi
else
  note_na "Fabric Manager Package (if present)" "not installed - fine, this precaution is optional/future-proofing only (§25)"
fi
# IMEX: installed via nvidia-imex-aarch64-<ver>.run alongside the driver (§7),
# and the daemon/service exist and are queryable on this host regardless of
# bring-up stage - unlike Fabric Manager, this is NOT an N/A case for
# *installation*. Split into two checks that ask different questions:
# "enabled" (systemd registered the unit at boot - meaningful at any stage,
# a real MISSING here is a real problem) vs. "active" (requires NVSwitch/GFM
# fabric peers to have anything to do - NOT meaningful pre-rack, see §19 of
# the build log; a single un-racked L10 tray finds no peers and cleanly
# exits to inactive by design, confirmed in §7/§7c).
check "IMEX Service (enabled)" "systemctl is-enabled nvidia-imex" "enabled"
note_na "IMEX Active State" "requires GFM active on NVSwitch tray + peer config populated - neither applies pre-rack"
check "IMEX Version"           "nvidia-imex --version | grep -oP 'IMEX version is:\s*\K[0-9.]+'" "$EXPECTED_IMEX"
check "NVLink Active Links"    "nvidia-smi nvlink -s -i 0 | grep -c 'Active'"
check "NVSwitch Devices"       "nvidia-smi -q | grep -m1 -i 'NVSwitch'"
check "GPU Topology (summary)" "nvidia-smi topo -m | head -1"

# ----------------------------------------------------------------------------
# 5. Collect: Networking (MOFED / RDMA / DOCA / BlueField)
# ----------------------------------------------------------------------------
section "Networking / MOFED / DOCA (BlueField)"
check "MOFED Version"          "ofed_info -s"
check "IB Devices"             "ibstat -l | tr '\n' ' '"
check "RDMA Link Status"       "rdma link show | head -1"
check "DOCA Version"           "doca_version 2>/dev/null || dpkg -l | grep -m1 doca-runtime" "$EXPECTED_DOCA"
check "BlueField DPU Detected" "lspci | grep -m1 -i 'BlueField'"
check "MFT Tools Version"      "mst version 2>/dev/null || flint -v 2>/dev/null | head -1" "$EXPECTED_MFT"
# mst's /dev/mst/* device tree is ephemeral - `mst start` creates it on demand
# and it does NOT persist across a reboot (build log §10 ran `mst start` for
# the firmware burn, then explicitly `mst stop`'d afterward; never set up as
# a persistent boot-time service). Every prior "OK" run relied on someone
# having manually run `mst start` in the meantime - after any reboot,
# including an unrelated BIOS/BMC update, the device tree is gone again and
# BF3/CX8 Firmware Version below would silently read MISSING. Start it here
# so the check is self-sufficient rather than depending on leftover state
# from something else. Safe/idempotent if already started; requires root,
# which the script's own EUID check (v0.4.7) already guarantees by this point.
mst start >/dev/null 2>&1
check "BF3 Firmware Version"   "flint -d /dev/mst/mt41692_pciconf0 q 2>/dev/null | grep -m1 'FW Version'" "$EXPECTED_BF3_FW"
check "CX8 Firmware Version"   "flint -d /dev/mst/mt4131_pciconf0 q 2>/dev/null | grep -m1 'FW Version'" "$EXPECTED_CX8_FW"
    # NOTE: /dev/mst/mt41692_pciconf0 and /dev/mst/mt4131_pciconf0 are placeholder
    # mst device paths - confirm actual device names via `mst status` once MFT
    # tools are installed and adjust. CX8 check above only covers card 1 of 4;
    # extend to loop over all cards if per-card firmware drift is a concern.
    #
    # NOTE: no "BF3 DPU OS version" check - waived deliberately, not an
    # oversight. This build uses the firmware-only BF3 bundle (NIC mode), so
    # the DPU Arm cores never run a customer-facing OS; there is no OS
    # version to read here. Revisit only if BF3 mode changes to embedded/DPU
    # mode with a full OS+firmware bundle.

# ----------------------------------------------------------------------------
# 6. Collect: DCGM / Container Runtime / Orchestration
# ----------------------------------------------------------------------------
section "DCGM / Container Runtime"
check "DCGM Version"           "dcgmi --version" "$EXPECTED_DCGM"
check "DCGM Service"           "systemctl is-active nvidia-dcgm"
check "Docker Version"         "docker --version"
check "containerd Version"     "containerd --version"
check "nvidia-container-toolkit" "nvidia-ctk --version"
check "Default Runtime = nvidia" "docker info 2>/dev/null | grep -m1 'Default Runtime'"

# ----------------------------------------------------------------------------
# 6b. Out-of-Band Firmware (CPLD/EROT/HMC/FPGA) via Redfish
# Confirms §17/§20's finding that these four are out-of-band-only. Discovers
# the BMC IP in-band via `ipmitool lan print`; if that comes back empty
# (not configured, or IPMI hidden from host per BMC config), stops there and
# reports N/A rather than attempting a Redfish call that can't succeed -
# same principle as the Fabric Manager / IMEX Active State N/A rows.
# Uses raw curl+Redfish rather than the `nvfwupd` tool, since curl/jq are far
# more likely to already be present than nvfwupd.
# v0.4.14 originally tried a single-call ?expand=.$levels=1 (per NVIDIA's DGX
# GB Rack Scale Systems doc, AMI-based BMC example) but confirmed against
# this unit's actual Pegatron-built BMC (Redfish 1.17.0) that expand syntax
# is NOT honored here - it silently falls back to returning the plain
# unexpanded Members list (only @odata.id, no Id/Version). Rather than keep
# guessing at vendor-specific expand syntax that may differ again on other
# nodes in the rack, v0.4.15 switched to a guaranteed-correct two-step
# approach: GET the plain list, filter candidate URIs by keyword, then GET
# each matched component individually for its Version. More HTTP calls
# (~12 on this unit), but zero syntax ambiguity.
# Real component Id strings confirmed against this unit's BMC (2026-08-11):
# no Id literally contains "HMC" - it's exposed as FW_BMC_0/HGX_FW_BMC_0
# instead, caught by the existing BMC keyword. Confirmed matches: FW_BMC_0,
# FW_E1S_CPLD_0/1, HGX_FW_BMC_0, HGX_FW_CPLD_0, HGX_FW_ERoT_BMC_0,
# HGX_FW_ERoT_CPU_0/1, HGX_FW_ERoT_FPGA_0/1, HGX_FW_FPGA_0/1.
# -k (skip TLS verify) is standard for BMC Redfish since they commonly run
# self-signed certs - flagged here explicitly rather than silently bypassed.
# ----------------------------------------------------------------------------
# v0.4.24 2026-09-14 (build log §0a/§7g): previously every matched component
# just reported OK unconditionally - there was no GA-sourced target to
# compare against when this section was written. §0a now documents real GA
# targets for BMC core and EROT, and this run's own output confirmed both
# are actually stale (BMC: GB200Nvl-25.09-2 vs GA's GB200Nvl-26.07-1; EROT:
# 01.04.0031.0000_n04 vs GA's 01.04.0055.0000_n04, all 5 instances) - a real
# drift this section was silently reporting as OK. Added expected-version
# comparison for BMC/EROT/CPLD by component-id pattern. Also expanded the
# keyword filter to add SMA|GPU: this run's actual output (FW_BMC_0,
# FW_E1S_CPLD_0/1, HGX_FW_BMC_0, HGX_FW_CPLD_0, HGX_FW_ERoT_*, HGX_FW_FPGA_0/1)
# never surfaced an SMA or HMC-GPU entry at all under the old
# CPLD|EROT|HMC|BMC|FPGA filter - confirming the gap flagged when §0a's MCU/
# HMC baseline was first documented. Whether that's because this unit's BMC
# genuinely has no separately-named SMA/GPU FirmwareInventory member, or
# because it exists under a name still not covered, is NOT yet known -
# expanding the filter is necessary but not sufficient to confirm either way.
# EXPECTED_HGX_BMC_FW / EXPECTED_HGX_EROT_FW / EXPECTED_HGX_CPLD_FW /
# EXPECTED_MCU_SMA_FW / EXPECTED_VBIOS are declared up in the main "§0.
# Config: expected versions" block near the top of this script, alongside
# every other EXPECTED_* variable - NOT here. (v0.4.24/v0.4.25 originally
# declared them at this point instead, which broke under `set -u`: the
# "VBIOS Version" check that references EXPECTED_VBIOS runs much earlier,
# in the NVIDIA Driver/CUDA/GPU section - referencing a variable before it's
# ever assigned is a hard "unbound variable" error regardless of where in
# the file it's assigned later. Fixed in v0.4.26 by moving the declarations,
# not by relaxing `set -u`.)
# EXPECTED_HGX_GPU_FW removed 2026-09-14 - was NOT a separate out-of-band
# Redfish component as originally assumed. Confirmed: the GA release notes'
# HMC table "GPU" field is VBIOS, in NVIDIA's raw-hex notation - same field
# nvidia-smi already reports via "VBIOS Version". Also consistent with why
# no "GPU"-matching component ever appeared in any live Redfish run this
# session - it was never going to, this isn't how VBIOS is exposed there.
# ----------------------------------------------------------------------------
section "Out-of-Band Firmware (Redfish)"
BMC_USER="${BMC_USER:-root}"
BMC_PASS="${BMC_PASS:-0penBmc}"   # MaxQ factory default - override via env var
                                   # (export BMC_USER/BMC_PASS before running)
                                   # once this unit's BMC credentials are
                                   # rotated. Do NOT assume this stays valid
                                   # on any node whose BMC password changed.

BMC_IP=$(ipmitool lan print 1 2>/dev/null | grep -E '^IP Address\s*:' | awk -F': ' '{print $2}' | tr -d ' ')

if [[ -z "$BMC_IP" || "$BMC_IP" == "0.0.0.0" ]]; then
  note_na "Out-of-Band FW (CPLD/EROT/HMC/FPGA)" "BMC IP not discoverable via ipmitool - not polled"
else
  BMC_FW_URIS=$(curl -sk -u "${BMC_USER}:${BMC_PASS}" -X GET \
    "https://${BMC_IP}/redfish/v1/UpdateService/FirmwareInventory" 2>/dev/null \
    | jq -r '.Members[]?."@odata.id"' 2>/dev/null \
    | grep -iE 'CPLD|EROT|HMC|BMC|FPGA|SMA')

  if [[ -z "$BMC_FW_URIS" ]]; then
    note_na "Out-of-Band FW (CPLD/EROT/HMC/FPGA)" "BMC IP=$BMC_IP found but Redfish query failed - check creds/reachability"
  else
    BMC_FW_FOUND=0
    while IFS= read -r uri; do
      [[ -z "$uri" ]] && continue
      comp_json=$(curl -sk -u "${BMC_USER}:${BMC_PASS}" -X GET "https://${BMC_IP}${uri}" 2>/dev/null)
      comp_id=$(echo "$comp_json" | jq -r '.Id // empty' 2>/dev/null)
      comp_ver=$(echo "$comp_json" | jq -r '.Version // empty' 2>/dev/null)
      if [[ -n "$comp_id" && -n "$comp_ver" ]]; then
        # Match against a known GA target by component-id pattern, where one
        # exists. Fixed in v0.4.28: every pattern anchored to the confirmed
        # "HGX_FW_" prefix instead of loose substrings. The old bare "*CPLD*"
        # pattern was a real bug, not just imprecise - it matched
        # FW_E1S_CPLD_0/1 (the E1S NVMe drive-carrier board's own CPLD, a
        # completely different, unrelated part) and compared it against the
        # HGX baseboard's CPLD target, producing a false "CHECK" mismatch
        # for two unrelated components rather than a real finding. Caught by
        # a live run showing "FW_E1S_CPLD_0: 0b.04.02 (expected 0.22)" - that
        # 0.22 target was never meant for this component at all. Order still
        # matters: EROT before BMC, since "HGX_FW_ERoT_BMC_0" would otherwise
        # match a plain BMC pattern first.
        comp_expected=""
        case "$comp_id" in
          HGX_FW_ERoT_*) comp_expected="$EXPECTED_HGX_EROT_FW" ;;
          HGX_FW_CPLD_*) comp_expected="$EXPECTED_HGX_CPLD_FW" ;;
          HGX_FW_FPGA_*) comp_expected="$EXPECTED_HGX_FPGA_FW" ;;
          HGX_FW_SMA_*)  comp_expected="$EXPECTED_MCU_SMA_FW" ;;
          HGX_FW_BMC_*)  comp_expected="$EXPECTED_HGX_BMC_FW" ;;
          # GPU pattern deliberately not matched here - see EXPECTED_VBIOS
          # comment in §0: the GA "GPU" field is VBIOS, checked against
          # nvidia-smi directly below, not something exposed via this
          # Redfish FirmwareInventory endpoint on this unit.
          # Deliberately NOT matched: bare FW_BMC_0 (this unit's baseboard
          # BMC itself, e.g. "carlonext-bmc_0.80.07") - different versioning
          # scheme entirely from the GB200Nvl-x.x GA target, no GA-sourced
          # comparison value exists for it. FW_E1S_CPLD_0/1 (the E1S drive-
          # carrier board's own CPLD - a different, unrelated part from the
          # HGX baseboard CPLD) is correctly excluded by the HGX_FW_ prefix
          # requirement above, not just "unconfirmed" - no GA target exists
          # for this component and none should be applied to it.
        esac
        if [[ -n "$comp_expected" ]]; then
          if [[ "$comp_ver" == "$comp_expected" ]]; then
            ROWS+=("Out-of-Band FW: ${comp_id}|${comp_ver}|OK")
          else
            ROWS+=("Out-of-Band FW: ${comp_id}|${comp_ver} (expected ${comp_expected} per GA §0a)|CHECK")
          fi
        else
          ROWS+=("Out-of-Band FW: ${comp_id}|${comp_ver}|OK")
        fi
        BMC_FW_FOUND=1
      fi
    done <<< "$BMC_FW_URIS"

    if [[ "$BMC_FW_FOUND" -eq 0 ]]; then
      note_na "Out-of-Band FW (CPLD/EROT/HMC/FPGA)" "BMC IP=$BMC_IP found, component list matched, but per-component GET failed"
    fi
  fi
fi

# ----------------------------------------------------------------------------
# 6c. Disk Hygiene / Repo Cleanup
# Confirms build log §22a's cleanup pass hasn't regressed. Both local-repo
# .deb packages are legitimate, dpkg-tracked install-time scaffolding for
# CUDA (§8) / nvidia-fabricmanager (§25) - fine to have installed transiently,
# but they leave a combined ~4.4G under /var that serves no purpose once the
# real packages they staged (cuda-toolkit-13-0, nvidia-fabricmanager) are in
# place. §22a purged both; this section catches silent re-installation on a
# future rebuild rather than assuming the cleanup stays done forever.
# Status is CHECK, not MISSING, if still present - this is a footprint/
# hygiene concern, not a functional defect, so it shouldn't count toward a
# failed bring-up the way a genuinely missing driver/CUDA component would.
# ----------------------------------------------------------------------------
section "Disk Hygiene / Repo Cleanup"

if dpkg-query -W -f='${Status}' cuda-repo-ubuntu2404-13-0-local 2>/dev/null | grep -q "ok installed"; then
  ROWS+=("Stale CUDA Repo Pkg|installed - ~3.6G under /var, purge per §22a (apt purge cuda-repo-ubuntu2404-13-0-local)|CHECK")
else
  ROWS+=("Stale CUDA Repo Pkg|not installed - clean (§22a)|OK")
fi

# Package name parameterized on EXPECTED_DRIVER as of 2026-09-14 (build log
# §0a) - was hardcoded to the RC4-era 580.173.02 suffix, which would have
# silently stopped matching anything real the moment the driver bumped to
# GA's 580.173.10 (false "clean" reading, not because the repo pkg was
# actually gone, but because the check was looking for the wrong name).
driver_repo_pkg="nvidia-driver-local-repo-ubuntu2404-${EXPECTED_DRIVER}"
if dpkg-query -W -f='${Status}' "$driver_repo_pkg" 2>/dev/null | grep -q "ok installed"; then
  ROWS+=("Stale NVIDIA Driver Repo Pkg|installed - ~573M under /var, purge per §22a (apt purge ${driver_repo_pkg})|CHECK")
else
  ROWS+=("Stale NVIDIA Driver Repo Pkg|not installed - clean (§22a)|OK")
fi

# BCM's own category disk-setup XML (confirmed in §22a) defines only
# efi/boot/root for this reference layout - no swap partition or swap file.
# /swap.img (8G, 0B ever used at 2.0Ti host RAM) was a manual, out-of-band
# addition, not something BCM provisioning creates - so its removal in §22a
# won't be undone by a category resync/reinstall. This check just confirms
# the current state; it doesn't assume swap is always wrong (a node with a
# real category-level swap definition, or genuinely tight RAM, might
# legitimately want it), so it's informational (CHECK), not PASS/FAIL.
swap_active=$(swapon --show --noheadings 2>/dev/null)
if [[ -z "$swap_active" ]]; then
  ROWS+=("Unused Swap File|none active - matches BCM disk-setup, no swap defined (§22a)|OK")
else
  swap_summary=$(echo "$swap_active" | awk '{print $1, $3}' | tr '\n' ';' | sed 's/;$//')
  ROWS+=("Unused Swap File|active: ${swap_summary} - confirm intentional, not part of BCM category disk-setup (§22a)|CHECK")
fi

# ----------------------------------------------------------------------------
# Golden-Image / Pre-Capture Readiness - added 2026-09-16 (build log §25 /
# SOP §12). Both checks below were previously manual-only SOP steps someone
# had to remember to run right before an image capture - wiring them into
# the checklist means a stale/incomplete pre-capture state shows up on a
# routine run instead of only being caught (or missed) by hand.
# ----------------------------------------------------------------------------
section "Golden-Image / Pre-Capture Readiness"

# Config directory presence - straightforward PASS/FAIL, no ambiguity: some
# BCM-provisioning pipelines fail hard if these don't exist for their
# node-installer to write generated config into (build log §25). Static
# directories, not per-node identity state, so there's no "correct answer
# depends on when you run this" complication the way the boot-addressing
# check below has - missing is missing, at any bring-up stage.
missing_dirs=()
[[ -d /etc/network/interfaces.d ]] || missing_dirs+=("/etc/network/interfaces.d")
[[ -d /etc/ntpsec ]] || missing_dirs+=("/etc/ntpsec")
if [[ ${#missing_dirs[@]} -eq 0 ]]; then
  ROWS+=("Config Dirs (interfaces.d/ntpsec)|both present|OK")
else
  ROWS+=("Config Dirs (interfaces.d/ntpsec)|missing: ${missing_dirs[*]} - mkdir -p before image capture (§25/SOP §12)|CHECK")
fi

# Boot device addressing (UUID vs by-path) - deliberately INFORMATIONAL, not
# PASS/FAIL, unlike everything else in this section. Unlike the config-dir
# check above, "correct" here depends entirely on WHEN this script runs, not
# just on the current state: UUID-based addressing is completely normal and
# correct during ordinary bring-up (SOP §1-§11) - only becomes a deliberate
# decision point right before image capture (SOP §12/build log §25), and
# only applies at all if this build's specific hardware-uniformity
# assumption holds (fixed NVMe slot, identical fleet hardware - see SOP §12
# step 0). This script has no way to know "are we about to capture an image
# right now" vs "mid bring-up", so asserting a hard target here would
# produce false CHECKs on every normal build before that decision point.
# Reports current state only; a human applies the SOP §12 judgment call.
if grep -q 'root=/dev/disk/by-path' /boot/grub/grub.cfg 2>/dev/null; then
  ROWS+=("Boot Device Addressing|by-path (converted) - confirm this matches an intentional decision, not an accident|OK")
elif grep -qE 'UUID=|/dev/disk/by-uuid' /etc/fstab 2>/dev/null; then
  ROWS+=("Boot Device Addressing|UUID (not converted) - normal during bring-up; decide by-path vs UUID before image capture, see SOP §12 step 0|OK")
else
  ROWS+=("Boot Device Addressing|neither UUID nor by-path detected in fstab/grub.cfg - inspect manually|CHECK")
fi

# ----------------------------------------------------------------------------
# 7. Print summary table
# ----------------------------------------------------------------------------
echo
echo -e "${BOLD}==================================================================${NC}"
echo -e "${BOLD} GB300 NVL L10 SYSTEM SOFTWARE CHECKLIST  v${SCRIPT_VERSION}  ($(date '+%Y-%m-%d %H:%M:%S'))${NC}"
echo -e "${BOLD}==================================================================${NC}"

pass=0; fail=0; check_n=0; na=0
for row in "${ROWS[@]}"; do
  IFS='|' read -r name val status <<< "$row"
  print_row "$name" "$val" "$status"
  case "$status" in
    OK) ((pass++)) ;;
    MISSING) ((fail++)) ;;
    N/A) ((na++)) ;;
    *) ((check_n++)) ;;
  esac
done

echo -e "${BOLD}------------------------------------------------------------------${NC}"
echo -e " Summary: ${GREEN}${pass} OK${NC} | ${YELLOW}${check_n} NEEDS REVIEW${NC} | ${RED}${fail} MISSING${NC} | ${BLUE}${na} N/A${NC}"
echo -e "${BOLD}==================================================================${NC}"

# ----------------------------------------------------------------------------
# 8. Optional: write to logfile (plain text, no color codes)
# ----------------------------------------------------------------------------
if [[ -n "$LOGFILE" ]]; then
  {
    echo "GB300 NVL L10 System Software Checklist - v${SCRIPT_VERSION} - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "===================================================================="
    for row in "${ROWS[@]}"; do
      IFS='|' read -r name val status <<< "$row"
      printf " %-32s : %-38s [%s]\n" "$name" "$val" "$status"
    done
    echo "--------------------------------------------------------------------"
    echo "Summary: ${pass} OK | ${check_n} NEEDS REVIEW | ${fail} MISSING | ${na} N/A"
  } > "$LOGFILE"
  echo
  echo "Log written to: $LOGFILE"
fi

exit 0
