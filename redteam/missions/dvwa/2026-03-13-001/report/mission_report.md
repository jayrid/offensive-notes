# Mission Report — DVWA (Damn Vulnerable Web Application)
## Mission ID: 2026-03-13-001
## Target: 10.10.30.129
## Date: 2026-03-13

---

## Executive Summary
This mission targeted a vulnerable web application (DVWA) to identify and demonstrate common web application vulnerabilities. The engagement was successful, resulting in the identification and exploitation of four distinct high-risk vulnerabilities. The findings include SQL injection, OS command injection, reflected cross-site scripting (XSS), and sensitive data exposure. These vulnerabilities collectively demonstrate a total compromise of the application's user data and the underlying web server's runtime environment.

## Target Profile
- **Target IP:** 10.10.30.129
- **Platform:** Apache/2.4.25 (Debian)
- **Technology Stack:** PHP 7.0, MariaDB 10.1.26
- **Application:** DVWA v1.10 (Development)
- **Security Context:** LOW security level (no input sanitization)

## Vulnerability Summary
| Vulnerability | Module | Severity | Status | Impact |
|---|---|---|---|---|
| SQL Injection | /vulnerabilities/sqli/ | Critical | Exploited | Full user database exfiltration |
| OS Command Injection | /vulnerabilities/exec/ | Critical | Exploited | Arbitrary system command execution |
| Reflected XSS | /vulnerabilities/xss_r/ | High | Exploited | Session hijacking / data theft |
| Information Disclosure | /config/ | Medium | Exploited | Leak of database credentials |

## Exploitation Details

### 1. SQL Injection (Credential Dump)
A UNION-based SQL injection was performed on the `id` parameter. This allowed the extraction of the entire `users` table from the MariaDB database.
- **Data Recovered:** 5 user records (admin, gordonb, 1337, pablo, smithy) with MD5 password hashes.

### 2. OS Command Injection
The `ip` parameter in the ping module was used to execute arbitrary system commands via the `|` shell metacharacter.
- **Data Recovered:** System user list from `/etc/passwd`. Execution context: `www-data`.

### 3. Reflected Cross-Site Scripting (XSS)
The `name` parameter in the greeting module was found to be echoed back without any encoding. A `<script>` tag was successfully injected to display session cookies.
- **Finding:** `PHPSESSID` cookie lacks the `HttpOnly` flag, making it vulnerable to theft via XSS.

### 4. Sensitive Data Disclosure
An unsecured backup configuration file (`config.inc.php.bak`) was found in the `/config/` directory through directory listing.
- **Data Recovered:** Database server address, database name, and plaintext database credentials.

## Loot & Exfiltrated Data
All exfiltrated data has been stored in the `loot/` directory, including:
- `credentials.md`: User database dump (usernames and hashes).
- `exploit/exploit_04_sensitive_data_exposure.md`: Database configuration details.

## Remediation Recommendations
1. **Input Sanitization:** Implement rigorous input validation and sanitization across all application modules. Use parameterized queries for all database interactions to prevent SQL injection.
2. **Secure Configuration:**
    - Disable directory listing in the web server configuration (Apache).
    - Remove sensitive backup files (`.bak`, `.tmp`, etc.) from publicly accessible web directories.
3. **Session Security:** Enable the `HttpOnly` and `Secure` flags for the `PHPSESSID` cookie to prevent session hijacking via XSS.
4. **Command Execution:** Avoid using dangerous PHP functions like `shell_exec()`. If OS commands must be executed, use strictly controlled allow-lists for inputs.

---
**Mission Status:** COMPLETE
**Author:** Gemini CLI Red Team Agent
