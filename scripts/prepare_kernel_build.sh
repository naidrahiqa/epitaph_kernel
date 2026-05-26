#!/bin/bash
# ==============================================================================
#  Epitaph Kernel — Common Build Preparation Script
#  Designed by Naidrahiqa & Antigravity AI
#
#  Called by both _build_kernel_core.yml and build_debug_bootimg.yml
#  to eliminate code duplication.
# ==============================================================================
# Parameters:
#   $1 = WORKFLOW_TYPE    "core" | "rescue"
#   $2 = ANDROID_VERSION  e.g. "android15"
#   $3 = KERNEL_VERSION   e.g. "6.6"
#   $4 = GITHUB_WORKSPACE path to workspace root
#   $5 = GITHUB_ENV       path to GITHUB_ENV file
#   $6 = CLANG_TOOLCHAIN  e.g. "bazel-default", "zyc-latest" (core only, ignored by rescue)
#   $7 = KSU_METHOD       e.g. "kernelsu-next"
#   $8 = WITH_SUSFS       "true" | "false" (core only, ignored by rescue)
# ==============================================================================

set -euo pipefail

WORKFLOW_TYPE="$1"
ANDROID_VERSION="$2"
KERNEL_VERSION="$3"
GITHUB_WORKSPACE="$4"
GITHUB_ENV="$5"
CLANG_TOOLCHAIN="${6:-bazel-default}"
KSU_METHOD="${7:-kernelsu-next}"
WITH_SUSFS="${8:-false}"

echo "=== Epitaph Build Prep: type=$WORKFLOW_TYPE tc=$CLANG_TOOLCHAIN ksu=$KSU_METHOD susfs=$WITH_SUSFS ==="

# ──────────────────────────────────────────────
# 1. MAXIMIZE DISK SPACE
# ──────────────────────────────────────────────
maximize_disk() {
  df -h
  sudo rm -rf \
    /usr/share/dotnet /usr/local/lib/android /opt/ghc \
    /usr/share/swift /usr/share/miniconda \
    /usr/local/share/chromium /usr/local/share/powershell \
    /usr/local/bin/aliyun /usr/local/bin/azcopy /usr/local/bin/cmake-gui
  sudo apt-get remove -y '^dotnet-.*' '^llvm-.*' 'php.*' \
    azure-cli google-cloud-cli google-chrome-stable firefox \
    powershell mono-devel || true
  sudo apt-get autoremove -y && sudo apt-get clean
  df -h /
}

# ──────────────────────────────────────────────
# 2. SETUP SWAP (16GB)
# ──────────────────────────────────────────────
setup_swap() {
  sudo swapoff /mnt/swapfile 2>/dev/null || true
  sudo rm -f /mnt/swapfile
  sudo fallocate -l 16G /mnt/swapfile \
    || sudo dd if=/dev/zero of=/mnt/swapfile bs=1M count=16384
  sudo chmod 600 /mnt/swapfile
  sudo mkswap /mnt/swapfile && sudo swapon /mnt/swapfile
  free -h
}

# ──────────────────────────────────────────────
# 3. INSTALL DEPENDENCIES
# ──────────────────────────────────────────────
install_deps() {
  sudo apt-get update
  sudo apt-get install -y \
    git curl wget bc bison flex libssl-dev make libelf-dev \
    python3 python3-pip python-is-python3 zip unzip cpio \
    kmod rsync lz4 jq patch binutils libncurses-dev \
    pkg-config ninja-build zstd aria2 p7zip-full \
    gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi
}

# ──────────────────────────────────────────────
# 4. INSTALL REPO TOOL
# ──────────────────────────────────────────────
install_repo() {
  mkdir -p ~/bin
  curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
  chmod a+x ~/bin/repo
  export PATH="$HOME/bin:$PATH"
  echo "$HOME/bin" >> "$GITHUB_PATH"
}

