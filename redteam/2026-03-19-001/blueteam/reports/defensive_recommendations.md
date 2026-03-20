# Defensive Recommendations — BLUE-2026-03-19-001
**Incident:** BLUE-2026-03-19-001
**Target:** 10.10.30.128 (bWAPP v2.2)
**Generated:** 2026-03-19
**Classification:** CRITICAL — Immediate action required on P0 items

---

## Priority Matrix

| Priority | Count | Rationale |
|---|---|---|
| P0 — Immediate (within 24 hours) | 2 | Actively exploitable, trivial exploitation |
| P1 — Critical (within 1 week) | 3 | Core vulnerability classes; code fixes required |
| P2 — High (within 2 weeks) | 3 | Defense-in-depth; configuration hardening |
| P3 — Medium (within 1 month) | 3 | Monitoring, suppression, disclosure reduction |
| P4 — Low (scheduled) | 2 | Platform-level upgrades |

---

## P0 — Immediate Actions

### P0-1: Set MySQL Root Password

**Current state:** MySQL root account has empty password. Exposed via LFI read of `admin/settings.php` and potentially accessible on all interfaces (0.0.0.0:3306).

**Fix:**
```sql
ALTER USER 'root'@'localhost' IDENTIFIED BY '<strong-random-password>';
FLUSH PRIVILEGES;
```

Update `admin/settings.php` with the new password. Remove `admin/settings.php` from the web root or move it outside of document root entirely.

**Why this is P0:** This credential was exfiltrated in both the 2026-03-13 and 2026-03-19 missions. Every file-read exploit (LFI, XXE, CMDi) leads directly here. Until fixed, any file-read vulnerability = full DB compromise.

---

### P0-2: Disable XML External Entity Loading

**Current state:** `libxml_disable_entity_loader(true)` is commented out in `xxe-2.php`. External entities are resolved at ALL security levels.

**Fix in PHP code:**
```php
// Add BEFORE calling simplexml_load_string()
libxml_disable_entity_loader(true);  // PHP < 8.0
// OR for PHP 8.0+:
$xml = simplexml_load_string($body, 'SimpleXMLElement', LIBXML_NOENT | LIBXML_NONET);
```

**Alternative (defense-in-depth):** Disable `allow_url_fopen` in `php.ini` to prevent HTTP entity resolution even if entity loading is enabled:
```ini
allow_url_fopen = Off
```

Note: `allow_url_fopen=Off` also blocks XXE SSRF via HTTP entities.

**Why this is P0:** XXE is exploitable at every security level. Combined with SSRF, it enables internal network reconnaissance from outside the perimeter.

---

## P1 — Critical Fixes

### P1-1: Remediate Local File Inclusion

**Current state:** `/rlfi.php` passes `$_GET["language"]` directly to `include()` at security_level=0, with no `open_basedir` restriction.

**Fix Option A — Whitelist (recommended):**
```php
$allowed_languages = ['en', 'fr', 'de', 'es', 'nl'];
$language = in_array($_GET["language"], $allowed_languages)
    ? $_GET["language"]
    : 'en';
include("lang/{$language}.php");
```

**Fix Option B — open_basedir in php.ini:**
```ini
open_basedir = /var/www/html/lang:/tmp
```

**Fix Option C — realpath validation:**
```php
$base = realpath('/var/www/html/lang/');
$path = realpath('/var/www/html/lang/' . $_GET["language"] . '.php');
if (strpos($path, $base) === 0) {
    include($path);
}
```

Block PHP stream wrappers entirely:
```ini
; php.ini
allow_url_include = Off  # already Off; keep it that way
```

To additionally block php:// wrappers in include():
- Use `open_basedir` — this restricts php:// stream wrappers to within allowed directories.

---

### P1-2: Fix Broken Authentication — Server-Side Authorization

**Current state:** Admin status determined by GET parameter or cookie value — both client-controlled.

**Fix:**
```php
// On successful login, set server-side session:
$_SESSION["admin"] = ($db_result["admin"] == "1") ? 1 : 0;

// On admin-restricted pages:
if (!isset($_SESSION["admin"]) || $_SESSION["admin"] !== 1) {
    http_response_code(403);
    exit("Access denied.");
}
```

Never read `$_GET["admin"]` or `$_COOKIE["admin"]` for authorization decisions. Authorization state must live exclusively in `$_SESSION` (server-side).

---

### P1-3: Remove/Protect Credential Files from Web Root

**Current state:** `admin/settings.php` containing MySQL root credentials is readable by the web server user (www-data) and reachable via LFI.

**Fix:**
- Move database configuration outside the web root: `/var/app/config/db.php`
- Reference via absolute path in PHP code (not a web-accessible path)
- Verify the file is not served directly by Apache (`<FilesMatch>` deny rule if needed)
- Set file permissions: `chmod 640 /var/app/config/db.php; chown root:www-data`

---

## P2 — High Priority Hardening

### P2-1: Harden Session Cookies

