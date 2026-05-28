# Contributing to Epitaph Kernel

Thank you for your interest in contributing. This document explains
how to work with this repository effectively.

## Before You Start

Read these documents first:
- [PRD.md](../../PRD.md) — Project requirements and architecture
- [INSTRUCTIONS_FOR_AI.md](./INSTRUCTIONS_FOR_AI.md) — Absolute technical constraints
- [NOTES.md](./NOTES.md) — Build history and known decisions

## Types of Contributions Welcome

- Bug reports with crash logs (see Debugging Guide)
- Defconfig improvements with test results
- Documentation fixes
- Patch additions to `patches/` directory
- Workflow improvements (CI/CD)

## What NOT to Submit

- Changes that enable `CONFIG_DEBUG_INFO_NONE=y`
- Changes that switch from `pershoot/KernelSU-Next` (dev-susfs branch)
- Removing `patch_vermagic.py`
- Forcing `CONFIG_CFG80211=y` or `CONFIG_MAC80211=y` (must stay `=m`)
- Locking the kernel to a specific old commit

## Submitting a Bug Report

Use the issue template. Include:
1. Build version (check kernel version: `adb shell uname -r`)
2. Toolchain used
3. SUSFS variant (yes/no)
4. Crash log from PStore: `adb shell "su -c cat /sys/fs/pstore/console-ramoops-0"`
5. Tuner log: `adb shell "cat /data/local/tmp/epitaph_tuner.log"`

## Submitting a PR

1. Fork the repo
2. Create a branch: `fix/short-description` or `feat/short-description`
3. Make targeted changes (no full-file rewrites unless necessary)
4. Test with a Bazel build before submitting
5. Describe what changed and why in the PR description

## Contact

- GitHub Issues for bugs
- XDA thread for user support
- Maintainer: @naidrahiqa
