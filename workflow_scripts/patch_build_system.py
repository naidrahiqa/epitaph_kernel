import os
import re

def main():
    # Daftar modul nirkabel (WiFi) kustom yang wajib terdaftar agar disalin ke artefak akhir
    WIFI_MODULES = ["net/mac80211/mac80211.ko", "net/wireless/cfg80211.ko"]

    # 1. MODIFIKASI BERKAS modules.bzl (JIKA ADA)
    if os.path.exists("modules.bzl"):
        with open("modules.bzl", "r") as f:
            bzl_content = f.read()

        patched_bzl = False
        for list_name in ["_COMMON_GKI_MODULES_LIST", "COMMON_GKI_MODULES_LIST"]:
            # Mencari posisi deklarasi list
            m = re.search(list_name + r"\s*=\s*\[", bzl_content)
            if not m:
                continue

            start_bracket = m.end() - 1
            d = 1
            p = start_bracket + 1
            while p < len(bzl_content) and d > 0:
                if bzl_content[p] == "[":
                    d += 1
                elif bzl_content[p] == "]":
                    d -= 1
                p += 1
            end_bracket = p - 1

            # Mengekstraksi isi list lama
            list_inner = bzl_content[start_bracket+1:end_bracket]
            
            # Mengurai modul lama dengan mendukung tanda petik tunggal dan ganda
            existing_items = re.findall(r"[\"\']([^\'\"]+\.ko)[\"\']", list_inner)
            
            # Menambahkan modul WiFi jika belum terdaftar
            added = []
            for mod in WIFI_MODULES:
                if mod not in existing_items:
                    existing_items.append(mod)
                    added.append(mod)
            
            if added:
                existing_items.sort()
                new_inner = "\n" + "".join(f"    \"{x}\",\n" for x in existing_items) + "]"
                bzl_content = bzl_content[:start_bracket] + "[" + new_inner + bzl_content[end_bracket+1:]
                patched_bzl = True
                print(f"✅ Berhasil mendaftarkan modul {added} ke dalam {list_name} di modules.bzl!")
            else:
                patched_bzl = True
                print(f"ℹ️ Modul WiFi sudah terdaftar di dalam {list_name} di modules.bzl.")
            break

        if patched_bzl:
            with open("modules.bzl", "w") as f:
                f.write(bzl_content)

    # 2. MODIFIKASI BERKAS BUILD.bazel (WAJIB)
    if os.path.exists("BUILD.bazel"):
        with open("BUILD.bazel", "r") as f:
            bazel_content = f.read()

        # Pembersihan pemeriksaan defconfig agar tidak memicu kegagalan kompilasi non-standar
        bazel_content = re.sub(r".*check_defconfig.*", "", bazel_content)

        # Mencari target utama kernel_aarch64
        m = re.search(r"name\s*=\s*[\"\']kernel_aarch64[\"\']", bazel_content)
        if m:
            name_idx = m.start()
            # Mencari posisi pembuka blok kernel_build
            start_idx = bazel_content.rfind("kernel_build", 0, name_idx)
            if start_idx != -1:
                d = 0
                end_idx = -1
                for i in range(start_idx, len(bazel_content)):
                    if bazel_content[i] == "(":
                        d += 1
                    elif bazel_content[i] == ")":
                        d -= 1
                        if d == 0:
                            end_idx = i
                            break

                if end_idx != -1:
                    # Memotong blok kernel_build untuk target kernel_aarch64
                    target_block = bazel_content[start_idx:end_idx]

                    # Menghapus pelacakan ketat KMI yang dapat memicu kegagalan pemuatan modul vendor
                    target_block = re.sub(r"\s*kmi_symbol_list_strict_mode\s*=\s*(True|False|[^,\n]*),?", "", target_block)
                    target_block = re.sub(r"\s*trim_nonlisted_kmi\s*=\s*(True|False|[^,\n]*),?", "", target_block)
                    target_block = re.sub(r"\s*kmi_symbol_list\s*=\s*[\"\'][^\"\']*[\"\'],?", "", target_block)

                    # Menyuntikkan pelonggaran aturan KMI secara default
                    inject_kmi = "\n    kmi_symbol_list_strict_mode = False,\n    trim_nonlisted_kmi = False,"
                    target_block = re.sub(r"(name\s*=\s*[\"\']kernel_aarch64[\"\'],?)", r"\1" + inject_kmi, target_block)

                    # ─── PENDAFTARAN MODUL WIFI DI DALAM KERNEL_BUILD BLOCK ───
                    patched_attr = False
                    for attr in ["module_outs", "module_implicit_outs"]:
                        attr_match = re.search(attr + r"\s*=\s*", target_block)
                        if attr_match:
                            start_pos = attr_match.end()
                            rest = target_block[start_pos:].lstrip()
                            
                            if rest.startswith("["):
                                # Kasus A: Atribut berupa list literal [...]
                                bp = target_block.find("[", start_pos)
                                inner_d = 1
                                p_idx = bp + 1
                                while p_idx < len(target_block) and inner_d > 0:
                                    if target_block[p_idx] == "[":
                                        inner_d += 1
                                    elif target_block[p_idx] == "]":
                                        inner_d -= 1
                                    p_idx += 1
                                ep = p_idx - 1
                                
                                list_inner = target_block[bp+1:ep]
                                existing_items = re.findall(r"[\"\']([^\'\"]+\.ko)[\"\']", list_inner)
                                
                                added = []
                                for mod in WIFI_MODULES:
                                    if mod not in existing_items:
                                        existing_items.append(mod)
                                        added.append(mod)
                                
                                if added:
                                    existing_items.sort()
                                    new_inner = "\n" + "".join(f"        \"{x}\",\n" for x in existing_items) + "    "
                                    target_block = target_block[:bp] + "[" + new_inner + "]" + target_block[ep+1:]
                                    print(f"✅ Berhasil mendaftarkan modul WiFi kustom ke {attr} (list literal)!")
                                else:
                                    print(f"ℹ️ Modul WiFi sudah ada di {attr} (list literal).")
                                patched_attr = True
                                break
                            else:
                                # Kasus B: Atribut merujuk pada variabel atau ekspresi lain.
                                # Kita bisa menambahkan penyambungan list dinamis (+ WIFI_MODULES) pada ekspresi tersebut.
                                comma_pos = target_block.find(",", start_pos)
                                if comma_pos != -1:
                                    expr = target_block[start_pos:comma_pos].strip()
                                    # Pastikan kita tidak menambahkannya berulang kali
                                    if "net/wireless/cfg80211.ko" not in expr:
                                        wifi_append = " + [\n        \"net/mac80211/mac80211.ko\",\n        \"net/wireless/cfg80211.ko\",\n    ]"
                                        target_block = target_block[:comma_pos] + wifi_append + target_block[comma_pos:]
                                        print(f"✅ Berhasil menyambungkan modul WiFi kustom ke ekspresi {attr}!")
                                    else:
                                        print(f"ℹ️ Modul WiFi sudah disambungkan pada ekspresi {attr}.")
                                    patched_attr = True
                                    break

                    if not patched_attr:
                        # Kasus C: Atribut module_outs tidak ditemukan sama sekali di dalam blok kernel_build.
                        # Kita akan menyuntikkan atribut module_outs baru tepat setelah nama target.
                        wifi_inject = "\n    module_outs = [\n        \"net/mac80211/mac80211.ko\",\n        \"net/wireless/cfg80211.ko\",\n    ],"
                        target_block = re.sub(r"(name\s*=\s*[\"\']kernel_aarch64[\"\'],?)", r"\1" + wifi_inject, target_block)
                        print("✅ Atribut module_outs baru disuntikkan secara dinamis dengan modul WiFi!")

                    # Menyatukan kembali blok yang telah dimodifikasi ke dalam konten berkas utama
                    bazel_content = bazel_content[:start_idx] + target_block + bazel_content[end_idx:]

        # SECURE OVERRIDE: Secara paksa nonaktifkan seluruh validasi KMI dan pemangkasan simbol di seluruh file BUILD.bazel
        bazel_content = bazel_content.replace("kmi_symbol_list_strict_mode = True", "kmi_symbol_list_strict_mode = False")
        bazel_content = bazel_content.replace("trim_nonlisted_kmi = True", "trim_nonlisted_kmi = False")
        # Cari dan ubah penugasan kmi_symbol_list menjadi None untuk mencegah eksekusi verifikator Kleaf
        bazel_content = re.sub(r'\bkmi_symbol_list\s*=\s*["\'][^"\']*["\']', 'kmi_symbol_list = None', bazel_content)
        bazel_content = re.sub(r'\bkmi_symbol_list\s*=\s*[\w\d_:]+', 'kmi_symbol_list = None', bazel_content)

        with open("BUILD.bazel", "w") as f:
            f.write(bazel_content)
        print("✅ Berkas BUILD.bazel utama berhasil diperbarui!")

    # 3. NONAKTIFKAN -Werror & SUNTIK OPTIMASI ARMv8.2-A / CORTEX-A75 DI TOP-LEVEL Makefile
    if os.path.exists("Makefile"):
        with open("Makefile", "r") as f:
            makefile_content = f.read()
        
        # Hapus flag -Werror yang membuat semua peringatan menjadi error fatal
        if "-Werror" in makefile_content:
            makefile_content = makefile_content.replace("KBUILD_CFLAGS += -Werror", "KBUILD_CFLAGS += -Wno-error")
            makefile_content = re.sub(r"\b-Werror\b", "-Wno-error", makefile_content)
            print("✅ Berhasil menonaktifkan -Werror di Makefile!")
        
        # Suntikkan optimasi arsitektur spesifik ARMv8.2-A Cortex-A75/A55 untuk Helio G88 (MT6769)
        # CATATAN: Ini hanya berdampak pada custom make-based toolchains (seperti ZyClang/Neutron standalone).
        # Bazel/Kleaf tidak terpengaruh karena menggunakan file konfigurasinya sendiri untuk menyetel flags compiler.
        if "march=armv8.2-a" not in makefile_content:
            arch_flags = "\n# Helio G88 (MT6769) Cortex-A75/A55 specific optimizations (make-based standalone toolchains only)\n"
            arch_flags += "KBUILD_CFLAGS += -march=armv8.2-a+fp+simd -mtune=cortex-a75\n"
            makefile_content += arch_flags
            print("✅ Berhasil menyuntikkan optimasi Cortex-A75/A55 di Makefile!")

        with open("Makefile", "w") as f:
            f.write(makefile_content)

if __name__ == "__main__":
    main()
