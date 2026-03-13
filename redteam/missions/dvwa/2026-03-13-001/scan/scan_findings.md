# Scan Findings — DVWA 10.10.30.129
## Date: 2026-03-13

## Port Scan Results (nmap -sV -sC + full -p-)
| Port | State | Service | Version |
|---|---|---|---|
| 80/tcp | OPEN | HTTP | Apache/2.4.25 (Debian) |
| 21/tcp | closed | FTP | — |
| 22/tcp | closed | SSH | — |
| 443/tcp | closed | HTTPS | — |
| 3306/tcp | closed | MySQL | — (not externally exposed) |

Only port 80 is open. Attack surface is entirely web application.

## Nmap HTTP Script Results
- http-robots.txt: Disallow / (confirmed from recon)
- PHPSESSID cookie: httponly flag NOT SET (cookie accessible via JavaScript — XSS session hijack possible)
- HTTP methods supported: GET, HEAD, POST, OPTIONS
- Auth method: FORM-based (login.php)
- No shellshock detected on common CGI paths

## Directory Enumeration
| Path | HTTP Code | Notes |
|---|---|---|
| /dvwa/ | 200 | Directory listing enabled — CSS/images/JS exposed |
| /config/ | 200 | CRITICAL: Directory listing enabled |
| /config/config.inc.php | 200 | PHP config (executes, does not expose raw) |
| /config/config.inc.php.bak | 200 | CRITICAL: Plaintext backup — DB credentials exposed |
| /config/config.inc.php.dist | 200 | Template file exposed |
| /includes/ | 404 | |
| /database/ | 404 | |
| /admin/ | 404 | |

## CRITICAL FINDING: Database Credentials Exposed via Config Backup
File: http://10.10.30.129/config/config.inc.php.bak
```
$_DVWA[ 'db_server' ]   = '127.0.0.1';
$_DVWA[ 'db_database' ] = 'dvwa';
$_DVWA[ 'db_user' ]     = 'app';
$_DVWA[ 'db_password' ] = 'vulnerables';
```
- Database: MySQL (DVWA schema)
- DB not externally accessible (port 3306 closed) but credentials confirm SQLi will yield real data
- Default security level confirmed: 'low'
- PHPIDS: disabled

## Module Attack Surface Confirmed
- SQL Injection: GET parameter `id` — /vulnerabilities/sqli/?id=&Submit=Submit
- Command Injection: POST parameter `ip` — /vulnerabilities/exec/ (ping wrapper)
- XSS Reflected: GET parameter `name` — /vulnerabilities/xss_r/?name=
- All confirmed accessible with current session cookies

## Cookie Security Issues
- PHPSESSID: No HttpOnly flag (exploitable via XSS)
- security cookie: No HttpOnly, no Secure flag — client-modifiable
- Session fixation potential noted (security level settable via cookie)
