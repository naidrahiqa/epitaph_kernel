# Changelog — Epitaph Kernel

All notable changes are documented here.
Format: [vX.Y] — YYYY-MM-DD

---

## [v148] — 2026-05-28
### Fixed
- SUSFS build: migrated KSU source to pershoot/KernelSU-Next branch next-susfs
- SUSFS build: added git commit after staging to make changes visible to Bazel
- SUSFS_INTEGRATED flag: now verified from actual patched source, not self-written Kconfig

### Added
- Epitaph Schedutil Performance: 3-profile runtime tuner (performance/balanced/battery)
- epitaph_tuner.sh v2.0: full logging to /data/adb/epitaph/tuner.log
- WiFi fallback loader: auto-insmod if systemless loading fails

### Changed
- AnyKernel3: migrated from upstream clone to own fork (pinned)
- Rescue kernel: now ships as separate build_debug_bootimg.yml workflow

---

## [v73] — 2026-05-17
### Added
- Netfilter NAT IPv4 + IPv6 for stable hotspot
- Epitaph Tuner post-boot script (v1.0)
- PStore RAMoops at 0x4d010000
- ZRAM ZSTD multi-comp & KSM memory optimizations

### Fixed
- GPU thermal throttle bug via GED bypass in tuner

---

## [v72] — 2026-05-10
### Changed
- Migrated all inline Python scripts to standalone workflow_scripts/
- GKI Control Center UI: replaced checkboxes with dropdown menus
- Fixed KernelSU-Next version injection IndentationError

### Fixed
- SUSFS patch application — mandatory validation now exits on failure
- Removed unused Azure build server support to clean up workflows

---

## [v71] — 2026-05-05
### Changed
- Experimentally compiled using ZyClang toolchain (bootloop identified due to debug info stripping)

---

## [v70] — 2026-04-28
### Added
- Initial successful boot on Android 15 HyperOS 2.0 with GKI 6.6
- Basic KernelSU-Next integration
