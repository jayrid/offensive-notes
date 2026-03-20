# Incident Report — BLUE-2026-03-19-001
**Classification:** CRITICAL
**Incident ID:** BLUE-2026-03-19-001
**Target:** 10.10.30.128 (bWAPP v2.2)
**Target Type:** bWAPP (intentionally vulnerable web application)
**Mission Reference:** 2026-03-19-001
**Report Date:** 2026-03-19
**Pipeline Mode:** Artifact-Analysis (no live Suricata IDS)
**Prepared By:** Blue Team Operations (blueteam-master)

---

## 1. Incident Overview

A multi-vector web application attack was conducted against bWAPP v2.2 running on 10.10.30.128 over an approximately 59-minute window (2026-03-19 00:01Z to 01:00Z). The attacker achieved full application compromise using five confirmed exploits spanning Local File Inclusion (LFI), XML External Entity (XXE) injection, Server-Side Request Forgery (SSRF), and Broken Authentication. All attacks were conducted over HTTP port 80 using standard tooling (curl, nmap).

The engagement resulted in exfiltration of system files, database credentials, and application source code. The attacker also confirmed internal service reachability via SSRF and achieved administrative access to the application portal at two security levels without valid admin credentials.

No persistence was established and no lateral movement was executed against internal hosts — but both pathways were confirmed viable.

---

## 2. Timeline of Events

| Time (UTC) | Phase | Event |
|---|---|---|
| 00:01:00 | Recon | Attacker confirmed target reachable; login with bee/bug at security_level=0 |
| 00:01:30 | Recon | phpinfo.php enumerated: PHP 5.5.9, allow_url_fopen=On, open_basedir=(none) |
| 00:02:00 | Recon | robots.txt read: /admin/, /documents/, /passwords/ disclosed |
| 00:05:00 | Recon | Challenge endpoints mapped: /rlfi.php, /smgmt_admin_portal.php confirmed |
| 00:06:00 | Scan | Nmap -sV -sC on 9 ports: Apache/2.4.7, PHP 5.5.9, MySQL 3306 fingerprinted |
| 00:08:00 | Scan | Full port scan (-p-); only 80 and 3306 confirmed open |
| 00:12:00 | Scan | LFI used to read bugs.txt — full challenge endpoint map obtained |
| 00:14:00 | Scan | XXE endpoint /xxe-2.php discovered (not at expected path) |
| 00:20:00 | Enum | rlfi.php source extracted via php://filter — unsanitized include confirmed |
| 00:22:00 | Enum | xxe-2.php source extracted — libxml_disable_entity_loader commented out at ALL levels |
| 00:25:00 | Enum | smgmt_admin_portal.php source extracted — GET/cookie admin bypass logic confirmed |
| 00:30:00 | Exploit | **EXPLOIT 1:** LFI /rlfi.php?language=/etc/passwd — /etc/passwd exfiltrated |
| 00:35:00 | Exploit | **EXPLOIT 2:** LFI php://filter on admin/settings.php — MySQL root/empty credential exfiltrated |
| 00:45:00 | Exploit | **EXPLOIT 3:** XXE POST /xxe-2.php with file:///etc/passwd — /etc/passwd stored in MySQL users.secret for user 'bee' |
| 01:00:00 | Exploit | **EXPLOIT 4:** SSRF via XXE — http://127.0.0.1:3306/ — MySQL banner fetched; internal port scan confirmed viable |
| 01:00:00 | Exploit | **EXPLOIT 5:** Broken auth — GET /smgmt_admin_portal.php?admin=1 — admin access without credentials |
| 01:00:00 | Exploit | **EXPLOIT 6:** Broken auth — Cookie admin=1 at security_level=1 — admin access by cookie manipulation |
| 01:00:00 | Post-Exploit | /proc/net/tcp read via LFI — internal socket table mapped: MySQL 0.0.0.0:3306, Docker DNS 127.0.0.11 |
| 01:05:00 | Post-Exploit | Attacker workstation IP 10.10.1.50 confirmed in established connections |
| 01:10:00 | Post-Exploit | Web shell attempt via php://input — blocked by allow_url_include=Off |
| 01:10:00 | Post-Exploit | /etc/shadow — not readable as www-data (hardened) |
| 01:20:00 | Complete | Mission complete; loot files saved (etc_passwd.txt, db_credentials.txt) |

---

## 3. Attack Vectors and Techniques

### 3.1 Local File Inclusion (LFI) — /rlfi.php

The `language` GET parameter is passed directly to PHP's `include()` function at security_level=0 with no sanitization and no `open_basedir` restriction. The attacker exploited this in two modes:

**Direct path traversal:** Reading `/etc/passwd` and `/proc/net/tcp` by supplying absolute filesystem paths.

**PHP wrapper chain:** Using `php://filter/convert.base64-encode/resource=<path>` to read and base64-encode any PHP source file, including `admin/settings.php` containing plaintext MySQL root credentials.

This single vulnerability enabled white-box disclosure of the entire application — the attacker read source code for all other attack targets before exploiting them.

### 3.2 XXE Injection — /xxe-2.php

`simplexml_load_string()` is called without disabling external entity loading (`libxml_disable_entity_loader(true)` is present but commented out). This allows:

- **File exfiltration:** `file:///etc/passwd` resolved and stored in the database
- **Internal service probing:** `http://127.0.0.1:3306/` triggered a server-side TCP connection to MySQL

The XXE vulnerability is present at ALL security levels because the fix is commented out in a comment noting it "doesn't work with older PHP versions" — but it does work with PHP 5.5.9.

### 3.3 SSRF via XXE

The HTTP SYSTEM entity resolution (allowed by `allow_url_fopen=On`) enabled the attacker to use the web server as a proxy to reach internal services. MySQL at 127.0.0.1:3306 was confirmed via the server returning a MySQL TCP banner as an XML parse error. The same technique is viable for scanning the 10.10.30.x Docker network range.

