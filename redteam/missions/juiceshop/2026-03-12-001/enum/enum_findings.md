# Enumeration Findings
## Mission: 2026-03-12-001
## Target: http://10.10.30.130:3000
## Phase: Enumeration

---

## Summary

Deep enumeration of the OWASP Juice Shop application confirmed 111 challenge categories, 21 user accounts, and multiple high-priority exploitation vectors. SQL injection on the login endpoint was validated during enumeration, yielding a valid admin JWT token. Admin password hash was cracked revealing plaintext credentials.

---

## Challenge Map (111 Total)

| Category | Count | Solved |
|----------|-------|--------|
| Broken Access Control | 11 | 0 |
| Broken Anti Automation | 4 | 0 |
| Broken Authentication | 9 | 0 |
| Cryptographic Issues | 5 | 0 |
| Improper Input Validation | 12 | 0 |
| Injection | 11 | 3 |
| Insecure Deserialization | 3 | 0 |
| Miscellaneous | 7 | 1 |
| Observability Failures | 4 | 2 |
| Security Misconfiguration | 4 | 1 |
| Security through Obscurity | 3 | 0 |
| Sensitive Data Exposure | 16 | 1 |
| Unvalidated Redirects | 2 | 0 |
| Vulnerable Components | 9 | 0 |
| XSS | 9 | 0 |
| XXE | 2 | 0 |

---

## User Account Enumeration (21 Users)

All users enumerated via `/api/Users` with admin JWT token.

| ID | Email | Role |
|----|-------|------|
| 1 | admin@juice-sh.op | admin |
| 2 | jim@juice-sh.op | customer |
| 3 | bender@juice-sh.op | customer |
| 4 | bjoern.kimminich@gmail.com | admin |
| 5 | ciso@juice-sh.op | deluxe |
| 6 | support@juice-sh.op | admin |
| 7 | morty@juice-sh.op | customer |
| 8 | mc.safesearch@juice-sh.op | customer |
| 9 | J12934@juice-sh.op | admin |
| 10 | wurstbrot@juice-sh.op | admin |
| 11 | amy@juice-sh.op | customer |
| 12 | bjoern@juice-sh.op | admin |
| 13 | bjoern@owasp.org | deluxe |
| 15 | accountant@juice-sh.op | accounting |
| 16 | uvogin@juice-sh.op | customer |
| 17 | demo | customer |
| 18 | john@juice-sh.op | customer |
| 19 | emma@juice-sh.op | customer |
| 20 | stan@juice-sh.op | deluxe |
| 21 | ethereum@juice-sh.op | deluxe |
| 22 | testing@juice-sh.op | admin |

---

## Validated Exploitation Vectors

### 1. SQL Injection — Login Bypass (CONFIRMED)
- **Endpoint**: POST /rest/user/login
- **Payload**: `{"email":"' OR 1=1--","password":"x"}`
- **Result**: Valid admin JWT token returned
- **Impact**: Full admin authentication bypass, admin password hash leaked in JWT

### 2. Admin Password Hash Cracked
- **Hash**: `0192023a7bbd73250516f069df18b500` (MD5)
- **Plaintext**: `admin123`
- **Account**: admin@juice-sh.op

### 3. FTP Null Byte Bypass (CONFIRMED)
- **Endpoint**: GET /ftp/package.json.bak%2500.md
- **Result**: HTTP 200, file contents returned
- **Blocked directly**: GET /ftp/coupons_2013.md.bak returns HTTP 403
- **Impact**: Restricted .bak files downloadable via null byte URL encoding

### 4. Exposed Encryption Keys
- **Location**: /encryptionkeys/jwt.pub (RSA public key)
- **Location**: /encryptionkeys/premium.key = `1337133713371337.EA99A61D92D2955B1E9285B55BF2AD42`
- **Impact**: Enables JWT algorithm confusion (RS256 → HS256 downgrade)

### 5. XSS Attack Surface
- **Feedback endpoint**: POST /api/Feedbacks accepts unescaped HTML in comment field
- **Persisted XSS payload**: `<iframe src="javascript:alert('xss')">`
- **DOM XSS**: Product search /#/search?q= parameter passes user input to innerHTML

### 6. B2B API (JWT Required)
- **Endpoint**: /b2b/v2 — Returns 401 without valid JWT
- **Attack path**: Forge JWT using exposed RSA public key via algorithm confusion

---

## FTP Directory Contents
- acquisitions.md — CONFIDENTIAL M&A document
- announcement_encrypted.md — Encrypted announcement
- coupons_2013.md.bak — Backup file (403 direct, 200 via null byte)
- eastere.gg — Easter egg file
- encrypt.pyc — Python compiled encryption utility
- incident-support.kdbx — KeePass database (potential credential store)
- legal.md — Legal document
- package-lock.json.bak — Dependency lockfile backup
- package.json.bak — Package manifest backup (retrieved via null byte)
- suspicious_errors.yml — Error log YAML

---

## Security Questions (For Password Reset Attacks)
1. Your eldest siblings middle name?
2. Mother's maiden name?
3. Mother's birth date? (MM/DD/YY)
4. Father's birth date? (MM/DD/YY)
5. Maternal grandmother's first name?
6. Paternal grandmother's first name?
7. Name of your favorite pet?
8. Last name of dentist when you were a teenager?
9. Your ZIP/postal code when you were a teenager?
10. Company you first work for as an adult?
11. Your favorite book?
12. Your favorite movie?
13. Number of one of your customer or ID cards?
14. What's your favorite place to go hiking?

---

## Priority Exploitation Targets

1. **SQLi Login Admin** — Fully confirmed, ready for exploit phase documentation
2. **Persisted XSS via Feedback** — Payload identified, needs CAPTCHA bypass or direct API call
3. **JWT Forging via Algorithm Confusion** — RSA key available, RS256→HS256 downgrade viable
4. **Sensitive Data Exposure (FTP loot)** — incident-support.kdbx download + crack offline
