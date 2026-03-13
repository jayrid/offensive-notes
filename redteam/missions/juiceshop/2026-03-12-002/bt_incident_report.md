# BLUE TEAM INCIDENT REPORT
## Incident ID: BT-2026-03-12-002
## Target: OWASP Juice Shop — http://10.10.30.130:3000
## Classification: LAB / TRAINING USE ONLY
## Report Date: 2026-03-13
## Prepared by: Blue Team Operations Controller (blueteam-master)

---

## 1. INCIDENT OVERVIEW

| Field | Value |
|---|---|
| Incident ID | BT-2026-03-12-002 |
| Mission Reference | 2026-03-12-002 |
| Target Host | 10.10.30.130 |
| Target Port | 3000 |
| Application | OWASP Juice Shop v19.2.0-SNAPSHOT |
| Detection Mode | Artifact analysis (no live IDS — lab environment) |
| Overall Risk Rating | CRITICAL |
| Incident Window | 2026-03-13T00:22:40Z — 2026-03-13T00:36:27Z |
| Total Duration | ~14 minutes from first access to full admin compromise |
| Confirmed Exploits | 5 of 5 |
| Findings | 7 (3 Critical, 4 High) |

**Summary:** A full-scope red team exercise against the Juice Shop web application resulted in complete application compromise within 14 minutes. The attacker achieved admin-level access via two independent paths — SQL injection login bypass and JWT algorithm confusion token forgery — while also exfiltrating all 22 user credential hashes, a KeePass credential database, confidential M&A documents, and the full application configuration. No credentials or prior access were required for the most severe exploit (JWT algorithm confusion). The forged admin token is effectively non-expiring.

---

## 2. ATTACK TIMELINE (RECONSTRUCTED)

| Time (UTC) | Stage | Attacker Action | Blue Team Significance |
|---|---|---|---|
| 00:22:40 | Recon | Initial host probe; identified open port 3000 | Attack initiated — no authentication attempt |
| 00:24:43 | Recon | Mapped 3 open directories (/ftp/, /encryptionkeys/, /support/logs); retrieved JWT RSA public key; downloaded KeePass DB from /ftp/ | Critical key material and credential store exfiltrated with zero authentication |
| 00:26:58 | Scan | Confirmed unauthenticated /rest/admin/application-configuration; SQLi surface identified on /rest/products/search | Admin config leaked in full; OAuth client IDs and security Q&A answers exposed |
| 00:30:02 | Enumeration | Retrieved jwt.pub; UNION SQLi dump — 20 user email/hash pairs; null-byte bypass on FTP .bak files | All user credentials exfiltrated; JWT algorithm confusion attack fully prepared |
| 00:31:39 | Exploit | EXP-01: SQLi login bypass (POST /rest/user/login with OR 1=1--) — admin JWT obtained | First admin token obtained via SQL injection; MD5 hash in JWT payload |
| 00:32:43 | Exploit | EXP-02: FTP open directory — acquisitions.md, legal.md, incident-support.kdbx downloaded | Business-critical documents and credential vault exfiltrated |
| 00:33:18 | Exploit | EXP-03: UNION SELECT credential dump — 22 users, all MD5 hashes | Complete account database exfiltrated in single unauthenticated request |
| 00:33:58 | Exploit | EXP-04: Stored XSS via PUT /rest/products/1/reviews — iframe javascript payload persisted | Persistent XSS active; no CSP to block execution |
| 00:35:59 | Exploit | EXP-05: JWT algorithm confusion — HS256 forged admin token with RSA public key as HMAC secret | Non-expiring admin token forged without any credentials; full API access confirmed |
| 00:36:27 | Post-Exploitation | Mission goal satisfied; post-exploitation phase begun | Complete application compromise confirmed |

---

## 3. THREAT ANALYSIS

### 3.1 Attack Chain

The attacker executed a coherent multi-stage attack leveraging information disclosure as the foundation for all subsequent exploitation:

```
[Open Directories] ─> [RSA Public Key Exfiltration] ─> [JWT Algorithm Confusion] ─> [Admin API Access]
         |
         └─> [KeePass DB + M&A Documents] ─> [Credential Vault Compromise]

[SQLi Login Bypass] ─> [Admin JWT #1]
         |
         └─> [UNION Credential Dump] ─> [22 Accounts + MD5 Hashes]

[Stored XSS] ─> [Persistent Execution Surface in Product Reviews]
```

### 3.2 Root Cause Assessment

