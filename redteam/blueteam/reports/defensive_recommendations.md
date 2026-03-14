# Defensive Recommendations — BLUE-2026-03-13-001

**Target**: 10.10.30.128 (bWAPP)
**Incident ID**: BLUE-2026-03-13-001
**Generated**: 2026-03-13T12:22:00Z
**Priority Ordering**: CRITICAL → HIGH → MEDIUM → LONG-TERM

---

## CRITICAL — Immediate (Within 24 Hours)

### REC-001: Remove Active Stored XSS Payload

**Vulnerability**: Exploit #4 — Stored XSS in blog table
**Risk if unaddressed**: Every user visiting the blog page executes attacker JavaScript; session hijacking ongoing

**Action**:
```sql
-- Connect to MySQL and remove malicious entries
mysql -u root -h 127.0.0.1 bWAPP
DELETE FROM blog WHERE entry LIKE '%<script>%';
DELETE FROM blog WHERE entry LIKE '%javascript:%';
DELETE FROM blog WHERE entry LIKE '%onerror=%';
DELETE FROM blog WHERE entry LIKE '%onload=%';
COMMIT;
```

Verify the blog page no longer executes any scripts from stored content.

---

### REC-002: Remove Credential Files from Web Root

**Vulnerability**: Exploit #1 — Credential files in web-accessible directory
**Risk if unaddressed**: Any visitor can download admin and database credentials

**Action**:
```bash
# Remove from web root immediately
rm /app/passwords/wp-config.bak
rm /app/passwords/heroes.xml
rm /app/db/bwapp.sqlite

# Verify removal
ls -la /app/passwords/
ls -la /app/db/
```

If backup files must be retained, store them outside the web root (e.g., `/var/backups/bwapp/`) with appropriate filesystem permissions (600, owned by root).

---

### REC-003: Rotate All Compromised Credentials

**Affected accounts**:

| Account | Type | Action |
|---|---|---|
| A.I.M. | bWAPP admin | Change password immediately |
| bee | bWAPP user | Change password immediately |
| thor | MySQL user | Change password; audit privileges |
| root | MySQL | Set a strong password immediately |
| All heroes.xml | Application | Invalidate and rotate all listed credentials |

```sql
-- Set MySQL root password
ALTER USER 'root'@'localhost' IDENTIFIED BY '<strong-random-password>';
ALTER USER 'thor'@'localhost' IDENTIFIED BY '<strong-random-password>';
FLUSH PRIVILEGES;
```

Additionally, invalidate all active PHPSESSID sessions by restarting the application or clearing the session store.

---

### REC-004: Block MySQL Port 3306 at Network Level

**Vulnerability**: MySQL 5.5.47 bound to 0.0.0.0:3306 — accessible from any network host
**Risk if unaddressed**: Direct database access from any attacker with network access

**Action (iptables)**:
```bash
# Block all external access to MySQL
iptables -I INPUT -p tcp --dport 3306 ! -s 127.0.0.1 -j DROP

# Or with ufw
ufw deny 3306
ufw allow from 127.0.0.1 to any port 3306
```

**MySQL configuration fix** (more durable):
```ini
# /etc/mysql/my.cnf
[mysqld]
bind-address = 127.0.0.1
```

Then restart MySQL: `service mysql restart`

---

### REC-005: Disable Directory Listing on All Paths

**Vulnerability**: 8 directories with listing enabled — exposes file structure and sensitive files
**Risk if unaddressed**: Continued reconnaissance capability for any attacker

**Action (Apache)**:
```apache
# /etc/apache2/apache2.conf or site vhost config
<Directory /app/>
    Options -Indexes
</Directory>
```

Apply this to all web-accessible directories: `/passwords/`, `/db/`, `/admin/`, `/documents/`, `/apps/`, `/soap/`, `/images/`, `/js/`.

---

## HIGH — Within 72 Hours

### REC-006: Implement Prepared Statements / Parameterized Queries

**Vulnerability**: Exploit #2 — SQL Injection on /sqli_16.php
**Root Cause**: String interpolation in SQL queries; `addslashes()` is insufficient protection

**Current vulnerable pattern**:
```php
$login = addslashes($_POST['login']); // INSUFFICIENT
$query = "SELECT * FROM users WHERE login='$login' AND ..."; // DANGEROUS
```

**Correct implementation (PDO)**:
```php
$pdo = new PDO("mysql:host=localhost;dbname=bWAPP", $username, $password);
$stmt = $pdo->prepare("SELECT * FROM users WHERE login = ? AND password = ?");
$stmt->execute([$_POST['login'], sha1($_POST['password'])]);
$user = $stmt->fetch();
```

This applies to ALL database queries in the application — audit every SQL-generating code path.

---

### REC-007: Fix OS Command Injection — Use escapeshellarg() Per Argument

**Vulnerability**: Exploit #3 — OS CMDi on /commandi.php
**Root Cause**: `escapeshellcmd()` applied to whole command string; semicolon not escaped

