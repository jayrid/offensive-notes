# Scan Findings — bWAPP | 10.10.30.128 | 2026-03-13-001

## Nmap Service Scan Results

| Port | State | Service | Version |
|---|---|---|---|
| 80/tcp | open | http | Apache/2.4.7 (Ubuntu) |
| 3306/tcp | open | mysql | MySQL 5.5.47-0ubuntu0.14.04.1 |

## HTTP Response Headers

```
Server: Apache/2.4.7 (Ubuntu)
X-Powered-By: PHP/5.5.9-1ubuntu4.14
Set-Cookie: PHPSESSID=<value>; path=/   [NO HttpOnly, NO Secure flag]
Cache-Control: no-store, no-cache, must-revalidate
```

## HTTP Methods Supported

GET, HEAD, POST, OPTIONS

## PHP Configuration (from phpinfo.php — EXPOSED)

| Setting | Value | Security Impact |
|---|---|---|
| PHP Version | 5.5.9-1ubuntu4.14 | EOL — multiple known CVEs |
| allow_url_fopen | On | Remote file read possible |
| allow_url_include | Off | Remote file include mitigated |
| open_basedir | No value | No filesystem restriction |
| sql.safe_mode | Off | No SQL safe mode |
| disable_functions | pcntl_* only | System/exec/shell_exec available |

**CRITICAL**: phpinfo.php is publicly accessible — exposes full PHP config, server paths, environment variables.

## Directories with Listing Enabled

| Directory | Contents |
|---|---|
| /passwords/ | heroes.xml, web.config.bak, wp-config.bak |
| /db/ | bwapp.sqlite (12K SQLite database) |
| /admin/ | Admin portal (no auth required) |
| /documents/ | 7 PDF files including bWAPP_intro.pdf |
| /apps/ | movie_search application |
| /soap/ | NuSOAP library PHP files (exposed source) |
| /images/ | Image assets |
| /js/ | JavaScript files |
| /stylesheets/ | CSS files |

## Notable Endpoints Identified

| Endpoint | Status | Notes |
|---|---|---|
| /login.php | 200 | Main login — SQL injection target |
| /admin/index.php | 200 | Admin portal — unauthenticated |
| /phpinfo.php | 200 | Full PHP configuration exposed |
| /info.php | 200 | Application info page |
| /user_new.php | 200 | User registration |
| /test.php | 200 | Test page (empty) |
| /robots.txt | 200 | Discloses sensitive directories |

## Vulnerability Summary from Scan

1. **CVE Attack Surface**: PHP 5.5.9 (EOL since 2016) — numerous unpatched CVEs
2. **Information Disclosure**: phpinfo.php exposed with full server config
3. **No Authentication on Admin**: /admin/ accessible without credentials
4. **MySQL Exposed**: Port 3306 open to network with known credentials (thor/Asgard)
5. **Session Cookie Weakness**: PHPSESSID without HttpOnly or Secure flags
6. **SOAP Library Exposed**: Source code of NuSOAP library browsable
7. **Unrestricted PHP Functions**: system(), exec(), shell_exec() are NOT disabled
