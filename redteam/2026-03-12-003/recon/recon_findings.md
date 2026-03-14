# Recon Findings — Mission 2026-03-12-003
Target: 10.10.30.130:3000 (OWASP Juice Shop v19.2.0-SNAPSHOT)
Date: 2026-03-12

## Target Fingerprint
- Application: OWASP Juice Shop v19.2.0-SNAPSHOT
- Stack: Express ^4.22.1 (Node.js)
- Port: 3000/tcp (HTTP)
- Response time: ~21ms

## HTTP Headers Observed
- Access-Control-Allow-Origin: * (CORS open)
- X-Frame-Options: SAMEORIGIN
- X-Content-Type-Options: nosniff
- Feature-Policy: payment 'self'
- X-Recruiting: /#/jobs (hint to hiring page / potential SSRF target)
- No CSP header observed

## Unauthenticated Endpoints
- GET /metrics — Prometheus metrics (no auth required)
- GET /ftp/ — Open directory listing (no auth required)
- GET /rest/admin/application-version — Returns {"version":"19.2.0-SNAPSHOT"} (no auth)

## FTP Directory Contents (/ftp/)
- acquisitions.md
- announcement_encrypted.md
- coupons_2013.md.bak
- eastere.gg
- encrypt.pyc
- incident-support.kdbx (KeePass DB — downloadable directly)
- legal.md
- package-lock.json.bak
- package.json.bak
- suspicious_errors.yml
- /quarantine/ (subdirectory)

## Authentication
- POST /rest/user/login with known admin credentials succeeded
- Admin JWT obtained for user ID 1 (admin@juice-sh.op)
- JWT algorithm: RS256 (RSA)

## User Enumeration via /api/Users (admin JWT)
Total 22 users enumerated:
- ID:1  admin@juice-sh.op (admin)
- ID:2  jim@juice-sh.op (customer)
- ID:3  bender@juice-sh.op (customer)
- ID:4  bjoern.kimminich@gmail.com (admin)
- ID:5  ciso@juice-sh.op (deluxe)
- ID:6  support@juice-sh.op (admin)
- ID:7  morty@juice-sh.op (customer)
- ID:8  mc.safesearch@juice-sh.op (customer)
- ID:9  J12934@juice-sh.op (admin)
- ID:10 wurstbrot@juice-sh.op (admin)
- ID:11 amy@juice-sh.op (customer)
- ID:12 bjoern@juice-sh.op (admin)
- ID:13 bjoern@owasp.org (deluxe)
- ID:15 accountant@juice-sh.op (accounting)
- ID:16 uvogin@juice-sh.op (customer)
- ID:17 demo (customer)
- ID:18 john@juice-sh.op (customer)
- ID:19 emma@juice-sh.op (customer)
- ID:20 stan@juice-sh.op (deluxe)
- ID:21 ethereum@juice-sh.op (deluxe)
- ID:22 testing@juice-sh.op (admin)
- ID:23 testidor2@juice-sh.op (customer)

## Basket API Structure
- GET /rest/basket/:id — Returns basket with UserId, Products list, coupon field
- Basket 1 confirmed: UserId=1 (admin), contains Apple Juice and other items
- Authorization enforced by JWT presence but NO basket ownership validation (IDOR vector)

## IDOR Attack Surface
- Primary target: GET /rest/basket/:id
- Basket IDs appear to be sequential integers starting from 1
- JWT for user X can be used to request basket Y (ownership not enforced per prior testing)
- Mission-critical: demonstrate access to baskets belonging to other users using non-admin JWT

## Mission-Specific Notes
- Challenge goal: IDOR on /rest/basket/:id
- Need: Register a non-admin user, get their JWT, then request basket IDs belonging to other users
- Known working pattern from memory: any valid JWT provides access to any basket ID
