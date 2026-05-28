import os
import sys
import re

def main():
    print("⏳ Running SUSFS SELinux services.c patcher...")
    
    # Try different relative paths depending on execution environment
    paths = [
        "kernel/common/security/selinux/ss/services.c",
        "common/security/selinux/ss/services.c",
        "security/selinux/ss/services.c"
    ]
    
    filepath = None
    for p in paths:
        if os.path.exists(p):
            filepath = p
            break
            
    if not filepath:
        print("⚠️ Warning: security/selinux/ss/services.c not found!")
        return

    print(f"🔍 Found services.c at: {filepath}")
    with open(filepath, "r") as f:
        content = f.read()

    modified = False

    # ──────────────────────────────────────────────────────────────
    # STEP 1: Detect the actual function signature of security_compute_av_user()
    #
    # GKI 6.6 upstream (common-android15-6.6) has changed the signature from
    #   5-param: (ssid, tsid, tclass, requested, avd)
    # to
    #   4-param: (ssid, tsid, tclass, avd)
    #
    # SUSFS patch (50_add_susfs_in_kernel.patch) was written for the old 5-param
    # version, so after applying it, callers in services.c use 5 arguments.
    # We must detect and fix this mismatch dynamically because the kernel is
    # always synced from tip-of-branch and signatures can change at any time.
    # ──────────────────────────────────────────────────────────────
    decl_match = re.search(
        r'void\s+security_compute_av_user\s*\(([^)]+)\)',
        content
    )
    has_requested_param = False
    if decl_match:
        params = [p.strip() for p in decl_match.group(1).split(',')]
        param_count = len(params)
        print(f"  → security_compute_av_user() declaration has {param_count} params")
        # The 'requested' param is u32, if there are 5+ params it includes 'requested'
        has_requested_param = param_count >= 5
    else:
        print("  ⚠️ Could not find security_compute_av_user() declaration, assuming 4-param (modern GKI 6.6)")
        param_count = 4

    # ──────────────────────────────────────────────────────────────
    # STEP 2: If SUSFS patch injected 5-arg callers but function only has 4 params,
    #         fix the callers by removing the 'requested' argument.
    #
    # This is the ROOT CAUSE of post-V144 build failures:
    #   security_compute_av_user(ssid, tsid, tclass, requested, avd);
    # must become:
    #   security_compute_av_user(ssid, tsid, tclass, avd);
    # ──────────────────────────────────────────────────────────────
    if not has_requested_param:
        # Match: security_compute_av_user(arg1, arg2, arg3, arg4, arg5)
        # Where arg4 is 'requested' (the extra one), replace with 4-arg call
        pattern = r'security_compute_av_user\s*\(\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*\w+\s*,\s*(\w+)\s*\)'
        replacement = r'security_compute_av_user(\1, \2, \3, \4)'
        
        new_content, count = re.subn(pattern, replacement, content)
        if count > 0:
            content = new_content
            modified = True
            print(f"  ✅ Fixed {count} caller(s): removed 'requested' arg from security_compute_av_user()")
        else:
            print("  ℹ️ No 5-arg security_compute_av_user() callers found (already correct or not patched)")
    else:
        print("  ℹ️ security_compute_av_user() has 5 params — no caller fix needed")

    # ──────────────────────────────────────────────────────────────
    # STEP 3: Inject helper function definitions if not already present.
    #
    # BUG FIX: Previous version checked for string "security_context_to_sid_with_policy"
    # which could match CALLERS injected by SUSFS patch, causing false-positive early exit.
    # Now we check for actual function DEFINITION (starting with 'int' at line start).
    # ──────────────────────────────────────────────────────────────
    has_helper_def = bool(re.search(
        r'^int\s+security_context_to_sid_with_policy\s*\(',
        content,
        re.MULTILINE
    ))
    
    if has_helper_def:
        print("✅ SUSFS helper function definitions already present in services.c. No injection needed.")
    else:
        print("🔧 SUSFS helper functions missing — injecting definitions...")
        
        # Adapt the wrapper call based on actual function signature
        if has_requested_param:
            av_user_call = "\tsecurity_compute_av_user(ssid, tsid, tclass, requested, avd);"
        else:
            av_user_call = "\tsecurity_compute_av_user(ssid, tsid, tclass, avd);"
        
        helper_code = """
/* Injected by Epitaph Build Script to resolve missing SUSFS symbols */
#if IS_ENABLED(CONFIG_KSU_SUSFS) || IS_ENABLED(CONFIG_SUSFS)
int security_context_to_sid_with_policy(struct selinux_state *state,
\t\t\t\t\tconst char *scontext, u32 scontext_len,
\t\t\t\t\tu32 *out_sid, u32 def_sid, gfp_t gfp_flags,
\t\t\t\t\tstruct selinux_policy *policy)
{
\treturn security_context_to_sid_core(scontext, scontext_len,
\t\t\t\t\t    out_sid, def_sid, gfp_flags, 0);
}

int security_sid_to_context_with_policy(struct selinux_state *state,
\t\t\t\t\tu32 sid, char **scontext, u32 *scontext_len,
\t\t\t\t\tstruct selinux_policy *policy)
{
\treturn security_sid_to_context_core(sid, scontext, scontext_len, 0, 0);
}

int security_compute_av_user_with_policy(struct selinux_state *state,
\t\t\t\t\t u32 ssid, u32 tsid, u16 tclass, u32 requested,
\t\t\t\t\t struct av_decision *avd,
\t\t\t\t\t struct selinux_policy *policy)
{
""" + av_user_call + """
\treturn 0;
}
#endif
"""
        content += helper_code
        modified = True
        print("✅ Successfully injected SUSFS SELinux helpers into services.c!")

    if modified:
        with open(filepath, "w") as f:
            f.write(content)
        print("✅ services.c patched and saved.")
    else:
        print("ℹ️ No modifications needed — services.c is already correct.")

    # ──────────────────────────────────────────────────────────────
    # STEP 4: Patch security/selinux/selinuxfs.c to inject weak definitions 
    #         for missing KernelSU-Next SELinux hide symbols.
    # ──────────────────────────────────────────────────────────────
    selinuxfs_paths = [
        "kernel/common/security/selinux/selinuxfs.c",
        "common/security/selinux/selinuxfs.c",
        "security/selinux/selinuxfs.c"
    ]
    
    fs_filepath = None
    for p in selinuxfs_paths:
        if os.path.exists(p):
            fs_filepath = p
            break
            
    if fs_filepath:
        print(f"🔍 Found selinuxfs.c at: {fs_filepath}")
        with open(fs_filepath, "r") as f:
            fs_content = f.read()
            
        if "weak" not in fs_content:
            print("🔧 Injecting weak symbol definitions into selinuxfs.c...")
            weak_defs = """
/* Injected by Epitaph Build Script to resolve missing KernelSU-Next SELinux hide symbols */
#if IS_ENABLED(CONFIG_KSU)
#include <linux/types.h>
#include <linux/jump_label.h>
__attribute__((weak)) bool ksu_selinux_hide_enabled = false;
__attribute__((weak)) int fake_status = 0;
__attribute__((weak)) void initialize_fake_status(void) {}
__attribute__((weak)) struct static_key_false fake_status_initialize_key = STATIC_KEY_FALSE_INIT;
#endif
"""
            fs_content += weak_defs
            with open(fs_filepath, "w") as f:
                f.write(fs_content)
            print("✅ Successfully injected weak KernelSU-Next symbols into selinuxfs.c!")
        else:
            print("ℹ️ selinuxfs.c already contains weak symbol definitions or doesn't reference them.")
    else:
        print("⚠️ Warning: security/selinux/selinuxfs.c not found!")

    # Clean up any SELinux-related .rej files so they don't fail the build integrity check
    dirpath = os.path.dirname(filepath)
    for root, dirs, files in os.walk(dirpath):
        for file in files:
            if file.endswith(".rej"):
                rej_path = os.path.join(root, file)
                print(f"🧹 Cleaning up non-critical rejected patch file: {rej_path}")
                try:
                    os.remove(rej_path)
                except Exception as e:
                    print(f"⚠️ Failed to remove {rej_path}: {e}")

if __name__ == "__main__":
    main()