### 3.4 Broken Authentication — smgmt_admin_portal.php

At security_level=0, the admin portal grants access when `?admin=1` is present in the URL with no further validation. At security_level=1, a client-supplied cookie `admin=1` (replacing the server-issued `admin=0`) grants the same access. Neither level validates admin status against server-side session state.

The admin cookie has no `HttpOnly` or `Secure` flags, making it additionally vulnerable to XSS-based theft (an attack confirmed in prior mission 2026-03-13-001).

### 3.5 Security Level Downgrade

The bWAPP login form accepts `security_level` as a POST body parameter that is stored in the session cookie. By setting `security_level=0` at login, the attacker ensured maximum vulnerability across all challenge endpoints, regardless of the configured server default.

---

## 4. Indicators of Compromise

### 4.1 Network IOCs

| IOC | Type | Description |
|---|---|---|
| `GET /rlfi.php?language=/etc/passwd` | HTTP URI | LFI direct path traversal |
| `GET /rlfi.php?language=php://filter/` | HTTP URI | LFI PHP wrapper |
| `POST /xxe-2.php` with `text/xml` body | HTTP method+header | XXE injection |
| XML body containing `<!ENTITY` + `SYSTEM` | HTTP body pattern | XXE entity declaration |
| `GET /smgmt_admin_portal.php?admin=1` | HTTP URI | Broken auth URL param |
| `Cookie: admin=1` | HTTP header | Broken auth cookie manipulation |
| `POST /login.php` with `security_level=0` | HTTP body | Security downgrade |
| SYN scan to multiple ports from single IP | TCP | Nmap reconnaissance |

### 4.2 Host-Based IOCs

| File | Access Type | Data Compromised |
|---|---|---|
| `/etc/passwd` | Read (LFI + XXE) | System user accounts |
| `/var/www/html/admin/settings.php` | Read (LFI) | MySQL root credentials |
| `/var/www/html/bugs.txt` | Read (LFI) | Full endpoint map |
| `/var/www/html/rlfi.php` | Read (LFI) | LFI source code |
| `/var/www/html/xxe-2.php` | Read (LFI) | XXE source code |
| `/var/www/html/smgmt_admin_portal.php` | Read (LFI) | Auth bypass source code |
| `/proc/net/tcp` | Read (LFI) | Internal service topology |

### 4.3 Credential Compromise

| Credential | Service | Status |
|---|---|---|
| root / (empty) | MySQL | COMPROMISED — root DB access |
| bee / bug | bWAPP | COMPROMISED — normal user |
| A.I.M. / bug | bWAPP | COMPROMISED — admin user |

### 4.4 Database Mutation

- Table: `bWAPP.users` | Column: `secret` | User: `bee`
- Mutated value: full content of `/etc/passwd` (stored via XXE)
- Impact: data integrity violation; persistence of exfiltrated content in DB

---

## 5. Impact Assessment

| Impact Category | Detail |
|---|---|
| Confidentiality | CRITICAL — DB credentials, system files, source code all exfiltrated |
| Integrity | HIGH — MySQL database mutated (users.secret overwritten with /etc/passwd) |
| Availability | None — no denial of service attacks attempted |
| Authentication | CRITICAL — admin access obtained without valid credentials |
| Internal Network | HIGH — internal service map obtained; SSRF lateral movement viable |
| Persistence | NONE — no backdoor established; session-only access |

---

## 6. MITRE ATT&CK Techniques

| Technique | ID | Usage |
|---|---|---|
| Exploit Public-Facing Application | T1190 | LFI + XXE primary access |
| Active Scanning: Vuln Scanning | T1595.002 | Nmap -sV -sC |
| Gather Host Info: Software | T1592.002 | phpinfo.php enumeration |
| Data from Local System | T1005 | /etc/passwd, settings.php via LFI |
| Data from Info Repositories | T1213 | Source code via php://filter |
| Unsecured Credentials: Files | T1552.001 | admin/settings.php credentials |
| Valid Accounts: Default Accounts | T1078.001 | MySQL root empty password |
| System Info Discovery | T1082 | /etc/passwd, phpinfo.php |
| System Network Connections | T1049 | /proc/net/tcp via LFI |
| Network Service Scanning | T1046 | SSRF internal port scan |
| File and Directory Discovery | T1083 | robots.txt, bugs.txt |
| Stored Data Manipulation | T1565.001 | XXE wrote /etc/passwd to DB |
| Abuse Elevation Control | T1548 | Broken auth URL/cookie bypass |

---

## 7. Comparison to Prior Incident (BLUE-2026-03-13-001)

The prior bWAPP engagement relied on credential files left in the web root (`/passwords/wp-config.bak`), which required no injection technique. This mission is more dangerous in that it uses pure injection and logic flaws — techniques that would be effective even if credential files were removed. Both missions converge on the same MySQL root/empty password disclosure, confirming this is the most persistent and critical unresolved flaw on the target.

New attack classes introduced in this mission not seen previously: XXE injection and SSRF via XXE.

---

## 8. Conclusion

bWAPP 10.10.30.128 remains in a critically vulnerable state across multiple independent attack surfaces. The attack demonstrated that a moderately skilled attacker with HTTP access and a valid low-privilege account can achieve full application compromise, credential exfiltration, and administrative takeover within one hour using entirely standard tooling. No authentication bypass, social engineering, or physical access was required.

The highest-risk finding — MySQL root with empty password disclosed via LFI — has been persistent across two separate mission engagements and represents an unmitigated P0 risk. Until this is remediated, any exploit granting file read access (LFI, XXE, CMDi) results in immediate full database compromise.
