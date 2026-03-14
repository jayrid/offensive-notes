# Recon Findings — bWAPP | 10.10.30.128 | 2026-03-13-001

## Target Profile

| Field | Value |
|---|---|
| IP | 10.10.30.128 |
| Application | bWAPP (an extremely buggy web app) |
| Entry Point | http://10.10.30.128/login.php |
| Web Server | Apache/2.4.7 (Ubuntu) |
| PHP Version | PHP/5.5.9-1ubuntu4.14 |
| MySQL Version | MySQL 5.5.47-0ubuntu0.14.04.1 |
| OS | Ubuntu 14.04 |

## Open Ports

| Port | Service | Version |
|---|---|---|
| 80/tcp | HTTP | Apache/2.4.7 (Ubuntu) |
| 3306/tcp | MySQL | 5.5.47-0ubuntu0.14.04.1 |

## Security Headers

- PHPSESSID cookie: **HttpOnly flag NOT set** (session hijacking possible)
- No CSP, X-Frame-Options, or X-XSS-Protection headers observed

## robots.txt Disclosures

```
Disallow: /admin/
Disallow: /documents/
Disallow: /images/
Disallow: /passwords/
```

## Directory Listings Exposed

| Path | Status | Contents |
|---|---|---|
| /passwords/ | 200 | heroes.xml, web.config.bak, wp-config.bak |
| /db/ | 200 | bwapp.sqlite |
| /admin/ | 200 | bWAPP Admin Portal (unauthenticated access) |

## Sensitive File Exposure

### /passwords/heroes.xml — Plaintext Credentials
```
neo:trinity
alice:loveZombies
thor:Asgard
wolverine:Log@N
johnny:m3ph1st0ph3l3s
selene:m00n
```

### /passwords/wp-config.bak — Database Config Leaked
- DB_NAME: bWAPP
- DB_USER: thor
- DB_PASSWORD: Asgard
- DB_HOST: localhost

### /db/bwapp.sqlite — Full SQLite Database Download
- Tables: users, heroes, movies, blog

## Users Table Dump (from bwapp.sqlite)

| ID | Login | Password Hash (SHA1) | Email | Admin |
|---|---|---|---|---|
| 1 | A.I.M. | 6885858486f31043e5839c735d99457f045affd0 | bwapp-aim@mailinator.com | 1 |
| 2 | bee | 6885858486f31043e5839c735d99457f045affd0 | bwapp-bee@mailinator.com | 0 |

**Note**: Both users share the same SHA1 hash — likely both use password "bug" (default bWAPP credential).

## Attack Surface Summary

1. **Login Portal** — http://10.10.30.128/login.php — SQL injection target
2. **Admin Portal** — http://10.10.30.128/admin/ — accessible without authentication
3. **MySQL port 3306** — directly exposed, credentials available from wp-config.bak
4. **Directory Listings** — /passwords/, /db/, /admin/ all browsable
5. **Sensitive Files** — heroes.xml (plaintext creds), wp-config.bak (DB creds), bwapp.sqlite (full DB)
6. **Session Security** — PHPSESSID without HttpOnly — XSS → session hijack vector
