# Blue Team Incident Report
## Incident ID: INC-2026-03-12-001
## Mission Reference: 2026-03-12-001
## Classification: LAB / TRAINING USE ONLY
## Generated: 2026-03-13T15:39:30Z

---

## Incident Summary

**Target:** OWASP Juice Shop v19.2.0-SNAPSHOT — http://10.10.30.130:3000
**Attack Window:** 2026-03-12T19:11:34Z – 2026-03-12T20:12:00Z (approximately 61 minutes)
**Overall Severity:** CRITICAL
**Confirmed Findings:** 8 (2 Critical, 5 High, 1 Medium)
**False Positives:** 0

A complete attack chain was executed against the Juice Shop web application. An unauthenticated external actor achieved full administrative compromise, exfiltrated all 22 user credentials, planted a persistent Cross-Site Scripting payload, and downloaded a KeePass credential database — all without triggering any defensive controls. The attack proceeded from recon through post-exploitation in under 50 minutes of active work.

---

## Alert Timeline

| Alert ID | Detected Behavior | Time (UTC) | Severity |
|---|---|---|---|
| ALT-001 | SQL injection — OR tautology in POST /rest/user/login | 2026-03-12T19:50:xx | CRITICAL |
| ALT-002 | UNION-based SQLi — credential dump from /rest/products/search | 2026-03-12T19:55:xx | CRITICAL |
| ALT-003 | Null byte path traversal — /ftp/*.bak%2500.md | 2026-03-12T19:52:xx | HIGH |
| ALT-004 | Stored XSS payload in PUT /rest/products/1/reviews | 2026-03-12T19:54:xx | HIGH |
| ALT-005 | Open directory listing at /ftp/ (unauthenticated) | 2026-03-12T19:52:xx | HIGH |
| ALT-006 | IDOR — sequential basket ID enumeration | 2026-03-12T20:01:xx | HIGH |
| ALT-007 | Unauthenticated Prometheus metrics at /metrics | 2026-03-12T19:14:xx | MEDIUM |
| ALT-008 | Unauthenticated admin config at /rest/admin/application-configuration | 2026-03-12T19:14:xx | HIGH |

---

## Confirmed Findings

---

### FINDING 1 — SQL Injection: Authentication Bypass
**Alert:** ALT-001
**Severity:** CRITICAL | CVSS 9.8
**OWASP:** A03:2021 Injection | CWE-89

The `/rest/user/login` endpoint concatenates the email field directly into SQL. The payload `' OR 1=1--` returned the admin account JWT on the first attempt. The JWT payload itself exposed the admin MD5 hash, which was cracked to `admin123` offline.

**Attacker impact:** Full admin access obtained. Authentication control completely bypassed. All admin-only API endpoints accessible. Secondary password exposure via JWT payload.

**Detection opportunity:** SQL syntax characters in JSON body fields (`'`, `--`, `OR 1=1`) are readily detectable by WAF rules, application-layer logging with anomaly detection, or parameterized query enforcement at the ORM level.

**Remediation:**
1. Replace raw SQL concatenation with Sequelize parameterized queries (`findOne({ where: { email: ? } })`)
2. Implement input validation — reject `'`, `--`, SQL keywords in email field
3. Strip sensitive fields (password hash, TOTP secret) from JWT payload; include only `userId` and `role`
4. Replace unsalted MD5 with bcrypt (cost 12+) or Argon2id; force password reset after migration
5. Implement account lockout after 5 failed login attempts

---

### FINDING 2 — SQL Injection: UNION Credential Dump
**Alert:** ALT-002
**Severity:** CRITICAL | CVSS 9.8
**OWASP:** A03:2021 Injection | CWE-89

The `/rest/products/search?q=` endpoint passes the `q` parameter unsanitized into a SQLite LIKE query. A 9-column UNION SELECT extracted all records from the `Users` table in a single HTTP request — 22 email/hash pairs returned immediately.

**Attacker impact:** Complete credential database exfiltrated. All 22 user account hashes (unsalted MD5) exposed. Additional exploitation of `sqlite_master` possible to dump full schema. Admin credentials confirmed cracked.

**Detection opportunity:** HTTP 500 error on malformed input (`'))`) is a direct leak of SQL error state. The UNION payload in the query string is distinctive and detectable by IDS/WAF string matching.

**Remediation:**
1. Parameterize all ORM queries — eliminate raw string interpolation in search handlers
2. Least-privilege database user — the app account should not have SELECT access to `Users` from the search handler context
3. Input validation — reject `)`, `UNION`, `SELECT`, `--` in search parameters
4. Rate-limit the search endpoint; alert on HTTP 500 from search paths
5. Replace MD5 with bcrypt/Argon2id for all stored passwords

---

### FINDING 3 — Open FTP Directory + Null Byte Path Traversal
**Alert:** ALT-003, ALT-005
**Severity:** HIGH | CVSS 7.5
**OWASP:** A02:2021 Cryptographic Failures / A05:2021 Security Misconfiguration | CWE-22, CWE-200

The `/ftp/` path serves a directory listing without authentication, containing 11 files including a KeePass credential database, confidential acquisition documents, and backup files. A Poison Null Byte bypass (`%2500`) defeats the extension filter on `.bak` files, exposing the full dependency manifest and coupon codes.

**Files exfiltrated:**
- `incident-support.kdbx` — KeePass 2.x database (3246 bytes, offline cracking pending)
- `coupons_2013.md.bak` — 12 active discount coupon codes
- `package.json.bak` — Full dependency manifest; confirms `sanitize-html 1.4.2` (CVE-2016-1000171)
- `acquisitions.md` — Confidential M&A document

**Detection opportunity:** Directory listing requests with no referrer, repeated GET requests to `/ftp/` with null byte encoded filenames, download of `.kdbx` file.

**Remediation:**
1. Disable directory listing (`Options -Indexes` or equivalent in Express)
2. Move all sensitive files (`.kdbx`, `.bak`, confidential docs) outside the web root entirely
3. Normalize and canonicalize file paths before extension checks — reject null bytes in file path inputs
4. Require authentication for all file download endpoints
5. Remove backup files from production/lab environments; use version control instead

---

### FINDING 4 — Stored Cross-Site Scripting via Product Review API
**Alert:** ALT-004
**Severity:** HIGH | CVSS 8.2
**OWASP:** A03:2021 Injection (XSS) | CWE-79

The `PUT /rest/products/{id}/reviews` endpoint stores the `message` field directly in MongoDB without sanitization. The payload `<iframe src="javascript:alert('xss')">` was persisted and confirmed present in subsequent GET requests. The application's CORS wildcard (`*`) policy significantly amplifies cross-origin exploitation impact.

**Attacker impact:** Persistent payload fires in every user's browser visiting Product 1. Can be upgraded to session cookie theft, admin session hijacking via cookie exfiltration, or keylogging. CORS wildcard means malicious cross-origin JavaScript can make authenticated API calls on behalf of the victim.

**Detection opportunity:** HTML tags or JavaScript URIs in review message fields. Inconsistency between `sanitize-html` being applied on the feedback endpoint but not reviews.

**Remediation:**
1. Apply consistent HTML output encoding on all user-generated content at render time
2. Implement Content Security Policy: `default-src 'self'; script-src 'self'; object-src 'none'` — blocks `javascript:` URI execution
3. Upgrade `sanitize-html` from 1.4.2 to current (CVE-2016-1000171 resolved in later versions)
4. Apply the same sanitization library to the review API as used on the feedback endpoint
5. Replace the CORS wildcard (`*`) with explicit allowed origin allowlisting

---

### FINDING 5 — Broken Access Control: IDOR on User Baskets
**Alert:** ALT-006
**Severity:** HIGH | CVSS 7.5
**OWASP:** A01:2021 Broken Access Control | CWE-639

The `/rest/basket/{id}` endpoint does not enforce basket ownership. Any authenticated user (including via the forged admin token from Exploit 01) can access, view, and modify any other user's basket by incrementing the integer ID.

**Attacker impact:** Full read/write access to all user shopping carts. Order manipulation, unauthorized purchase modifications, user behavior surveillance.

**Detection opportunity:** Authenticated requests to basket IDs other than the user's own (determinable by comparing bid in JWT to requested ID). Rapid sequential ID enumeration pattern.

**Remediation:**
1. Enforce object-level authorization — validate that the authenticated user's `bid` (from JWT) matches the requested basket ID
2. This check must apply even to admin-role tokens unless explicit admin basket management is an intended feature

---

### FINDING 6 — Security Misconfiguration: Unauthenticated Admin Configuration Endpoint
**Alert:** ALT-008
**Severity:** HIGH | CVSS 7.8
**OWASP:** A01:2021 Broken Access Control / A05:2021 Security Misconfiguration

`GET /rest/admin/application-configuration` returns the full application configuration — including server basePath, cookie settings, security.txt paths, chatbot config, and social links — without any authentication token required.

**Attacker impact:** Internal configuration details used to refine attack planning. `localBackupEnabled: true` indicates backup files are being generated, providing another potential data exfiltration target.

**Remediation:**
1. Require admin-role JWT on all `/rest/admin/*` endpoints
2. Apply middleware authentication check at the router level, not per-handler
3. Audit all admin API routes for missing authentication guards

---

### FINDING 7 — Security Misconfiguration: Unauthenticated Prometheus Metrics
**Alert:** ALT-007
**Severity:** MEDIUM | CVSS 5.3
**OWASP:** A05:2021 Security Misconfiguration

The `/metrics` endpoint exposes Prometheus-format operational metrics without authentication, including CPU time, process uptime, file upload counts/errors, and startup task durations.

**Attacker impact:** Operational intelligence gathered passively. An attacker can monitor application load to time exploitation attempts during low-traffic periods, or confirm success of denial-of-service conditions without direct interaction.

**Remediation:**
1. Bind metrics endpoint to localhost or an internal-only network interface
2. If external access is required, require authentication (bearer token or basic auth)
3. Consider a separate internal-only metrics port isolated from the public application port

---

## Evidence Inventory

| Artifact | Path | Description |
|---|---|---|
| Exploit 01 | exploit/exploit_01_sqli_login_bypass.md | SQLi login bypass — full reproduction steps + JWT |
| Exploit 02 | exploit/exploit_02_sensitive_data_ftp.md | FTP open dir + null byte bypass — file inventory |
| Exploit 03 | exploit/exploit_03_persisted_xss_reviews.md | Stored XSS — payload and verification |
| Exploit 04 | exploit/exploit_04_sqli_credential_dump.md | UNION SQLi — 22 credential dump table |
| Credential Loot | loot/credentials.md | 22 MD5 hashes, cracked admin password, coupon codes |
| Post-Exploitation | postex/postex_findings.md | IDOR, config dump, metrics, attack chain diagram |
| Mission Notes | notes/notes.md | Analyst notes including null byte bypass and XSS variant |
| Mission Report | report/mission_report.md | Full red team findings report |
| Timeline | timeline.log | Phase-by-phase event log with timestamps |
| Recon: Fingerprint | recon/application_fingerprint.md | Tech stack, headers, version info |
| Recon: Surface Map | recon/attack_surface_map.md | Endpoint inventory |
| Recon: Host Discovery | recon/host_discovery.md | Network-level host data |
| Mission State | mission_state.json | Phase completion status, confirmed exploit count |
| Mission Plan | mission_plan.json | Original scope, objectives, exploit candidates |

---

## Attack Chain Reconstruction

```
STAGE 1 — INITIAL ACCESS (Unauthenticated)
  Recon: robots.txt discloses /ftp/ → open dir listing → incident-support.kdbx downloaded
  Recon: /encryptionkeys/ open → jwt.pub RSA key retrieved
  Recon: /rest/admin/application-configuration accessible without auth

STAGE 2 — CREDENTIAL ACCESS
  SQLi → POST /rest/user/login with ' OR 1=1-- → admin JWT obtained
  JWT decoded → admin MD5 hash leaked → cracked to admin123
  SQLi UNION → /rest/products/search?q= → 22 credential records exfiltrated

STAGE 3 — PERSISTENCE
  Stored XSS → PUT /rest/products/1/reviews → <iframe javascript:> payload persisted
  Payload fires for all users viewing Product 1

STAGE 4 — POST-EXPLOITATION
  Admin JWT used to enumerate all 22 users (/api/Users)
  IDOR confirmed on all user baskets (/rest/basket/1-5)
  Full application config dumped (/rest/admin/application-configuration)
  Metrics gathered (/metrics) — unauthenticated
  KeePass DB offline cracking initiated (rockyou budget exhausted)

TOTAL TIME TO ADMIN COMPROMISE: ~39 minutes from mission start
```

---

## Risk Assessment

| Category | Status | Detail |
|---|---|---|
| Authentication | COMPROMISED | Admin bypass via SQLi; all accounts accessible |
| Confidentiality | BREACHED | 22 credentials + admin plaintext + KeePass DB exfiltrated |
| Integrity | COMPROMISED | Persistent XSS payload active in product reviews |
| Availability | INTACT | No DoS attempted (out of scope) |
| Authorization | FAILED | IDOR on baskets; admin endpoints unauthenticated |
| Cryptography | FAILED | Unsalted MD5 for passwords; sensitive data in JWT |

---

## Remediation Priority Matrix

| Priority | Finding | Action |
|---|---|---|
| P1 — CRITICAL | SQLi in login and search | Parameterize all SQL queries immediately |
| P1 — CRITICAL | Unsalted MD5 passwords | Migrate to bcrypt/Argon2; force password reset |
| P2 — HIGH | Open /ftp/ directory | Remove from web root; disable directory listing |
| P2 — HIGH | Stored XSS in reviews | Apply output encoding + CSP + sanitize-html upgrade |
| P2 — HIGH | Admin config unauthenticated | Require admin JWT on all /rest/admin/* routes |
| P2 — HIGH | IDOR on baskets | Enforce ownership check in basket handler |
| P2 — HIGH | Sensitive data in JWT | Strip password hash and secrets from JWT payload |
| P3 — MEDIUM | Unauthenticated /metrics | Restrict to internal network or authenticated access |
| P3 — MEDIUM | CORS wildcard | Replace * with explicit origin allowlist |
| P4 — LOW | X-Recruiting header | Remove information-leaking HTTP headers |

---

## Unexecuted Attack Surface (Residual Risk)

The following vectors were identified but not executed in this mission (max_exploits reached). They represent confirmed residual attack surface for mission 2026-03-12-002:

- JWT algorithm confusion (RS256 → HS256 downgrade) using the exposed `jwt.pub` key
- IDOR write operations on user baskets (cart manipulation)
- GraphQL introspection and data extraction at `/graphql`
- Mass assignment — account registration with admin role injection
- `/rest/user/authentication-details` — admin-only endpoint, unverified

---

## Blue Team Observations

1. **No defensive controls observed** — No WAF, no rate limiting, no login attempt monitoring, no anomaly detection on SQL error rates. The full attack chain completed without any friction.
2. **Error verbosity aids attacker** — HTTP 500 on SQL syntax error (`'))`) directly confirms injection point. Errors should return generic messages in production.
3. **JWT algorithm exposure** — RS256 public key at `/encryptionkeys/` is not protected. This creates a ready-made HS256 confusion attack surface for the next mission.
4. **Dependency management gap** — `sanitize-html 1.4.2` was discoverable via `/ftp/package.json.bak`. Backup files must not be web-accessible.
5. **Monitoring gap on recon** — The attack began with passive file retrieval (`/ftp/`, `/metrics`, `/rest/admin/application-configuration`) before any exploitation. All of this was undetected. Logging and alerting on access to sensitive paths should be a baseline control.

---

*Incident ID: INC-2026-03-12-001*
*Controller: blueteam-master*
*Pipeline: monitoring → analysis → collection → reporting*
*Report generated: 2026-03-13T15:39:30Z*
*Classification: LAB / TRAINING USE ONLY*
