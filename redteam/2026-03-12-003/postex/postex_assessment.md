# Post-Exploitation Assessment — Mission 2026-03-12-003
Target: 10.10.30.130:3000
Date: 2026-03-12

## Impact Scope Assessment

### Affected Users
All 22+ registered users are affected. Any user with a valid account JWT can:
- Read any other user's basket contents
- Modify quantities of items in any other user's basket
- Read cross-user basket item dumps via /api/BasketItems

### Basket Data Exposed via IDOR
| Basket | User     | Products                              | Cart Value |
|--------|----------|---------------------------------------|------------|
| 1      | admin (1)| Apple Juice x2, Orange Juice x3, Eggfruit x1 | $21.94 |
| 2      | jim (2)  | Raspberry Juice x5 (modified by us)   | $24.95     |
| 3      | bender (3)| Raspberry Juice x1                   | $4.99      |
| 4      | amy (11) | Raspberry Juice x2                    | $9.98      |
| 5      | uvogin (16)| Eggfruit x5, Raspberry Juice x2     | $54.93     |
| 6      | testidor2 (23)| Empty                            | $0.00      |

### Attack Chain Demonstrated
1. Register any user account (POST /api/Users — no email verification)
2. Authenticate to obtain JWT (POST /rest/user/login)
3. Request any basket by sequential ID (GET /rest/basket/:id)
4. List all basket items across all users (GET /api/BasketItems)
5. Modify any item in any basket (PUT /api/BasketItems/:id)

### Additional IDOR Surfaces Identified (Post-Ex Discovery)
- GET /rest/track-order/:orderId — order tracking accessible (returned orderId:1 for any user)
- GET /api/Addresss — no saved addresses in test environment (empty) but endpoint exists
- GET /api/BasketItems (full dump) — all cart items for all users, no per-user filter

### Financial Impact Potential
- Quantity manipulation: attacker can inflate cart quantities for other users pre-checkout
  causing unintended charges
- Cart erasure: attacker could DELETE basket items via /api/BasketItems/:id (not tested
  to avoid destructive action, but DELETE method is permitted per OPTIONS response)
- Competitive intelligence: attacker learns what products all other users have selected

### Privilege Level Required
- Authentication: YES (any valid JWT)
- Privilege: NONE beyond basic customer account
- Account creation: OPEN (no invite, no email verification)
- Net access barrier: Near zero

### Persistence Assessment
The vulnerability is architectural — no session token or cookie-based component means
it persists across all application restarts. No remediation artifacts were left.

## Loot Summary
- Full basket contents for 6 active baskets (baskets 1-6)
- User-to-basket ID mapping: User 1=basket 1, User 2=basket 2, User 3=basket 3,
  User 11=basket 4, User 16=basket 5, User 23=basket 6, User 24=basket 7
- Confirmed Jim's basket item (id=4) modified: qty 2 -> 5 (write impact demonstrated)
