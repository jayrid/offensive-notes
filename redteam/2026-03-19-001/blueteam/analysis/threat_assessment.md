# Threat Assessment — BLUE-2026-03-19-001
**Target:** 10.10.30.128 (bWAPP v2.2, Ubuntu 14.04, Apache/2.4.7, PHP 5.5.9)
**Incident ID:** BLUE-2026-03-19-001
**Mission:** 2026-03-19-001
**Generated:** 2026-03-19T02:02:10Z
**Analyst:** blueteam-master (artifact-analysis mode)

---

## Executive Summary

A systematic, multi-vector web application attack was conducted against bWAPP over approximately 59 minutes. The attacker combined Local File Inclusion (LFI), XML External Entity (XXE) injection, Server-Side Request Forgery (SSRF) via XXE, and broken authentication exploitation to achieve full application compromise. Five distinct exploits were confirmed across four challenge categories. The attack resulted in credential exfiltration, filesystem read access, internal service mapping, and administrative privilege escalation — all from the HTTP/80 surface with no requirement for prior authenticated access to sensitive endpoints.

This engagement represents a more sophisticated attack profile than the prior bWAPP mission (2026-03-13-001), which relied on credential files left in the web root. This mission exclusively used injection vulnerabilities and client-side trust failures, demonstrating that the application is vulnerable at multiple independent layers.

---

## Kill Chain Analysis

### Phase 1 — Reconnaissance (00:01–00:05Z)
The attacker performed active fingerprinting: ping confirmation, banner grab on `/`, login with security_level=0 to obtain a low-security session, phpinfo.php enumeration, and robots.txt discovery.

**Defender visibility gap:** robots.txt exposed `/admin/`, `/documents/`, `/passwords/` directly. No authentication required to read phpinfo.php.

### Phase 2 — Scanning (00:06–00:15Z)
Nmap -sV -sC targeted 9 ports, confirming Apache/2.4.7, PHP 5.5.9, and MySQL 3306. A full port scan followed. The attacker leveraged the already-functional LFI on `/rlfi.php` to read `bugs.txt` — a file mapping all available challenge endpoints — effectively replacing standard directory brute force with a single targeted request.

**Defender visibility gap:** An authenticated user enumerating the challenge map via LFI is indistinguishable from normal app usage without parameter-level monitoring.

### Phase 3 — Enumeration (00:15–00:30Z)
Source code of three target files was extracted via PHP wrapper LFI:
- `rlfi.php` — confirmed unsanitized `include($_GET["language"])`
- `xxe-2.php` — confirmed `simplexml_load_string()` with `libxml_disable_entity_loader` commented out
- `smgmt_admin_portal.php` — confirmed `$_GET["admin"]` and `$_COOKIE["admin"]` trust

This phase transformed enumeration into a white-box attack, giving the attacker complete knowledge of all code paths before exploitation.

### Phase 4 — Exploitation (00:30–01:00Z)

**Exploit 1 — LFI /etc/passwd:** Direct read of system user accounts.

**Exploit 2 — LFI PHP Wrapper (DB Credentials):** `php://filter` chain exfiltrated `admin/settings.php`, yielding MySQL root with empty password. This is the highest-impact individual exploit — full database compromise without any DB-layer attack.

**Exploit 3 — XXE File Exfiltration:** POST to `/xxe-2.php` with `file:///etc/passwd` SYSTEM entity. Content stored in MySQL `users.secret` column — deferred exfiltration pathway that persists in the database after the attack session ends.

**Exploit 4 — SSRF via XXE:** HTTP entity `http://127.0.0.1:3306/` caused the server to initiate a TCP connection to MySQL. MySQL's raw TCP banner was returned as a parser error, confirming SSRF and internal service reachability. Internal port scanning is viable via timing differences (~42ms open vs ~96ms closed).

**Exploit 5 — Broken Auth (URL param, level 0):** `?admin=1` on `/smgmt_admin_portal.php` grants admin access with no credential validation.

**Exploit 6 — Broken Auth (Cookie, level 1):** Intercepting `Set-Cookie: admin=0` and resending `admin=1` bypasses medium-security authorization.