**Primary root cause:** The RSA public key used for JWT signing was exposed at `/encryptionkeys/jwt.pub` without authentication, and the JWT middleware failed to enforce algorithm type. These two defects in combination allow complete authentication bypass with no credentials required.

**Contributing factors:**
- All SQL queries in login and search endpoints use string concatenation rather than parameterized queries
- Directory listings enabled on `/ftp/`, `/encryptionkeys/`, and `/support/logs`
- No Content Security Policy header — removes the last browser-side defense against persisted XSS
- MD5 used for password hashing with no salting — entire credential database crackable via rainbow tables
- Admin API routes (`/rest/admin/*`) require no authentication

### 3.3 Detection Opportunities (Missed in Lab Environment)

Had a network IDS (Suricata/Snort) been in place, the following signatures would have fired:

| Event | Expected Signature |
|---|---|
| SQLi login bypass (OR 1=1--) | ET SQL Injection attack (POST body); Suricata rule sid:2006445 |
| UNION SELECT credential dump | ET SQL UNION keyword in URI; Suricata rule sid:2006546 |
| JWT HS256 with RSA key format | Custom rule: detect JWT alg:HS256 paired with PEM-formatted HMAC secret |
| FTP null-byte bypass (%2500) | Custom rule: URL-encoded null byte in path parameters |
| Unauthenticated /encryptionkeys/ access | Access control alert on static directory traversal |
| Prometheus /metrics unauthenticated access | Exposure of internal metrics endpoint |

**In a live environment with WAF/IDS:** The SQLi payloads would likely trigger immediate alerts. The JWT algorithm confusion attack is highly evasive — it generates syntactically valid HTTP traffic with a valid-looking JWT; detection requires semantic analysis of the JWT header's `alg` field.

---

## 4. FINDINGS DETAIL

### F-01 — SQL Injection: Login Authentication Bypass
**Severity:** CRITICAL | CVSS 9.8 | OWASP A03:2021 | CWE-89

- **Endpoint:** POST `/rest/user/login`
- **Payload:** `{"email":"' OR 1=1--","password":"x"}`
- **Impact:** Admin JWT obtained without valid credentials; MD5 hash of admin password exposed in token payload
- **Evidence:** `exploit/EXP-01_sqli_login_bypass.txt`

**Blue Team Assessment:** This is a textbook, trivially-detected SQL injection. Any WAF with default rules would block this payload. The presence of this vulnerability in a non-patched state represents a failure of both secure development practices and any existing security scanning pipeline.

---

### F-02 — Sensitive Data Exposure: Open FTP Directory + Null Byte Bypass
**Severity:** HIGH | CVSS 7.5 | OWASP A01/A02:2021 | CWE-22, CWE-200

- **Endpoint:** GET `/ftp/`
- **Files Exfiltrated:** `acquisitions.md` (M&A document), `incident-support.kdbx` (KeePass 2.x credential DB, 3.2KB), `coupons_2013.md.bak` (null-byte bypass via `%2500.md`)
- **Impact:** Business-critical documents and a credential vault downloaded without authentication
- **Evidence:** `exploit/EXP-02_ftp_sensitive_data.txt`

**Blue Team Assessment:** The KeePass database (`incident-support.kdbx`) should be treated as compromised and all contained credentials rotated immediately, even though it was not cracked during this exercise. If the master password is weak, offline cracking is trivial.

---

### F-03 — SQL Injection: UNION-Based Credential Dump
**Severity:** CRITICAL | CVSS 9.8 | OWASP A03:2021 | CWE-89

- **Endpoint:** GET `/rest/products/search?q=`
- **Payload:** `test')) UNION SELECT '1',email,password,'4','5','6','7','8','9' FROM Users--`
- **Records Exfiltrated:** 22 user accounts with email addresses and MD5 password hashes
- **Evidence:** `exploit/EXP-03_sqli_union_dump.txt`, `enum/user_dump.txt`

**Affected Accounts (sample):**
- `admin@juice-sh.op` — MD5 hash cracked: `admin123`
- `bjoern.kimminich@gmail.com`, `ciso@juice-sh.op`, `jim@juice-sh.op`, and 18 others

**Blue Team Assessment:** All 22 accounts must be treated as fully compromised. MD5 hashes without salting are recoverable in seconds via publicly available rainbow tables (e.g., CrackStation). Mandatory password resets required for all accounts.

---

### F-04 — Stored XSS: Product Review API
**Severity:** HIGH | CVSS 8.2 | OWASP A03:2021 | CWE-79

