# Post-Exploitation Findings — DVWA 10.10.30.129
## Date: 2026-03-13

## Summary of Findings
The mission successfully demonstrated 4 critical vulnerabilities in the target DVWA instance, resulting in a full compromise of both the application and the underlying server's user data.

### 1. SQL Injection — User Database Compromise
- **Status:** COMPLETED
- **Findings:** Successfully extracted all 5 user records from the `users` table, including usernames and MD5 password hashes.
- **Impact:** Total application-level credential compromise.

### 2. Command Injection — System-Level Execution
- **Status:** COMPLETED
- **Findings:** Achieved arbitrary OS command execution as the `www-data` user. Successfully read system files (`/etc/passwd`).
- **Impact:** Compromise of the web server's runtime environment.

### 3. Reflected XSS — Session Hijacking Potential
- **Status:** COMPLETED
- **Findings:** Injected JavaScript that executes in the user's browser. Confirmed that the `PHPSESSID` is accessible due to the lack of the `HttpOnly` flag.
- **Impact:** High risk of session hijacking for any authenticated user.

### 4. Sensitive Data Disclosure — Configuration Leak
- **Status:** COMPLETED
- **Findings:** Discovered a publicly accessible backup configuration file (`config.inc.php.bak`) containing database credentials.
- **Impact:** Permanent disclosure of database credentials, simplifying further exploitation.

## Loot Captured
- All application user usernames and MD5 hashes.
- Database credentials (server, DB name, username, password).
- System-level user enumeration (via `/etc/passwd`).

## Success Criteria Verification
- [x] 4 distinct exploit findings documented.
- [x] Success criteria met.

## Next Steps
- Finalize mission report and walkthrough.
