# Enumeration Findings — bWAPP | 10.10.30.128 | 2026-03-13-001

## Authentication Status

- Successful login as bee:bug at security_level=1 (medium)
- Session cookie: PHPSESSID (no HttpOnly, no Secure)
- Security level cookie: security_level=1 (persistent, client-controlled)

## bWAPP Vulnerability Catalogue

158 numbered bugs across OWASP Top 10 categories confirmed in the portal. Relevant targets for this mission:

### A1 — Injection (Primary Mission Targets)

| Bug # | Name | Endpoint | Method | Parameters |
|---|---|---|---|---|
| 9 | OS Command Injection | /commandi.php | POST | target |
| 10 | OS Command Injection - Blind | /commandi_blind.php | POST | target |
| 13 | SQL Injection (GET/Search) | /sqli_1.php | GET | title, action |
| 15 | SQL Injection (POST/Search) | /sqli_3.php | POST | title, action |
| 19 | SQL Injection (Login Form/Hero) | /sqli_19.php | POST | login, password |
| 20 | SQL Injection (Login Form/User) | /sqli_20.php | POST | login, password |
| 23 | SQL Injection - Stored (Blog) | /sqli_6.php | POST | entry |

### A2 — Broken Authentication (Secondary Mission Targets)

| Bug # | Name | Endpoint |
|---|---|---|
| 37 | Broken Authentication - Insecure Login Forms | /ba_insecure_login_1.php |
| 40 | Broken Authentication - Weak Passwords | /ba_weak_passwords.php |
| 41 | Session Management - Administrative Portals | /smgmt_admin_portal.php |

### A3 — Cross-Site Scripting (Secondary Mission Targets)

| Bug # | Name | Endpoint | Method | Parameters |
|---|---|---|---|---|
| 62 | Cross-Site Scripting - Stored (Blog) | /xss_stored_1.php | POST | entry |
| 48 | Cross-Site Scripting - Reflected (GET) | /xss_get.php | GET | firstname, lastname |

### Extras

| Bug # | Name | Notes |
|---|---|---|
| 150 | A.I.M. - No-authentication Mode | Direct URL parameter control |
| 155 | Unprotected Admin Portal | /admin/ accessible |

## SQL Injection Endpoint Analysis

### /sqli_1.php (GET/Search) — CONFIRMED INJECTABLE
- Parameters: `title` (GET), `action=search` (GET)
- Response: Returns movie records from MySQL
- Column structure from response: **Title | Release | Character | Genre | IMDb** (5 columns)
- At medium security level: addslashes() applied — requires bypass

### /commandi.php (OS Command Injection)
- Parameter: `target` (POST)
- Behavior: Executes `nslookup <target>` or `ping <target>`
- At medium security level: escapeshellcmd() applied (NOT escapeshellargs())
  - Implication: pipe | and semicolon ; blocked but may have bypasses

### /xss_stored_1.php (Stored XSS Blog)
- Parameter: `entry` (POST, textarea)
- Behavior: Stored in blog, rendered to all users
- At medium security: some tags filtered via htmlspecialchars but may be bypassable via encoding

## Medium Security Filter Analysis

bWAPP medium security (level=1) applies:
- SQL: `addslashes()` — escapes quotes. **Bypass: numeric injection, UNION with no quotes, hex encoding**
- Command: `escapeshellcmd()` — protects shell metacharacters. **Bypass: may still allow some operators**
- XSS: `htmlspecialchars()` with limited scope — **Bypass: attribute injection, event handlers without quotes**

## MySQL Database Structure (from Live Injection Test)

Table: movies — columns: title, release_year, character, genre, imdb_url

## Attack Vectors Prioritized for Exploitation

1. **SQL Injection — Authentication Bypass** on main /login.php (login/password params)
   - Tautological payload: `' OR '1'='1` — medium filter may block quotes
   - Bypass attempt: comment injection `bee'-- -` or numeric `' OR 1=1-- -`

2. **SQL Injection — UNION Data Extraction** on /sqli_1.php
   - 5 columns confirmed: UNION SELECT attacks viable
   - Hex-encode strings to bypass addslashes()

3. **OS Command Injection** on /commandi.php
   - Target param with shell metacharacter bypass at medium level

4. **Stored XSS** on /xss_stored_1.php
   - Attribute/event injection to bypass htmlspecialchars()
