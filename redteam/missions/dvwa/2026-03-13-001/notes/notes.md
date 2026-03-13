# Mission Notes — 2026-03-13-001
## Target: DVWA v1.10 (10.10.30.129)
## Stack: Apache/2.4.25 (Debian), PHP 7.0, MariaDB 10.1.26

---

## Key Observations

### Recon
- Target: DVWA v1.10 (Development) at http://10.10.30.129
- Default credentials confirmed: admin / password
- Security level confirmed: LOW (no input sanitization active)
- 10 DVWA modules identified; priority targets: SQLi, Command Injection, Reflected XSS
- Apache/2.4.25 Debian — moderately outdated server

### Scan
- Single open port: 80/tcp (HTTP only)
- `/config/` directory listing ENABLED — exposes `config.inc.php.bak`
  - Backup file contains plaintext database credentials: host, dbname, user, password (app/vulnerables)
- `PHPSESSID` cookie confirmed missing `HttpOnly` flag — session theft via XSS viable
- Three exploit-ready module endpoints confirmed:
  - SQLi: GET `/vulnerabilities/sqli/?id=`
  - CMDi: POST `/vulnerabilities/exec/`
  - XSS_R: GET `/vulnerabilities/xss_r/?name=`

### Enum
- SQLi: Error-based and UNION-based confirmed; 2-column query structure; MariaDB 10.1.26
- Database `dvwa` confirmed with tables: `users`, `guestbook`
- CMDi: Pipe separator (`|`) bypasses input handling; execution context = `www-data`
- XSS_R: `<script>` tags unescaped in response; cookie accessible (no HttpOnly)
- All 3 vectors confirmed exploit-ready before exploitation phase

### Exploitation
- 4 exploits documented:
  1. SQLi UNION: `999' UNION SELECT user,password FROM users-- -` → 5 user records
  2. CMDi pipe: `127.0.0.1|whoami` → `www-data`; `127.0.0.1|cat /etc/passwd` → /etc/passwd dump
  3. XSS Reflected: `<script>alert(document.cookie)</script>` → PHPSESSID visible (no HttpOnly)
  4. Sensitive data: `config.inc.php.bak` → DB credentials (app/vulnerables)
- DB users: admin, gordonb, 1337, pablo, smithy — MD5 hashes only
  - admin hash: 5f4dcc3b5aa765d61d8327deb882cf99 (= "password")
  - smithy hash: 5f4dcc3b5aa765d61d8327deb882cf99 (= "password") — same password as admin

### Post-Exploitation
- Impact assessment finalized; mission success criteria confirmed met
- www-data user has limited OS privileges — no escalation attempted (out of scope)
- Credential reuse: admin and smithy both use "password" as their DVWA password

---

## Attack Chain Summary
1. Recon → Apache/DVWA identified, default creds work
2. Scan → /config/ open; config.inc.php.bak → plaintext DB creds
3. Enum → SQLi UNION columns confirmed; CMDi via `|` confirmed
4. SQLi → 5 user credentials (MD5) exfiltrated
5. CMDi → arbitrary command execution as www-data; /etc/passwd read
6. XSS Reflected → PHPSESSID exposed (no HttpOnly flag); session hijack vector confirmed
7. Sensitive data → backup config file confirms DB infrastructure

---

## Caveats / Limitations
- Security level was LOW — all exploits are baseline; medium/high levels would require additional bypass techniques
- No privilege escalation attempted (file_upload, CSRF out of scope per mission plan)
- OS password hashes not targeted (only web app layer in scope)
- MD5 hashes in DVWA users table: admin=smithy="password" (trivially crackable)
