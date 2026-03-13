# Post-Exploitation Findings
## Mission: 2026-03-12-001
## Phase: Post-Exploitation

---

## Overview
With admin access established via SQL injection (Exploit 01), post-exploitation activities confirmed the full blast radius of the authentication bypass. All privileged API endpoints were accessible, IDOR vulnerabilities confirmed across multiple resources, and operational intelligence was gathered from the metrics and configuration endpoints.

---

## Admin Capabilities Confirmed

### 1. Full User Database Access
- **Endpoint**: GET /api/Users (admin token required)
- **Result**: All 22 user accounts enumerated including emails, roles, and password hashes
- **Roles present**: admin (8), customer (9), deluxe (4), accounting (1)

### 2. Application Configuration Exposed
- **Endpoint**: GET /rest/admin/application-configuration
- **Result**: Full server config returned — port, basePath, domain, chatbot config, socialLinks, cookie config, security.txt paths
- **Key Finding**: Server baseUrl is `http://localhost:3000` (confirms Node.js running locally)
- **localBackupEnabled**: true (local database backups are being created)

### 3. Application Version Confirmed
- **Endpoint**: GET /rest/admin/application-version
- **Version**: 19.2.0-SNAPSHOT (development/snapshot build — not a stable release)

### 4. IDOR — All User Baskets Accessible
- **Endpoint**: GET /rest/basket/{id}
- **Result**: Baskets 1-5 all return HTTP 200 with admin token
- **Impact**: An attacker can view, modify, or empty any user's shopping basket

### 5. Prometheus Metrics Exposed (No Auth)
- **Endpoint**: GET /metrics (unauthenticated)
- **Data exposed**: CPU time, file upload counts/errors, startup task durations, process start time
- **Impact**: Operational intelligence — reveals uptime, load, feature usage patterns

### 6. FTP Loot Summary
- `incident-support.kdbx` — KeePass 2.x database downloaded (3246 bytes). Offline cracking pending.
- `coupons_2013.md.bak` — 12 coupon codes exfiltrated via null byte bypass
- `package.json.bak` — Full dependency list confirming `sanitize-html 1.4.2` (known vulnerable)

---

## Attack Chain Summary

```
1. Reconnaissance
   → Port 3000 HTTP (Node.js/Express)
   → /ftp/ directory listing open
   → /encryptionkeys/ JWT public key exposed

2. Scan
   → /support/logs directory open (access.log, audit.json)
   → CORS wildcard (*) on all HTTP methods

3. Enumeration
   → 111 challenges identified
   → 21 users enumerated
   → Admin password hash leaked in JWT

4. Exploitation
   → SQLi login bypass → Admin JWT obtained
   → FTP null byte bypass → KeePass DB + coupon codes
   → Persisted XSS → iframe payload in product reviews
   → SQLi UNION dump → 22 credential records

5. Post-Exploitation
   → Admin API access confirmed
   → IDOR across all user baskets
   → Full application config dumped
   → Metrics endpoint intelligence gathered
```

---

## Persistence / Impact Assessment

| Impact Category | Detail |
|-----------------|--------|
| Confidentiality | 22 user credential hashes exfiltrated; admin plaintext recovered; KeePass DB downloaded |
| Integrity | XSS payload persisted in product reviews; fake feedback postable |
| Availability | No DoS attempted (out of scope) |
| Authentication | Admin account fully compromised; login bypass available for all accounts |
| Authorization | IDOR on baskets; admin panel accessible; all user data readable |

---

## Remaining Attack Vectors (Not Executed — Max Exploits Reached)
- JWT algorithm confusion (RS256 → HS256 downgrade) using exposed jwt.pub
- Account registration with admin role via mass assignment
- Password reset attacks using security questions (social engineering — out of scope)
- XXE data access via file upload endpoint
- GraphQL introspection and data exfiltration
