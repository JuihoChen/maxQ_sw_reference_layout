# GB300 NVL L10 — Kernel / DOCA 3.2.1 Compatibility Findings for NV Review

**Platform:** GB300 NVL, 1.0.6 reference layout (field-upgrade path toward 2.0.0)
**Reported by:** [name/team]
**Date:** 2026-08-19

## Summary

NV guidance directed testing kernel **6.17.0-1016** as the target kernel for the 1.0.6 → 2.0.0 field-upgrade path (a single kernel intended to remain fixed across both DOCA 3.2.1 [1.0.6] and the DOCA version shipped with 2.0.0). Testing found:

1. **6.17.0-1016 does not exist** in the published Ubuntu archive for `linux-signed-nvidia-6.17` (pool jumps 1014 → 1018, confirmed via `ports.ubuntu.com` directory listing).
2. **6.17.0-1018 and 6.17.0-1029** both **fail to build** `mlnx-ofed-kernel` (DOCA 3.2.1 source train, `25.10.OFED.25.10.1.7.1.409.1`) against their kernel headers — identical failure signature on both builds.
3. **6.17.0-1029 builds successfully against DOCA 3.4.1** (the RC4/2.0.0 source train) — same kernel, different DOCA source train, no failure.
4. **6.17.0-1014** is the only 6.17-line build confirmed to compile DOCA 3.2.1 cleanly, but NV has separately flagged a **CPU stream-score bug** on 1014, disqualifying it.
5. **6.14.0-1015** (LTS-adjacent, already NV/customer-validated for 1.0.6) remains the only currently-viable kernel for DOCA 3.2.1 without known defects. Reference layout is reverting to 6.14.0-1015 as the interim baseline.

**Net effect: no kernel currently satisfies both "compiles DOCA 3.2.1 cleanly" and "free of the known 1014 CPU stream-score bug" within the 6.17 HWE line.**

## Build Test Matrix

| Kernel | DOCA 3.2.1 (25.10 MOFED source) | DOCA 3.4.1 (source used for 2.0.0RC4) | Notes |
|---|---|---|---|
| 6.14.0-1015 | ✅ Builds/runs clean | Not tested | Already NV/customer-validated for 1.0.6 |
| 6.17.0-1014 | ✅ Builds/runs clean (DKMS autoinstall, full functional validation incl. cold power cycle) | Not yet tested | **Disqualified: NV-reported CPU stream-score bug** |
| 6.17.0-1016 | N/A | N/A | **Does not exist in Ubuntu archive** (pool skips from 1014 to 1018) |
| 6.17.0-1018 | ❌ Build failure | Not tested | See error detail below |
| 6.17.0-1029 | ❌ Build failure (identical to 1018) | ✅ Builds clean | Confirms failure is source-train-specific, not kernel-line-general |

## Root Cause — Build Failure Detail (1018 and 1029, identical)

`mlnx-ofed-kernel` source `25.10.OFED.25.10.1.7.1.409.1` fails to compile against these kernels' `net/tls.h` due to a changed function signature for TLS RX resync offload:

```
drivers/net/ethernet/mellanox/mlx5/core/en_accel/ktls_rx.c: In function 'mlx5e_ktls_handle_get_psv_completion':
error: passing argument 1 of 'tls_offload_rx_resync_async_request_end' from incompatible pointer type [-Werror=incompatible-pointer-types]
        tls_offload_rx_resync_async_request_end(priv_rx->sk, cpu_to_be32(hw_seq));
                                                 ~~~~~~~^~~~
                                                        struct sock *
note: expected 'struct tls_offload_resync_async *' but argument is of type 'struct sock *'

drivers/net/ethernet/mellanox/mlx5/core/en_accel/ktls_rx.c: In function 'resync_update_sn':
error: passing argument 1 of 'tls_offload_rx_resync_async_request_start' from incompatible pointer type [-Werror=incompatible-pointer-types]
        tls_offload_rx_resync_async_request_start(sk, seq, datalen);
                                                   ^~
                                                   struct sock *
note: expected 'struct tls_offload_resync_async *' but argument is of type 'struct sock *'

cc1: some warnings being treated as errors
make: *** [debian/rules:59: build] Error 2
```

The kernel-side `net/tls.h` in both 1018 and 1029 expects the first argument to be `struct tls_offload_resync_async *`; the DOCA 3.2.1 / `25.10` MOFED source still calls these functions passing `struct sock *`. Build treats the mismatch as a hard error (`-Werror=incompatible-pointer-types`).

This is consistent with an upstream kernel TLS-offload API change introduced somewhere between 1014 and 1018 that the `25.10` MOFED/DOCA 3.2.1 source has not been updated to match. The 3.4.1 source train (used successfully on 1029) does not exhibit this failure, suggesting it already accounts for the newer signature.

## Open Questions for NV

1. **Was 6.17.0-1016 the intended build number**, or was a different/internal identifier meant? It does not exist in the public Ubuntu archive for this kernel line.
2. **Is there a patched/updated MOFED source for the DOCA 3.2.1 train** that accounts for the `net/tls.h` signature change, allowing it to build against 1018/1029/later kernels? If so, please provide.
3. **What is the expected resolution path for the 1014 CPU stream-score bug**, and is a fix targeted for a specific point release?
4. Given DOCA 3.4.1 already builds clean on 1029, **is 1029 (or later) the intended long-term kernel target for the 2.0.0 field-upgrade path**, with a corresponding DOCA-3.2.1-compatible source update still pending? Clarifying this affects whether the field-upgrade procedure needs to include a kernel swap alongside the DOCA version bump, or can remain DOCA-only with the kernel held fixed.

## Interim Action (no NV input required)

1.0.6 reference layout (`maxQ106`) is reverting from 6.17.0-1014 to **6.14.0-1015**, the previously NV/customer-validated baseline, pending resolution of the above. This does not require an NV response to proceed and is already underway.
