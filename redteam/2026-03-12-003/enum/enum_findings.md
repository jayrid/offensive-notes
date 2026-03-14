# Enumeration Findings — Mission 2026-03-12-003
Target: 10.10.30.130:3000
Date: 2026-03-12

## Test Account Created
- Email: idortest@pwn.lab
- Password: Test1234
- User ID: 24
- Role: customer
- Assigned Basket ID: 7

## IDOR Vulnerability Confirmed — /rest/basket/:id

### Test Methodology
Used JWT for User ID 24 (idortest@pwn.lab, customer role) to access baskets
belonging to different user accounts.

### Basket-to-User Mapping (via IDOR)
| Basket ID | Owner User ID | Access via Test JWT | HTTP Status | Items |
|-----------|--------------|---------------------|-------------|-------|
| 1         | 1 (admin)    | YES — UNAUTHORIZED  | 200 OK      | 3     |
| 2         | 2 (jim)      | YES — UNAUTHORIZED  | 200 OK      | 1     |
| 3         | 3 (bender)   | YES — UNAUTHORIZED  | 200 OK      | 1     |
| 4         | 11 (amy)     | YES — UNAUTHORIZED  | 200 OK      | 1     |
| 5         | 16 (uvogin)  | YES — UNAUTHORIZED  | 200 OK      | 2     |
| 6         | 23 (testidor2)| YES — UNAUTHORIZED | 200 OK      | 0     |
| 7         | 24 (idortest) | YES — authorized    | 200 OK      | 0     |

### Exposed Data from Other Users' Baskets (IDOR)
- Basket 1 (admin, UserId=1):
  - Apple Juice (1000ml) x2 @ $1.99
  - Orange Juice (1000ml) x3 @ $2.99
  - Eggfruit Juice (500ml) x1 @ $8.99

- Basket 2 (jim, UserId=2):
  - Raspberry Juice (1000ml) x2 @ $4.99

- Basket 3 (bender, UserId=3):
  - Raspberry Juice (1000ml) x1 @ $4.99

## Additional IDOR Surface — /api/BasketItems
- GET /api/BasketItems (customer JWT) returns ALL basket items across ALL users
- No per-user filtering applied
- Full item inventory visible: BasketId, ProductId, quantity for all users

## Root Cause Analysis
The application uses JWT authentication but does NOT validate that the
requesting user's ID matches the basket's UserId. Any valid JWT can access
any basket by simply changing the numeric ID in the URL.

No authorization check: the server only verifies that a JWT exists,
not that the JWT subject owns the requested resource.

## CVSS Score Estimate
CVSS v3.1: 6.5 (Medium)
- AV:N / AC:L / PR:L / UI:N / S:U / C:H / I:N / A:N
- Network exploitable, low complexity, low privilege required

## OWASP Classification
- A01:2021 — Broken Access Control (IDOR)
