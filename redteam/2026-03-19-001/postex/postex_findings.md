# Post-Exploitation Findings — bWAPP Mission 2026-03-19-001
**Date:** 2026-03-19
**Target:** 10.10.30.128

---

## System Context

| Property | Value |
|---|---|
| Kernel | Linux 6.8.0-100-generic (Ubuntu 24.04 — Docker host kernel) |
| Container OS | Ubuntu 14.04 LTS |
| Web process | www-data (uid=33, gid=33) |
| Document root | /var/www/html |
| App path | /app/ (symlinked or aliased) |

---

## Internal Network Intelligence (via /proc/net/tcp + LFI)

| Address:Port | Decoded | Service |
|---|---|---|
| 0.0.0.0:80 | TCP listen | Apache HTTP |
| 0.0.0.0:3306 | TCP listen | MySQL |
| 127.0.0.11:46549 | 127.0.0.11 | Docker DNS resolver |
| 10.10.1.50:52898 | Established | Outbound connection (lab host) |

**Docker network:** Container is on 10.10.30.0/24. Internal Docker DNS at 127.0.0.11.
Container can reach other internal hosts. SSRF via XXE can be used to port-scan the 10.10.30.x range.

---

## Credential Exfiltration (Loot)

### Database Credentials
```
Server: localhost
Username: root
Password: (empty)
Database: bWAPP
```
**Impact:** Root MySQL access with no password. All bWAPP user accounts, secrets, and application data accessible.

### /etc/passwd Extract
```
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
mysql:x:102:105:MySQL Server,,,:/nonexistent:/bin/false
```
- **Root** account confirmed active
- **www-data** is the web process user
- **/etc/shadow** not readable by www-data (container hardened for shadow)

---

## Persistence / Further Exploitation Paths

| Path | Method | Status |
|---|---|---|
| MySQL root access | Direct 3306 (if port exposed) | Blocked (3306 not publicly reachable) |
| MySQL via XXE SSRF | SYSTEM entity http://127.0.0.1:3306/ | Viable — banner fetched |
| Web shell via LFI+include | php://input with POST body | Blocked (allow_url_include=Off) |
| Web shell via LFI+file write | Need write permission to web root | Not tested |
| PHP code injection | phpi.php (bug 11) — out of scope for this mission | Reserved mission 3 |
| SSRF lateral movement | XXE entity to internal 10.10.30.x | Viable — needs enumeration |

---

## Security Control Gaps

1. **No open_basedir** — LFI can read entire filesystem as www-data
2. **MySQL root with empty password** — local DB fully compromised via SSRF/command exec
3. **libxml_disable_entity_loader commented out** — XXE works at ALL security levels
4. **Client-controlled authorization** — Cookie/GET param admin bypass at low+medium levels
5. **display_errors=1** — Error messages leak file paths, service banners, SQL errors
6. **PHPSESSID no HttpOnly** — Session hijack viable via XSS (from prior mission)

---

## Loot Files
- `/home/jayrid/RedTeam/missions/bwapp/2026-03-19-001/loot/etc_passwd.txt`
- `/home/jayrid/RedTeam/missions/bwapp/2026-03-19-001/loot/db_credentials.txt`
