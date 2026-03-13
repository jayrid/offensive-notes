# Recon Findings — DVWA 10.10.30.129
## Date: 2026-03-13

## Host Discovery
- Target: 10.10.30.129
- ICMP: Alive (TTL=63, avg RTT=3.1ms — one hop behind NAT, likely Linux)
- HTTP port 80: Active — Apache/2.4.25 (Debian)

## Server Banner & Technology Stack
- Web Server: Apache/2.4.25 (Debian)
- OS (from phpinfo): Linux 6.8.0-100-generic x86_64 (Ubuntu container)
- PHP Version: 7.0 (build Jun 14 2018)
- Application: DVWA v1.10 *Development*
- Session management: PHPSESSID cookie (PHP sessions), security cookie set to "low"
- CSRF token: Present on login form (user_token hidden field)

## Web Application Recon
- Root / redirects (302) to /login.php
- Login page: POST to login.php with username, password, Login, user_token fields
- Default credentials confirmed working: admin / password
- Authenticated successfully — session established

## robots.txt
- Disallow: / (entire app disallowed for robots — no additional path disclosures)

## Exposed Paths / Services
- /phpinfo.php — accessible post-auth, reveals full PHP configuration
- /phpmyadmin/ — 404 (not exposed)
- /.git/ — 404 (not exposed)

## Current Security Level
- Security level: LOW (no input validation active)
- This is optimal for initial exploitation phase

## DVWA Modules Identified (Attack Surface)
| Module | Path | In-Scope |
|---|---|---|
| SQL Injection | /vulnerabilities/sqli/ | YES |
| SQL Injection (Blind) | /vulnerabilities/sqli_blind/ | YES |
| Command Injection | /vulnerabilities/exec/ | YES |
| XSS (Reflected) | /vulnerabilities/xss_r/ | YES |
| XSS (DOM) | /vulnerabilities/xss_d/ | YES |
| XSS (Stored) | /vulnerabilities/xss_s/ | YES |
| File Inclusion | /vulnerabilities/fi/ | YES (enumeration) |
| Brute Force | /vulnerabilities/brute/ | OUT OF SCOPE |
| File Upload | /vulnerabilities/upload/ | OUT OF SCOPE |
| CSRF | /vulnerabilities/csrf/ | OUT OF SCOPE |

## Key Findings for Next Phases
- Target is live, web app is accessible and authenticated
- Security level: LOW — all input sanitization disabled
- Priority targets: SQL Injection (/vulnerabilities/sqli/), Command Injection (/vulnerabilities/exec/), XSS Reflected (/vulnerabilities/xss_r/)
- Session cookie + PHPSESSID captured for scan/enum phases