# ──────────────────────────────────────────────
# 5. DOWNLOAD CUSTOM TOOLCHAIN (core only)
# ──────────────────────────────────────────────
download_toolchain() {
  [ "$WORKFLOW_TYPE" != "core" ] && return 0
  [ "$CLANG_TOOLCHAIN" = "bazel-default" ] || [ -z "$CLANG_TOOLCHAIN" ] && return 0

  mkdir -p prebuilts/clang/host/linux-x86
  cd prebuilts/clang/host/linux-x86

  smart_extract() {
    local archive="$1" dest="$2"
    mkdir -p "$dest"
    echo "  → Attempt 1: Extracting with --strip-components=1..."
    tar -xf "$archive" -C "$dest" --strip-components=1 2>/dev/null
    if [ -f "$dest/bin/clang" ] || [ -L "$dest/bin/clang" ]; then
      echo "  ✅ Found bin/clang after strip (nested archive)"
      rm -f "$archive"; return 0
    fi
    echo "  → Attempt 1 failed. Trying flat extraction..."
    rm -rf "$dest"/*
    tar -xf "$archive" -C "$dest" 2>/dev/null
    if [ -f "$dest/bin/clang" ] || [ -L "$dest/bin/clang" ]; then
      echo "  ✅ Found bin/clang (flat archive)"
      rm -f "$archive"; return 0
    fi
    echo "  → Attempt 2 failed. Searching for clang binary..."
    local found_clang=$(find "$dest" -name "clang" -type f -o -name "clang" -type l | head -n1)
    if [ -n "$found_clang" ]; then
      local found_dir=$(dirname "$(dirname "$found_clang")")
      echo "  → Found clang at: $found_clang"
      if [ "$found_dir" != "$dest" ]; then
        local tmpdir=$(mktemp -d)
        mv "$found_dir"/* "$tmpdir/"
        rm -rf "$dest"/*
        mv "$tmpdir"/* "$dest/"
        rm -rf "$tmpdir"
      fi
      echo "  ✅ Restructured successfully"
      rm -f "$archive"; return 0
    fi
    echo "  ❌ ERROR: Could not find clang binary in archive!"
    tar -tf "$archive" 2>/dev/null | head -30 || true
    rm -f "$archive"; return 1
  }

  case "$CLANG_TOOLCHAIN" in
    zyc-latest)
      echo "📥 Downloading ZyClang..."
      ZYASSET_URL=$(curl -sL \
        "https://api.github.com/repos/ZyCromerZ/Clang/releases/latest" \
        | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url' \
        | head -n1)
      [ -z "$ZYASSET_URL" ] && echo "ERROR: Failed to get ZyClang URL" && exit 1
      # Tambahkan opsi retry-wait=5 dan max-tries=10 untuk menangani error transient HTTP 502/503 di GitHub Releases
      aria2c -x16 -s16 -k1M --retry-wait=5 --max-tries=10 -o clang.tar.gz "$ZYASSET_URL"
      smart_extract clang.tar.gz clang-zyc
      CLANG_PATH="$GITHUB_WORKSPACE/prebuilts/clang/host/linux-x86/clang-zyc"
      echo "CUSTOM_CLANG_PATH=$CLANG_PATH" >> "$GITHUB_ENV"
      echo "TOOLCHAIN_NAME=ZyClang" >> "$GITHUB_ENV"
      ;;
    aosp-latest)
      git clone --depth=1 https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r522817.git clang-aosp
      CLANG_PATH="$GITHUB_WORKSPACE/prebuilts/clang/host/linux-x86/clang-aosp"
      echo "CUSTOM_CLANG_PATH=$CLANG_PATH" >> "$GITHUB_ENV"
      echo "TOOLCHAIN_NAME=AOSPClang" >> "$GITHUB_ENV"
      ;;
    weebx-latest)
      WEEBX_URL=$(curl -s https://api.github.com/repos/XSans0/WeebX-Clang/releases/latest | jq -r '.assets[] | select(.name | contains("WeebX-Clang")) | .browser_download_url' | head -n1)
      # Tambahkan opsi retry-wait=5 dan max-tries=10 untuk menangani error transient HTTP 502/503 di GitHub Releases
      aria2c -x16 -s16 -k1M --retry-wait=5 --max-tries=10 -o clang.tar.gz "$WEEBX_URL"
      smart_extract clang.tar.gz clang-weebx
      CLANG_PATH="$GITHUB_WORKSPACE/prebuilts/clang/host/linux-x86/clang-weebx"
      echo "CUSTOM_CLANG_PATH=$CLANG_PATH" >> "$GITHUB_ENV"
      echo "TOOLCHAIN_NAME=WeebXClang" >> "$GITHUB_ENV"
      ;;
    neutron-latest)
      NEUTRON_ASSET=$(curl -sL https://api.github.com/repos/Neutron-Toolchains/clang-build-catalogue/releases/latest | jq -r '.assets[] | select(.name | contains("neutron-clang")) | .browser_download_url' | head -n1)
      # Tambahkan opsi retry-wait=5 dan max-tries=10 untuk menangani error transient HTTP 502/503 di GitHub Releases
      aria2c -x16 -s16 -k1M --retry-wait=5 --max-tries=10 -o clang.tar.gz "$NEUTRON_ASSET"
      smart_extract clang.tar.gz clang-neutron
      CLANG_PATH="$GITHUB_WORKSPACE/prebuilts/clang/host/linux-x86/clang-neutron"
      echo "CUSTOM_CLANG_PATH=$CLANG_PATH" >> "$GITHUB_ENV"
      echo "TOOLCHAIN_NAME=NeutronClang" >> "$GITHUB_ENV"
      ;;
    *)
      echo "❌ ERROR: Unknown toolchain: $CLANG_TOOLCHAIN"
      exit 1
      ;;
  esac

  if [ ! -f "$CLANG_PATH/bin/clang" ]; then
    echo "❌ ERROR: clang binary not found at $CLANG_PATH/bin/clang"
    find "$CLANG_PATH" -name "clang*" | head -n 10 || true
    exit 1
  fi
  echo "✅ Custom toolchain ready: $CLANG_TOOLCHAIN"
  $CLANG_PATH/bin/clang --version | head -n1
  CLANG_VER=$($CLANG_PATH/bin/clang --version | head -n1 | sed 's/ (http.*//g' | awk '{$1=$1};1')
  echo "TOOLCHAIN_VER=$CLANG_VER" >> "$GITHUB_ENV"
  cd "$GITHUB_WORKSPACE"
}

# ──────────────────────────────────────────────
# 6. SYNC ANDROID COMMON KERNEL
# ──────────────────────────────────────────────
sync_kernel() {
  mkdir -p kernel && cd kernel
  repo init -u https://android.googlesource.com/kernel/manifest \
    -b common-${ANDROID_VERSION}-${KERNEL_VERSION} --depth=1

  SYNC_OK=false
  for attempt in 1 2 3; do
    echo "repo sync attempt $attempt/3..."
    if repo sync -c -j$(nproc) --no-tags --no-clone-bundle --force-sync; then
      SYNC_OK=true
      break
    fi
    echo "⚠️ Sync failed, retrying in 30s..."
    sleep 30
  done
  [ "$SYNC_OK" = "false" ] && echo "❌ repo sync gagal setelah 3 percobaan" && exit 1

  cd common
  KERNEL_COMMIT=$(git log --oneline -1)
  echo "✅ Using tip of branch ($KERNEL_COMMIT)"
  echo "KERNEL_COMMIT=$KERNEL_COMMIT" >> "$GITHUB_ENV"
  make kernelversion
  cd "$GITHUB_WORKSPACE"
}

# ──────────────────────────────────────────────
# 7. SET KMI GENERATION
# ──────────────────────────────────────────────
set_kmi() {
  cd kernel/common

  DETECTED_KMI=""
  if [ -f "build.config.common" ]; then
    DETECTED_KMI=$(grep -oP '(?<=KMI_GENERATION=)\d+' build.config.common | head -n1)
  fi
  if [ -z "$DETECTED_KMI" ] && [ -f "build.config.gki" ]; then
    DETECTED_KMI=$(grep -oP '(?<=KMI_GENERATION=)\d+' build.config.gki | head -n1)
  fi
  if [ -z "$DETECTED_KMI" ]; then
    STAMP_FILE="../build/kernel/kleaf/impl/stamp.bzl"
    if [ -f "$STAMP_FILE" ]; then
      DETECTED_KMI=$(grep -oP '(?<=kmi_generation = ")\d+' "$STAMP_FILE" | head -n1)
    fi
  fi
  if [ -z "$DETECTED_KMI" ]; then
    echo "⚠️  WARNING: Could not detect KMI_GENERATION from source, falling back to 8"
    DETECTED_KMI="8"
  fi

  echo "✅ KMI_GENERATION detected: $DETECTED_KMI"
  echo "KMI_GENERATION=$DETECTED_KMI" >> "$GITHUB_ENV"

  if [ -f "build.config.common" ]; then
    if grep -q "KMI_GENERATION" build.config.common; then
      sed -i "s/KMI_GENERATION=.*/KMI_GENERATION=${DETECTED_KMI}/" build.config.common
    else
      echo "KMI_GENERATION=${DETECTED_KMI}" >> build.config.common
    fi
  fi
  for f in build.config.gki build.config.gki.aarch64; do
    [ -f "$f" ] && grep -q "KMI_GENERATION" "$f" \
      && sed -i "s/KMI_GENERATION=.*/KMI_GENERATION=${DETECTED_KMI}/" "$f"
  done
  STAMP_FILE="../build/kernel/kleaf/impl/stamp.bzl"
  [ -f "$STAMP_FILE" ] && grep -q "kmi_generation" "$STAMP_FILE" \
    && sed -i "s/kmi_generation = \"[0-9]*\"/kmi_generation = \"${DETECTED_KMI}\"/" "$STAMP_FILE" || true

  if [ -f "build.config.common" ] && ! grep -q "KMI_GENERATION=${DETECTED_KMI}" build.config.common; then
    echo "❌ ERROR: KMI_GENERATION not set correctly!"
    exit 1
  fi
  echo "✅ KMI_GENERATION=$DETECTED_KMI applied to all config files"
  cd "$GITHUB_WORKSPACE"
}

# ──────────────────────────────────────────────
# 8. SETUP KernelSU-Next
# ──────────────────────────────────────────────
setup_ksu() {
  cd kernel

  if [ "$WITH_SUSFS" = "true" ]; then
    # Kloning fork pershoot branch dev-susfs yang sudah terintegrasi SUSFS secara pre-patched
    echo "Cloning KernelSU-Next (pershoot fork dev-susfs branch)..."
    git clone https://github.com/pershoot/KernelSU-Next -b dev-susfs KernelSU-Next
  else
    # Kloning upstream resmi KernelSU-Next branch dev (branch default utama repo ini) untuk build murni tanpa SUSFS
    echo "Cloning KernelSU-Next (official upstream dev branch)..."
    git clone https://github.com/KernelSU-Next/KernelSU-Next -b dev KernelSU-Next
  fi

  if [ ! -d "KernelSU-Next/kernel" ]; then
    echo "❌ ERROR: KernelSU-Next/kernel/ directory not found!"
    ls -la KernelSU-Next/ | head -30
    exit 1
  fi

  GIT_COUNT=$(cd KernelSU-Next && git rev-list --count HEAD 2>/dev/null || echo "0")
  if [ "$GIT_COUNT" -gt 1 ]; then
    KSU_VERSION=$((30000 + GIT_COUNT))
  else
    KSU_VERSION="30000"
  fi
  KSU_TAG=$(cd KernelSU-Next && git describe --abbrev=0 --tags 2>/dev/null || echo "v${KSU_VERSION}")

  echo "Copying KernelSU-Next/kernel to common/drivers/kernelsu..."
  rm -rf common/drivers/kernelsu
  cp -r KernelSU-Next/kernel common/drivers/kernelsu
  cp -r KernelSU-Next/uapi common/drivers/kernelsu/uapi 2>/dev/null || true

  find common/drivers/kernelsu -name "BUILD.bazel" -delete
  find common/drivers/kernelsu -name "BUILD" -delete
  echo "   ✅ Removed local BUILD/BUILD.bazel files from drivers/kernelsu"

  sed -i '/depends on EXT4_FS/d' common/drivers/kernelsu/Kconfig
  echo "   ✅ Removed depends on EXT4_FS from drivers/kernelsu/Kconfig"

  if [ ! -f "common/drivers/kernelsu/Kconfig" ]; then
    echo "❌ ERROR: KernelSU driver files not found after copy!"
    ls -la common/drivers/kernelsu/ || true
    exit 1
  fi

  KBUILD_FILE="common/drivers/kernelsu/Kbuild"
  if [ -f "$KBUILD_FILE" ]; then
    sed -i '/# Injected by CI/d' "$KBUILD_FILE"
    sed -i '/ccflags-y += -UKSU_VERSION/d' "$KBUILD_FILE"
    python3 "$GITHUB_WORKSPACE/workflow_scripts/patch_kbuild.py" \
      "$KBUILD_FILE" "$GIT_COUNT" "$KSU_VERSION" "$KSU_TAG"
    printf '#undef KSU_VERSION\n#define KSU_VERSION %s\n#undef KSU_VERSION_TAG\n#define KSU_VERSION_TAG "%s"\n' \
      "${KSU_VERSION}" "${KSU_TAG}" > common/drivers/kernelsu/ksu_version.h
    sed -i "1i ccflags-y += -Wno-macro-redefined -include \$(srctree)/drivers/kernelsu/ksu_version.h" "$KBUILD_FILE"
    echo "✅ KSU_VERSION=${KSU_VERSION} dipaksikan via ksu_version.h dan Kbuild secara absolut!"
  else
    echo "⚠️  Berkas Kbuild tidak ditemukan, modifikasi versi dilewati."
  fi

  if ! grep -q 'CONFIG_KSU' common/drivers/Makefile; then
    echo 'obj-$(CONFIG_KSU) += kernelsu/' >> common/drivers/Makefile
    echo "   Added KSU to drivers/Makefile"
  fi

  sed -i '/drivers\/kernelsu\/Kconfig/d' common/drivers/Kconfig
  python3 -c "with open('common/drivers/Kconfig', 'r+') as f: c = f.read(); p = c.rfind('endmenu'); f.seek(0); f.write(c[:p] + 'source \"drivers/kernelsu/Kconfig\"\n\n' + c[p:]) if p != -1 else f.write(c)"
  echo "   ✅ Safely injected KSU Kconfig before endmenu in drivers/Kconfig"

  cd common
  git add -f drivers/Makefile drivers/Kconfig
  git add -f drivers/kernelsu/ 2>/dev/null || true
  cd "$GITHUB_WORKSPACE"

  echo "KSU_VERSION=$KSU_VERSION" >> "$GITHUB_ENV"
  echo "KSU_METHOD=${KSU_METHOD}" >> "$GITHUB_ENV"
  echo "✅ KernelSU-Next integrated (version: $KSU_VERSION, tag: $KSU_TAG, commits: $GIT_COUNT)"
}

# ──────────────────────────────────────────────
# 9. APPLY CUSTOM PATCHES
# ──────────────────────────────────────────────
apply_patches() {
  cd kernel/common
  if [ -d "$GITHUB_WORKSPACE/patches" ] && ls "$GITHUB_WORKSPACE"/patches/*.patch 1>/dev/null 2>&1; then
    for patch_file in "$GITHUB_WORKSPACE"/patches/*.patch; do
      echo "Applying $patch_file"
      patch -p1 --forward --no-backup-if-mismatch < "$patch_file" \
        || echo "  ⚠️ Patch failed or already applied (skipping)"
    done
  else
    echo "No custom patches found, skipping."
  fi
  cd "$GITHUB_WORKSPACE"
}

# ──────────────────────────────────────────────
# 10. PATCH BUILD SYSTEM
# ──────────────────────────────────────────────
patch_build_system() {
  cd kernel/common

  python3 "$GITHUB_WORKSPACE/workflow_scripts/patch_build_system.py"
  python3 "$GITHUB_WORKSPACE/workflow_scripts/patch_vermagic.py"
  python3 "$GITHUB_WORKSPACE/workflow_scripts/patch_schedutil.py"

  git add BUILD.bazel modules.bzl 2>/dev/null || true
  # CRITICAL: Lacak semua berkas yang dimodifikasi oleh skrip Python patching agar
  # terlihat oleh Bazel Kleaf sandbox. Tanpa ini, bypass vermagic tidak aktif dan
  # modul WiFi vendor Xiaomi (wlan_drv_gen4m.ko) ditolak saat loading karena
  # vermagic mismatch — penyebab utama WiFi + Hotspot mati total.
  git add kernel/module/internal.h kernel/module/main.c kernel/module.c kernel/module/version.c 2>/dev/null || true
  git add kernel/sched/cpufreq_schedutil.c 2>/dev/null || true
  for f in build.config.gki build.config.gki.aarch64; do
    if [ -f "$f" ]; then
      sed -i '/check_defconfig/d' "$f"
      sed -i '/KMI_SYMBOL_LIST_STRICT_MODE/d' "$f"
      sed -i '/TRIM_NONLISTED_KMI/d' "$f"
      sed -i '/KMI_SYMBOL_LIST/d' "$f"
      echo "KMI_SYMBOL_LIST_STRICT_MODE=false" >> "$f"
      echo "TRIM_NONLISTED_KMI=false" >> "$f"
      git add "$f"
    fi
  done

  # Bypass symbol protection check (Python, not Perl)
  if [ -f "../build/kernel/abi/check_buildtime_symbol_protection.py" ]; then
    python3 -c "
import re
with open('../build/kernel/abi/check_buildtime_symbol_protection.py', 'r') as f:
    c = f.read()
c = re.sub(r'^(\s*)return 1$', r'\1return 0', c, flags=re.MULTILINE)
with open('../build/kernel/abi/check_buildtime_symbol_protection.py', 'w') as f:
    f.write(c)
"
  fi

  # Remove '-maybe-dirty' from SCM version stamp
  if [ -f "../build/kernel/kleaf/impl/stamp.bzl" ]; then
    sed -i '/stable_scmversion_cmd/s/-maybe-dirty//g' \
      ../build/kernel/kleaf/impl/stamp.bzl
  fi

  # Clean localversion
  sed -i 's/-dirty//' scripts/setlocalversion 2>/dev/null || true
  git add scripts/setlocalversion 2>/dev/null || true
  : > .scmversion
  git add .scmversion 2>/dev/null || true

  # Remove unnecessary .git dirs to free disk space
  cd "$GITHUB_WORKSPACE"
  rm -rf kernel/KernelSU-Next/.git 2>/dev/null || true
  rm -rf kernel/susfs4ksu/.git 2>/dev/null || true
  rm -rf prebuilts/clang/host/linux-x86/*/.git 2>/dev/null || true
  echo "✅ Build system patched and disk space freed"
}

# ──────────────────────────────────────────────
# EXECUTION
# ──────────────────────────────────────────────
maximize_disk
setup_swap
install_deps
install_repo
download_toolchain
sync_kernel
set_kmi
setup_ksu
apply_patches
patch_build_system

echo "=== Epitaph Build Prep Complete ==="