**Current state:** `PHPSESSID` lacks `HttpOnly` flag. Admin cookie lacks both `HttpOnly` and `Secure` flags.

**Fix in PHP:**
```php
session_set_cookie_params([
    'httponly' => true,
    'secure'   => true,    // requires HTTPS
    'samesite' => 'Strict'
]);
```

For the admin cookie specifically, remove it entirely (P1-2 eliminates the need for it). If a cookie is still used for non-auth purposes, apply `httponly` and `secure` flags.

---

### P2-2: Prevent Security Level Downgrade

**Current state:** `security_level` is accepted from the login POST body and stored in a client-accessible cookie. Any user can set `security_level=0` to disable all security controls.

**Fix:**
- Remove `security_level` from the login POST parameter entirely
- Set `security_level` server-side only (admin configuration, not user-supplied)
- If the parameter must exist for lab purposes, validate it against an allowlist and require admin authentication before change

---

### P2-3: Restrict MySQL Network Binding

**Current state:** MySQL is bound to `0.0.0.0:3306` (all interfaces). While currently not publicly reachable, this is accessible from within the Docker network and via SSRF.

**Fix in my.cnf:**
```ini
[mysqld]
bind-address = 127.0.0.1
```

Additionally: firewall MySQL at the host level to prevent any direct external access:
```bash
iptables -A INPUT -p tcp --dport 3306 -s 127.0.0.1 -j ACCEPT
iptables -A INPUT -p tcp --dport 3306 -j DROP
```

---

## P3 — Medium Priority

### P3-1: Suppress PHP Error Output

**Current state:** `display_errors=1` leaks file paths, stack traces, SQL errors, and in the SSRF case, MySQL TCP banner content via XML parse errors.

**Fix in php.ini:**
```ini
display_errors = Off
log_errors = On
error_log = /var/log/php_errors.log
```

This is the difference between a silent failure and an informative error that helps an attacker confirm SSRF success.

---

### P3-2: Remove phpinfo.php from Web Root

**Current state:** `phpinfo.php` is publicly accessible and exposes PHP version, configuration flags, document root, and loaded modules — all used during the reconnaissance phase.

**Fix:**
```bash
rm /var/www/html/phpinfo.php
```

If needed for development, restrict by IP:
```apache
<Files phpinfo.php>
    Require ip 10.10.1.0/24
</Files>
```

---

### P3-3: Sanitize robots.txt

**Current state:** `robots.txt` directly advertises sensitive directories (`/admin/`, `/documents/`, `/passwords/`).

**Fix:** Remove sensitive directory entries from `robots.txt`. Robots.txt is not a security control — it is advisory only and is read by attackers for reconnaissance. True access restriction belongs in the web server configuration (auth gates on sensitive paths).

---

## P4 — Platform Upgrades (Scheduled)

### P4-1: Upgrade PHP from 5.5.9 to 8.x

PHP 5.5.9 reached end-of-life in July 2016. It lacks security patches for numerous CVEs. PHP 8.x includes `libxml_disable_entity_loader()` deprecation and improved default security posture.

### P4-2: Upgrade Ubuntu 14.04 to a Supported LTS

Ubuntu 14.04 reached end-of-life in April 2019. The Docker host kernel is 6.8.0 but the container OS is Ubuntu 14.04 — the container tooling and base packages have unpatched CVEs. Migrate to Ubuntu 22.04 LTS or Ubuntu 24.04 LTS.

---

## Detection Recommendations

### Implement WAF Rules for:
1. Requests with `language` parameter containing `/etc/`, `proc/`, or `php://`
2. POST bodies to any endpoint containing `<!DOCTYPE` + `<!ENTITY` + `SYSTEM`
3. Requests with `?admin=1` to admin endpoints
4. Cookie header `admin=1` on admin endpoints where server issues `admin=0`
5. Login POST with `security_level=0` in body

### Log Enhancement:
- Enable Apache `mod_security` with OWASP CRS
- Log full request bodies for POST endpoints processing XML
- Alert on LFI pattern: GET parameter containing `php://`, `/etc/`, `/proc/`
- Alert on multiple 500 errors from single IP (SSRF timing scan pattern)

### IDS Coverage:
Deploy Suricata on the bWAPP container's traffic. The lab environment currently has no IDS coverage for this host — the Blue Team pipeline operated in artifact-analysis mode as a result. Live alert monitoring would detect LFI and XXE patterns in real time.

---

## Summary

The five most impactful single fixes (in order) are:

1. **Set MySQL root password** — breaks the LFI→credential→DB-compromise kill chain
2. **Uncomment `libxml_disable_entity_loader(true)`** — eliminates XXE + SSRF entirely
3. **Whitelist `language` parameter in rlfi.php** — eliminates LFI class
4. **Move auth to `$_SESSION` in smgmt_admin_portal.php** — eliminates broken auth
5. **Move `admin/settings.php` outside web root** — eliminates credential exposure even if LFI persists

Implementing these five fixes would reduce this incident's severity from CRITICAL to LOW.