**Current vulnerable code (approximate)**:
```php
$target = $_POST['target'];
$output = shell_exec(escapeshellcmd("nslookup " . $target)); // WRONG
```

**Correct implementation**:
```php
$target = escapeshellarg($_POST['target']); // Escape the ARGUMENT, not the command
$output = shell_exec("nslookup " . $target);
```

**Even better — whitelist validation**:
```php
// Only allow valid hostname/IP format
if (!preg_match('/^[a-zA-Z0-9.\-]+$/', $_POST['target'])) {
    die("Invalid target format");
}
$target = escapeshellarg($_POST['target']);
$output = shell_exec("nslookup " . $target);
```

---

### REC-008: Fix Stored XSS — Implement Output Encoding

**Vulnerability**: Exploit #4 — Stored XSS on /xss_stored_1.php
**Root Cause**: Blog entries stored and rendered without HTML encoding

**Correct implementation**:
```php
// On input: sanitize before storage
$entry = htmlspecialchars($_POST['entry'], ENT_QUOTES, 'UTF-8');

// On output: always encode when rendering user-supplied content
echo htmlspecialchars($row['entry'], ENT_QUOTES, 'UTF-8');
```

Additionally, implement a Content Security Policy (CSP) header:
```apache
Header set Content-Security-Policy "default-src 'self'; script-src 'self'; object-src 'none';"
```

This prevents inline script execution even if an XSS payload is present.

---

### REC-009: Add Authentication to Admin Portal

**Vulnerability**: /admin/index.php accessible without credentials
**Risk**: Full admin functionality exposed to unauthenticated users

**Action**: Implement session-based authentication on all `/admin/` paths:
```php
// Add to top of every admin PHP file:
session_start();
if (!isset($_SESSION['user']) || $_SESSION['admin'] !== 1) {
    header('Location: /login.php');
    exit;
}
```

Alternatively, use Apache basic auth as a quick compensating control:
```apache
<Directory /app/admin>
    AuthType Basic
    AuthName "Admin Area"
    AuthUserFile /etc/apache2/.htpasswd
    Require valid-user
</Directory>
```

---

### REC-010: Set HttpOnly and Secure Flags on Session Cookie

**Vulnerability**: PHPSESSID without HttpOnly/Secure — readable by JavaScript
**Risk**: XSS payloads can steal session cookies, enabling session hijacking

**PHP configuration** (`php.ini`):
```ini
session.cookie_httponly = 1
session.cookie_secure = 1
session.cookie_samesite = Strict
```

**Or in application code**:
```php
ini_set('session.cookie_httponly', 1);
ini_set('session.cookie_secure', 1);
session_set_cookie_params(['samesite' => 'Strict']);
session_start();
```

---

### REC-011: Remove or Restrict phpinfo.php

**Vulnerability**: phpinfo.php publicly accessible — full server configuration disclosed

**Action**:
```bash
# Remove the file entirely
rm /app/phpinfo.php

# Or restrict to localhost only (Apache)
```
```apache
<Files "phpinfo.php">
    Require ip 127.0.0.1
</Files>
```

---

## MEDIUM — Within 2 Weeks

### REC-012: Upgrade PHP Version

**Current**: PHP 5.5.9 (EOL January 2016 — 10 years without security patches)
**Target**: PHP 8.1+ (current supported branch)

PHP 5.5.9 has numerous known and unpatched CVEs. Upgrading eliminates an entire class of known vulnerability exposure. Review bWAPP compatibility with newer PHP versions.

---

### REC-013: Upgrade MySQL Version

**Current**: MySQL 5.5.47 (EOL December 2018)
**Target**: MySQL 8.0+ or MariaDB 10.6+

MySQL 5.5 is past end-of-life and receives no security patches. Upgrade to a supported version.

---

### REC-014: Add Security Headers

Implement the following HTTP response headers to reduce client-side attack surface:

```apache
Header set X-Content-Type-Options "nosniff"
Header set X-Frame-Options "DENY"
Header set X-XSS-Protection "1; mode=block"
Header set Referrer-Policy "strict-origin-when-cross-origin"
Header set Content-Security-Policy "default-src 'self'; script-src 'self'; object-src 'none'; style-src 'self';"
```

---

### REC-015: Implement Web Application Firewall (WAF)

Deploy a WAF to detect and block common attack patterns before they reach the application layer:

**ModSecurity with OWASP Core Rule Set (CRS)** is a free, effective option for Apache:
```bash
apt-get install libapache2-mod-security2
a2enmod security2
# Download and configure OWASP CRS
```

Key rules to enable:
- SQL injection detection (OWASP CRS rules 942xxx)
- XSS detection (OWASP CRS rules 941xxx)
- Command injection detection (OWASP CRS rules 932xxx)
- Scanner detection (OWASP CRS rules 913xxx)

---

