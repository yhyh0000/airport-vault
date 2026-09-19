# Mihomo patches

`proxy-only-traffic.patch` exposes SlClash's proxy-only upload/download
counters through the small bridge API expected by this repository. The current
FlClash Mihomo fork already maintains the proxy counters internally; the patch
only adds the `ProxyNow` and `ProxyTotal` accessors.

The Android build applies this patch automatically. The scheduled Mihomo
update workflow also applies and validates it before pushing an update branch.
If a future Mihomo release changes the touched code, update the patch against
that release and rerun the core tests before merging.