### Phase 5 — Post-Exploitation (01:00–01:10Z)
Internal network mapping via `/proc/net/tcp` (read via LFI) revealed:
- MySQL bound to 0.0.0.0:3306 (all interfaces)
- Docker DNS at 127.0.0.11
- Established outbound connection from container to 10.10.1.50:52898 (attacker workstation)

The attacker confirmed MySQL root access pathway via settings.php credentials and the 3306 SSRF vector. Web shell deployment was blocked by `allow_url_include=Off`. No `/etc/shadow` read (not accessible as www-data).

---

## Threat Actor Profile

| Attribute | Assessment |
|---|---|
| Skill Level | Intermediate-Advanced |
| Tools | Standard: curl, nmap, manual HTTP crafting |
| Automation | Minimal — manual targeted exploitation |
| Persistence | Not established (no web shell, no cron, no SSH key) |
| Exfiltration | Local (loot files), deferred DB (XXE to MySQL users table) |
| Lateral Movement | SSRF to internal 10.10.30.x range viable but not executed in this mission |
| Stealth | Moderate — no rate limiting, standard request patterns |

---

## Vulnerability Root Causes

| Vulnerability | Root Cause | Severity |
|---|---|---|
| LFI — Path Traversal | `include($_GET["language"])` with no sanitization, no open_basedir | CRITICAL |
| LFI — PHP Wrapper | Same as above; php:// wrappers not blocked | CRITICAL |
| XXE Injection | `libxml_disable_entity_loader(true)` commented out in all security levels | CRITICAL |
| SSRF via XXE | `allow_url_fopen=On` + external entity loading enabled | CRITICAL |
| Broken Auth (URL) | Authorization state in GET parameter (client-controlled) | HIGH |
| Broken Auth (Cookie) | Authorization state in insecure cookie (no HttpOnly, no Secure) | HIGH |
| Security Downgrade | `security_level` accepted from POST body at login | HIGH |
| Session Cookie | PHPSESSID no HttpOnly (XSS theft viable from prior mission) | MEDIUM |
| MySQL 3306 Exposure | MySQL bound to 0.0.0.0 inside container | MEDIUM |
| Ubuntu 14.04 EOL | End-of-life OS; kernel exploits may be viable at container escape level | MEDIUM |

---

## Chained Attack Paths

### Path A — DB Credential Exfil (Highest Impact)
LFI → php://filter → admin/settings.php → MySQL root/empty → Full DB access

### Path B — Deferred Exfiltration via XXE
XXE → file:///etc/passwd → stored in MySQL users.secret → retrievable by any DB reader

### Path C — Internal Reconnaissance
LFI → /proc/net/tcp → service map → SSRF via XXE → MySQL banner → confirm internal topology

### Path D — Admin Takeover (Zero Auth)
GET /smgmt_admin_portal.php?admin=1 → admin access — no exploit chain required

### Path E — Code-Assisted White-Box Attack
LFI php://filter → source of all target files → exact auth bypass logic revealed → precision exploitation

---

## Comparison to Prior bWAPP Mission (2026-03-13-001)

| Dimension | 2026-03-13-001 | 2026-03-19-001 |
|---|---|---|
| Security Level | Medium | Low + Medium |
| Initial Access Vector | Credential files in web root | LFI direct path traversal |
| Exploit Types | CMDi RCE, SQLi, Stored XSS, Broken Auth | LFI, XXE, SSRF, Broken Auth |
| Credential Exfil | Via CMDi reading settings.php | Via LFI php://filter on settings.php |
| Persistence | Not established | Not established |
| Internal Pivot | Not attempted | SSRF to MySQL 3306 confirmed |
| XXE/SSRF | Not in scope | Both confirmed CRITICAL |
| Code Disclosure | Partial | Full (5 source files read) |

This mission introduces a new attack class (XXE+SSRF chaining) not present in the prior engagement. Both missions converge on the same MySQL root/empty credential disclosure — confirming this is the single most dangerous persistent flaw on this target.

---

## Overall Incident Severity: CRITICAL