### REC-016: Implement Application Logging and Alerting

Current state: No application-level logging of attacks; no alerting on suspicious patterns.

**Minimum viable logging**:
```php
// Log all authentication attempts
error_log("[AUTH] Login attempt for user: " . $_POST['login'] . " from IP: " . $_SERVER['REMOTE_ADDR']);

// Log all form submissions to sensitive endpoints
error_log("[FORM] POST to " . $_SERVER['REQUEST_URI'] . " from IP: " . $_SERVER['REMOTE_ADDR']);
```

**Deploy Suricata or Snort** with rules targeting:
- SQL injection patterns in HTTP bodies (SID 9000001)
- Shell metacharacters in form fields (SID 9000002)
- Script tags in HTTP bodies (SID 9000003)
- Downloads of .bak and .sqlite files (SID 9000004, SID 9000005)
- External MySQL connection attempts (SID 9000006)

(Full Suricata rule stubs available in: `blueteam/evidence/network_iocs.txt`)

---

## LONG-TERM — Architectural Improvements

### REC-017: Apply Principle of Least Privilege to Database Accounts

The web application should NOT use the MySQL root account. Create a dedicated application user with only the permissions required:

```sql
CREATE USER 'bwapp_app'@'localhost' IDENTIFIED BY '<strong-password>';
GRANT SELECT, INSERT, UPDATE, DELETE ON bWAPP.* TO 'bwapp_app'@'localhost';
REVOKE ALL ON *.* FROM 'bwapp_app'@'localhost';
FLUSH PRIVILEGES;
```

Drop or restrict the `thor` account. Disable remote root login entirely.

---

### REC-018: Upgrade Ubuntu / Harden Container

**Current**: Ubuntu 14.04 LTS (EOL April 2019 — kernel exploits unpatched)
**Risk**: Local privilege escalation CVEs (e.g., CVE-2016-5195 Dirty COW, CVE-2015-1328)

- Upgrade base image to Ubuntu 22.04 LTS or Debian 12
- Apply Docker security hardening: read-only filesystem, no-new-privileges, seccomp profiles
- Ensure container cannot access host network namespaces

---

### REC-019: Implement Password Hashing with bcrypt/Argon2

**Current**: Passwords hashed with unsalted SHA1
- SHA1 is trivially reversible via rainbow tables and GPU cracking
- The hash `6885858486f31043e5839c735d99457f045affd0` = "bug" (instantly crackable)

**Correct implementation**:
```php
// On registration/password change:
$hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 12]);

// On login:
if (password_verify($submitted_password, $stored_hash)) {
    // valid
}
```

---

### REC-020: Implement Multi-Factor Authentication for Admin Accounts

Admin access protected only by a password (or no password, as demonstrated) is insufficient. Implement TOTP-based MFA for all admin accounts using a library such as `php-otp` or a FIDO2/WebAuthn token for high-value administrative functions.

---

## Remediation Priority Matrix

| Rec | Description | Priority | Effort | Impact |
|---|---|---|---|---|
| REC-001 | Remove stored XSS payload | CRITICAL | Minutes | Stops ongoing attack |
| REC-002 | Remove credential files from web root | CRITICAL | Minutes | Stops credential harvest |
| REC-003 | Rotate all compromised credentials | CRITICAL | 1 hour | Invalidates stolen creds |
| REC-004 | Block MySQL 3306 externally | CRITICAL | Minutes | Stops DB exposure |
| REC-005 | Disable directory listing | HIGH | 30 min | Removes recon capability |
| REC-006 | Parameterized queries (SQL) | HIGH | Days | Fixes injection class |
| REC-007 | escapeshellarg() per argument | HIGH | Hours | Fixes RCE |
| REC-008 | Output encoding (XSS) | HIGH | Days | Fixes XSS class |
| REC-009 | Authenticate admin portal | HIGH | Hours | Closes major access gap |
| REC-010 | HttpOnly/Secure on session cookie | HIGH | 30 min | Closes cookie theft vector |
| REC-011 | Remove phpinfo.php | MEDIUM | Minutes | Stops info disclosure |
| REC-012 | Upgrade PHP | MEDIUM | Days | Eliminates EOL CVEs |
| REC-013 | Upgrade MySQL | MEDIUM | Days | Eliminates EOL CVEs |
| REC-014 | Security headers | MEDIUM | 1 hour | Defense-in-depth |
| REC-015 | Deploy WAF (ModSecurity) | MEDIUM | Days | Detects future attacks |
| REC-016 | Logging and alerting | MEDIUM | Days | Detection capability |
| REC-017 | DB least privilege | LOW | Hours | Limits blast radius |
| REC-018 | Upgrade Ubuntu / harden container | LOW | Days | Closes kernel CVEs |
| REC-019 | Migrate to bcrypt/Argon2 | LOW | Days | Closes hash cracking |
| REC-020 | Admin MFA | LOW | Days | Adds auth layer |