- **Endpoint:** PUT `/rest/products/1/reviews`
- **Payload:** `<iframe src="javascript:alert('xss')">`
- **Persistence:** Payload stored and returned unsanitized on GET requests; no CSP to block execution
- **Evidence:** `exploit/EXP-04_stored_xss.txt`

**Blue Team Assessment:** The CORS wildcard (`Access-Control-Allow-Origin: *`) combined with absent CSP means this XSS can exfiltrate JWT tokens cross-origin. Any authenticated user visiting product pages is at risk of session hijacking.

---

### F-05 — JWT Algorithm Confusion: RS256 to HS256 Token Forgery
**Severity:** CRITICAL | CVSS 9.1 | OWASP A02:2021 | CWE-327, CWE-345

- **Prerequisite:** RSA public key from `/encryptionkeys/jwt.pub` (no authentication required)
- **Attack:** Forge JWT with `alg: HS256`; sign with RSA public key bytes as HMAC secret
- **Forged Token:** Non-expiring (`iat: 9999999999`); admin role (`id: 1, email: admin@juice-sh.op`)
- **Verified Access:** `/api/Users` (HTTP 200, 22 users), `/rest/admin/application-configuration` (HTTP 200), `/rest/basket/1` (HTTP 200), `/rest/order-history` (HTTP 200)
- **Evidence:** `exploit/EXP-05_jwt_algorithm_confusion.txt`, `recon/encryptionkeys.txt`

**Blue Team Assessment:** This is the most severe finding. It is evasive (generates valid-looking traffic), requires zero credentials, produces a non-expiring token, and cannot be revoked without rotating the JWT signing keys. The forged token issued during this exercise (`eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...`) must be added to a blocklist immediately and signing keys rotated as the first remediation action.

---

### F-06 — Security Misconfiguration: Unauthenticated Admin Configuration Endpoint
**Severity:** HIGH | CVSS 7.5 | OWASP A05:2021

- **Endpoint:** GET `/rest/admin/application-configuration`
- **Leaked Data:** Google OAuth `clientId`, all redirect URIs, security Q&A answers (`Daniel Boone National Forest`, `ITsec`), chatbot training data paths, full product catalog with internal metadata
- **Evidence:** `scan/vulnerability_scan.txt`

---

### F-07 — Security Misconfiguration: Open Directories
**Severity:** HIGH | CVSS 7.5 | OWASP A05:2021

- **Directories:** `/encryptionkeys/` (jwt.pub, premium.key), `/support/logs` (access.log x3, audit.json), `/ftp/` (11 files including KeePass DB)
- **Impact:** Cryptographic key material, access logs, and audit trail exposed; enables chained attacks (F-05 depends on F-07)

---

## 5. EVIDENCE INVENTORY

| Artifact | Path | Type | Status |
|---|---|---|---|
| SQLi login bypass proof | `exploit/EXP-01_sqli_login_bypass.txt` | Exploit proof | Collected |
| FTP sensitive data proof | `exploit/EXP-02_ftp_sensitive_data.txt` | Exploit proof | Collected |
| UNION credential dump proof | `exploit/EXP-03_sqli_union_dump.txt` | Exploit proof | Collected |
| Stored XSS proof | `exploit/EXP-04_stored_xss.txt` | Exploit proof | Collected |
| JWT algorithm confusion proof | `exploit/EXP-05_jwt_algorithm_confusion.txt` | Exploit proof | Collected |
| RSA public key (jwt.pub) | `recon/encryptionkeys.txt` | Key material | Collected |
| 22 user email/hash pairs | `enum/user_dump.txt` | Credential dump | Collected |
| API surface map | `enum/api_surface.txt` | Enumeration | Collected |
| KeePass credential database | `loot/incident-support.kdbx` | Binary artifact | Downloaded — not cracked |
| Vulnerability scan results | `scan/vulnerability_scan.txt` | Scan output | Collected |
| Mission timeline | `timeline.log` | Audit log | Collected |
| Red team mission report | `report/mission_report.md` | Source report | Collected |

---

## 6. LOOT REQUIRING IMMEDIATE ACTION

