# CVEs Identified - Pterodactyl

## CVE-2025-6018 — PAM/Polkit Active Session Bypass

| Field | Value |
|-------|-------|
| CVE ID | CVE-2025-6018 |
| CVSS Score | 7.8 (High) |
| Affected Service | Linux PAM (`pam_env.so`) versions 1.3.0–1.6.0 on SUSE 15 |
| Affected System | openSUSE Leap 15.x, SUSE Linux Enterprise 15 SP1–SP6 |
| Discovered By | Qualys Threat Research Unit (TRU) |

### Description
A PAM environment variable injection vulnerability in `pam_env.so` that allows users to poison their session environment via `~/.pam_environment`. By setting XDG session variables (`XDG_SEAT`, `XDG_VTNR`, `XDG_SESSION_TYPE`, `XDG_SESSION_CLASS`), an attacker can trick `systemd-logind` into granting `allow_active` PolicyKit privileges, making a remote SSH session appear as a local physical console session.

### Exploit Source
- Qualys Advisory: https://www.qualys.com/2025/06/17/suse15-pam-udisks-lpe.txt
- GitHub PoC: https://github.com/MichaelVenturella/CVE-2025-6018-6019-PoC

### Applicability
CONFIRMED applicable. Target runs openSUSE (kernel 6.4.0-150600.23.65-default). Creating `~/.pam_environment` with XDG variables successfully elevated session to `allow_active`, enabling udisksctl loop-setup without password.

---

## CVE-2025-6019 — libblockdev/UDisks2 XFS SUID Race Condition

| Field | Value |
|-------|-------|
| CVE ID | CVE-2025-6019 |
| CVSS Score | 7.8 (High) |
| Affected Service | libblockdev (used by udisks2) |
| Affected System | openSUSE Leap 15.x, SUSE Linux Enterprise 15, Ubuntu, Debian, Fedora |
| Discovered By | Qualys Threat Research Unit (TRU) |

### Description
libblockdev fails to apply the `nosuid` security flag when temporarily mounting a filesystem for maintenance operations (Filesystem.Resize D-Bus call). When a resize is triggered on a loop device containing a crafted XFS filesystem with a SUID-root bash binary, libblockdev mounts the filesystem at `/tmp/blockdev.XXXXX/` WITHOUT the `nosuid,nodev` flags, allowing execution of the SUID binary.

The standard udisksctl mount uses `nosuid,nodev,noexec`, but the internal maintenance mount during Resize does not. This creates a race window where the SUID binary can be executed from the temporary mount point.

### Exploit Source
- Qualys Advisory: https://www.qualys.com/2025/06/17/suse15-pam-udisks-lpe.txt
- GitHub PoC: https://github.com/guinea-offensive-security/CVE-2025-6019
- GitHub PoC: https://github.com/And-oss/CVE-2025-6019-exploit

### Applicability
CONFIRMED applicable. Target has udisks2 installed. After obtaining `allow_active` via CVE-2025-6018, the Filesystem.Resize call successfully caused libblockdev to mount XFS at `/tmp/blockdev.8I27L3/` without nosuid, allowing execution of SUID bash to obtain root.

---

## Exploit Chain

CVE-2025-6018 → CVE-2025-6019:

1. SSH user (`phileasfogg3`) creates `~/.pam_environment` with XDG session variables
2. Next SSH login picks up PAM env vars, `systemd-logind` grants `allow_active`
3. `udisksctl loop-setup` now works without password (requires `allow_active`)
4. XFS image containing SUID-root bash (planted via mkfs.xfs protofile `-p`) is loop-mounted
5. Continuous `Filesystem.Resize` D-Bus calls trigger libblockdev internal mount without nosuid
6. Temporary mount appears at `/tmp/blockdev.*/`
7. Execute `bash -p` from temporary mount to obtain `euid=0 (root)`
