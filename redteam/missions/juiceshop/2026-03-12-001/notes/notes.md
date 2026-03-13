# Mission Notes — 2026-03-12-001
## Target: OWASP Juice Shop (10.10.30.130:3000)

---

## Key Observations

### Recon
- Application is Juice Shop v19.2.0-SNAPSHOT on Node.js/Express, port 3000
- `robots.txt` discloses `/ftp` — confirmed accessible with full directory listing, no auth
- `/rest/admin/application-configuration` returns full config unauthenticated (CRITICAL)
- CORS wildcard (`*`) on all endpoints amplifies XSS impact significantly
- `X-Recruiting: /#/jobs` header leaks internal job board path
- 75+ challenges mapped from `/api/Challenges` endpoint

### Scan
- `/support/logs` open — access logs reveal app running from `/juice-shop/` on server
- `/encryptionkeys/` open — `jwt.pub` RSA public key + `premium.key` exposed
- Another user at 10.10.30.159 observed in access logs — noted as out-of-scope
- No WAF detected

### Enum
- 21 user accounts enumerated, 8 admins — via `/api/Users` with admin JWT
- Admin password hash `0192023a7bbd73250516f069df18b500` cracked locally: `admin123`
- FTP null byte bypass confirmed: `%2500` bypasses `.bak` extension filter
- `sanitize-html 1.4.2` in package.json.bak — known XSS bypass vulnerability

### Exploitation
- Mission resumed after break — enum phase restarted (see timeline gap 19:17-19:42)
- SQLi payload: `' OR 1=1--` in email field → admin JWT obtained first try
- XSS iframe payload stored on product ID 1 (Apple Juice) reviews
- UNION dump returned 22 rows — one more than prior enumeration (test account created during enum?)
- KeePass DB downloaded: `incident-support.kdbx` — 3246 bytes; rockyou exhausted in 15s

### Post-Exploitation
- IDOR on baskets confirmed: all 5 baskets (IDs 1-5+) accessible with admin token
- `localBackupEnabled: true` in app config — potential backup file attack surface
- Prometheus metrics unauthenticated: CPU, uptime, upload counts visible
- `sanitize-html 1.4.2` — CVE-2016-1000171 (XSS bypass via malformed HTML)

---

## Attack Chain Summary
1. Recon → FTP open dir → KeePass DB exfiltrated
2. SQLi login bypass → Admin JWT obtained
3. JWT decoded → admin hash `admin123`
4. SQLi UNION → 22 credentials dumped
5. XSS → iframe payload stored on Product 1 reviews
6. PostEx → IDOR on all baskets, metrics, config

---

## Caveats / Limitations
- KeePass DB not cracked (offline budget exceeded)
- Other user IP (10.10.30.159) in access logs — left untouched per scope rules
- JWT RSA public key noted — HS256 confusion attack NOT executed in this mission (in scope for mission -002)

---

## Follow-Up for Next Mission
- JWT algorithm confusion (RS256 → HS256) using exposed jwt.pub
- IDOR on basket write operations (modify other users' carts)
- Explore GraphQL introspection at /graphql
- /rest/user/authentication-details endpoint (admin-only)
