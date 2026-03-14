# Mission Notes — 2026-03-12-003
## Target: OWASP Juice Shop (10.10.30.130:3000)
## Focus: IDOR Basket Access

---

## Key Observations

### Recon
- Admin auth established using known credentials (admin@juice-sh.op:admin123 from prior missions)
- 22 users enumerated via /api/Users with admin JWT
- Basket API structure confirmed: /rest/basket/:id returns full product list + UserId field
- IDOR vector identified immediately: no ownership check on basket endpoint

### Scan
- Single open port: 3000/tcp (HTTP only) — no SSH, FTP, SMB
- All HTTP methods allowed: GET, HEAD, PUT, PATCH, POST, DELETE
- CORS wildcard, no CSP, no HSTS — consistent with prior missions
- Attack surface exclusively web layer

### Enum
- Registered test account: idortest@pwn.lab / User ID 24 / Basket ID 7
- Customer JWT tested against baskets 1-7 — ALL returned HTTP 200 regardless of ownership
- Basket-to-user mapping:
  - Basket 1 → User 1 (admin@juice-sh.op)
  - Basket 2 → User 2 (jim@juice-sh.op)
  - Basket 3 → User 3 (bender@juice-sh.op)
  - Basket 4 → User 11 (amy@juice-sh.op)
  - Basket 5 → User 16 (uvogin@juice-sh.op)
  - Basket 6 → User 23 (testidor2@juice-sh.op)
- /api/BasketItems returns ALL users' basket items with ANY valid JWT — completely unfiltered

### Exploitation
- Three IDOR exploits confirmed (matching max_exploits: 3):
  1. Read admin basket (basket 1) with User 24 JWT → HTTP 200
  2. Write Jim's basket item (PUT /api/BasketItems/4, qty 2→5) → HTTP 200
  3. Read Bender's basket (basket 3) → HTTP 200
- All exploits use simple sequential integer ID enumeration
- Zero privilege escalation required — customer account only

### Post-Exploitation
- 6 baskets fully dumped (see loot/basket_dump.json)
- Financial exposure: cart totals from $4.99 to $54.93
- Jim's basket permanently modified (qty 2→5) during IDOR write demo
- /rest/track-order/:id also confirmed to leak cross-user order data (additional IDOR surface)
- /api/BasketItems full cross-user data leak logged

---

## Root Cause Analysis
- Express middleware validates JWT presence and RS256 signature
- Middleware does NOT compare token subject (user ID) to requested resource's UserId
- The fix requires one additional authorization check: `basket.UserId !== token.data.id`
- Same pattern likely applies to orders, addresses, payment methods, delivery routes

---

## Caveats / Limitations
- Jim's basket item modified during testing (qty 2→5) — noted in basket_dump.json
- No cleanup step performed (lab environment, disposable state)
- /api/BasketItems write exploit not formally counted as separate exploit (covered under IDOR Write)
