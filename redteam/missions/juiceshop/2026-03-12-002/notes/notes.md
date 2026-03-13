# Mission Notes — 2026-03-12-002
## Target: OWASP Juice Shop (10.10.30.130:3000)

---

## Key Observations

### Recon
- Same target as mission -001; application state reset between sessions
- Three open directories confirmed immediately: /ftp/, /encryptionkeys/, /support/logs
- No WAF detected — all payloads reach backend unfiltered
- Access logs (2026-03-11, -12, -13 dates) visible in /support/logs with audit.json

### Scan
- `/rest/admin/application-configuration` confirmed CRITICAL: returns geo-stalking security Q&A data
  - Security answer Q14 = "Daniel Boone National Forest"
  - Security answer Q10 = "ITsec"
- SQLi surface on `/rest/products/search?q=` confirmed from prior mission data
- No CSP header — XSS execution unrestricted

### Enum
- jwt.pub retrieved from /encryptionkeys/jwt.pub — RSA public key confirmed, HS256 confusion ready
- SQLi UNION dump: 22 users this run (vs 22 in -001; testidor2@juice-sh.op appeared in both)
- Security Q&A answers leaked via app config — account recovery attack vectors exist
- FTP null byte bypass re-confirmed (%2500.md)

### Exploitation
- EXP-01 (SQLi login): confirmed in 1 min 8 sec from phase start
- EXP-02 (FTP): acquisitions.md, legal.md, incident-support.kdbx downloaded without auth
- EXP-03 (SQLi UNION): 22 users + MD5 hashes in single unauthenticated GET request
- EXP-04 (Stored XSS): multiple payloads stored: iframe + script tag variants
- EXP-05 (JWT confusion): forged HS256 token with iat:9999999999 — effectively permanent admin token

### JWT Confusion Attack Notes
- Key insight: the JWT library accepts algorithm specified in token header (not server-enforced)
- Using the PUBLIC key as HMAC-SHA256 secret is the core trick
- The forged token (EXP-05) grants full admin access including /api/Users, /rest/basket/*, /rest/order-history
- Token has iat=9999999999 — far-future issued-at timestamp, not expiring
- This is a completely credential-free admin takeover vector

### Post-Exploitation Phase
- Phase started at 00:36:27 — timeline.log ends here (postex findings not yet logged to timeline)
- Postex findings are documented in postex/ directory (if present) or can be inferred from exploit results

---

## Attack Chain Summary
1. Recon → Open directories, RSA public key captured
2. EXP-01: SQLi OR tautology → admin JWT (conventional)
3. EXP-02: FTP open dir → KeePass DB + confidential docs
4. EXP-03: SQLi UNION → 22 credentials
5. EXP-04: Stored XSS on product reviews
6. EXP-05: JWT algorithm confusion → forged non-expiring admin token (credential-free)

---

## Differences vs Mission -001
- EXP-05 (JWT confusion) is new — not covered in prior mission
- Focus shifted from input validation to cryptographic/auth logic flaws
- Same injection vectors re-confirmed (SQLi, XSS) as foundational steps before JWT exploit

---

## Caveats / Limitations
- Timeline.log cuts off at postex phase start (00:36:27) — postex events not recorded
- mission_state.json status was `running` at time of audit — corrected to `completed`
- commands.log header-only — no commands appended during session
- report/ files were missing at time of audit — reconstructed from exploit artifacts and timeline
