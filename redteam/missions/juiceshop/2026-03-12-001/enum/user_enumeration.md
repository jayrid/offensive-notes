# User Enumeration Report
## Mission: 2026-03-12-001

## Source
Endpoint: GET /api/Users (authenticated with admin JWT obtained via SQLi)

## Accounts (21)

| ID | Email | Role | Notes |
|----|-------|------|-------|
| 1 | admin@juice-sh.op | admin | Password: admin123 (MD5: 0192023a7bbd73250516f069df18b500) |
| 2 | jim@juice-sh.op | customer | Security question target |
| 3 | bender@juice-sh.op | customer | Security question target |
| 4 | bjoern.kimminich@gmail.com | admin | Developer account |
| 5 | ciso@juice-sh.op | deluxe | CISO account |
| 6 | support@juice-sh.op | admin | Support team (check KeePass) |
| 7 | morty@juice-sh.op | customer | Morty — CAPTCHA bypass challenge |
| 8 | mc.safesearch@juice-sh.op | customer | Social OSINT challenge |
| 9 | J12934@juice-sh.op | admin | Unknown admin |
| 10 | wurstbrot@juice-sh.op | admin | Unknown admin |
| 11 | amy@juice-sh.op | customer | Login Amy challenge |
| 12 | bjoern@juice-sh.op | admin | Dev alias |
| 13 | bjoern@owasp.org | deluxe | OWASP developer |
| 15 | accountant@juice-sh.op | accounting | Accounting role — IDOR target |
| 16 | uvogin@juice-sh.op | customer | Uvogin — password reset challenge |
| 17 | demo | customer | Demo account (no email format) |
| 18 | john@juice-sh.op | customer | |
| 19 | emma@juice-sh.op | customer | |
| 20 | stan@juice-sh.op | deluxe | |
| 21 | ethereum@juice-sh.op | deluxe | Blockchain challenge |
| 22 | testing@juice-sh.op | admin | Test admin account |

## Key Credential Finding

Admin hash cracked via local MD5 dictionary:
- Email: admin@juice-sh.op
- Hash: 0192023a7bbd73250516f069df18b500
- Password: **admin123**
- Method: MD5 (no salt) — trivially crackable

## Roles Present
- admin: 8 accounts (IDs 1, 4, 6, 9, 10, 12, 22)
- customer: 9 accounts
- deluxe: 4 accounts
- accounting: 1 account (ID 15)