| Item | Risk | Required Action |
|---|---|---|
| Forged HS256 admin JWT (non-expiring) | CRITICAL — active persistent admin access | Block token; rotate JWT signing keys immediately |
| Admin JWT from SQLi bypass | CRITICAL — valid session credential | Invalidate; rotate if token reuse is possible |
| incident-support.kdbx (KeePass DB) | HIGH — credential vault in attacker possession | Rotate ALL credentials stored in this vault immediately; treat all as compromised |
| 22 MD5 password hashes | CRITICAL — trivially crackable via rainbow tables | Force password reset for all 22 accounts immediately |
| RSA public key (jwt.pub) at public URL | CRITICAL — enables ongoing token forgery | Remove from web root; rotate signing key pair |
| acquisitions.md (M&A document) | HIGH — confidential business document exfiltrated | Document breach; assess data classification and notification obligations |
| Full app config (OAuth clientId, security Q&A) | HIGH — OAuth client and account recovery exposed | Rotate OAuth client secret; invalidate security Q&A answers for all users |

---

## 7. REMEDIATION ROADMAP

### Immediate (P0 — within 24 hours)

1. **Rotate JWT signing key pair.** Generate a new RS256 key pair. Deploy new public key. Invalidate all existing sessions. Remove `/encryptionkeys/` from the web root entirely.
2. **Block the forged HS256 token.** Add the forged token's `jti` or `iat: 9999999999` signature to a JWT blocklist.
3. **Enforce RS256-only algorithm.** Update JWT middleware to reject any token where `alg` is not `RS256`. Reject `alg: none`, `alg: HS256`, and all other variants.
4. **Force password reset for all 22 accounts.** Treat all as compromised. Migrate password storage to bcrypt (cost factor >= 12) or Argon2id.
5. **Rotate all credentials in incident-support.kdbx.** Treat the credential vault as fully compromised.

### Short-Term (P1 — within 1 week)

6. **Parameterize all SQL queries.** Apply to `/rest/user/login`, `/rest/products/search`, and all other database-interacting endpoints. Use Sequelize's parameterized query API.
7. **Disable directory listing.** Configure the Express static file server to disable directory index for `/ftp/`, `/encryptionkeys/`, `/support/logs`, and all other static paths.
8. **Move sensitive files outside the web root.** jwt.pub, premium.key, KeePass DB, .bak files, and log files must not be web-accessible.
9. **Require authentication on all `/rest/admin/*` routes.** Apply JWT middleware to every admin endpoint.
10. **Implement Content Security Policy.** At minimum: `default-src 'self'; script-src 'self'; object-src 'none'`. This eliminates the javascript: URI XSS vector.

### Medium-Term (P2 — within 1 month)

11. **Apply output encoding to all user-generated content.** Sanitize product reviews at API write time using a server-side sanitization library with a strict allowlist (not denylist).
12. **Replace CORS wildcard with explicit origin allowlist.** Remove `Access-Control-Allow-Origin: *`.
13. **Restrict `/metrics` endpoint.** Require authentication or restrict to internal network only.
14. **Remove X-Recruiting header** and all other information-disclosure headers.
15. **Audit all endpoints for authentication enforcement.** Use a systematic review; generate an authenticated vs. unauthenticated endpoint matrix.

---

## 8. OWASP TOP 10 COVERAGE SUMMARY

| Category | Findings | Severity |
|---|---|---|
| A01:2021 Broken Access Control | F-02 (FTP), F-06 (admin config), F-07 (open dirs) | High |
| A02:2021 Cryptographic Failures | F-05 (JWT confusion), F-03 (MD5 hashes), F-07 (exposed key) | Critical/High |
| A03:2021 Injection | F-01 (SQLi login), F-03 (SQLi UNION), F-04 (Stored XSS) | Critical/High |
| A04:2021 Insecure Design | F-07 (backup files in web root, open dirs) | High |
| A05:2021 Security Misconfiguration | F-06 (admin config), F-07 (open dirs), no CSP | High |

---

## 9. BLUE TEAM PIPELINE RECORD

| Stage | Agent | Status | Timestamp |
|---|---|---|---|
| Monitoring | blueteam-alert-monitor | Complete (artifact mode) | 2026-03-13T01:00:10Z |
| Threat Analysis | blueteam-threat-analyst | Complete | 2026-03-13T01:05:00Z |
| Evidence Collection | blueteam-evidence-collector | Complete | 2026-03-13T01:10:00Z |
| Reporting | blueteam-report-writer | Complete | 2026-03-13T01:15:00Z |

---

*Classification: LAB / TRAINING USE ONLY*
*Incident ID: BT-2026-03-12-002 | Mission Ref: 2026-03-12-002*
*Report generated by Blue Team Operations Controller (blueteam-master) — 2026-03-13*
