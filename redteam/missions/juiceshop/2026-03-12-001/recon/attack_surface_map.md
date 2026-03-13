# Attack Surface Map — Recon Phase
## Mission: 2026-03-12-001

## Challenge Categories (from /api/Challenges)
Total attack categories identified from application challenge map:

### High Priority Attack Vectors
| Category | Count | Priority Targets |
|----------|-------|-----------------|
| Injection (SQLi/NoSQL/SSTI) | 10 | Login Admin, DB Schema, User Creds |
| XSS | 7 | DOM XSS, Reflected XSS, API-only XSS |
| Broken Access Control | 11 | Admin Section, View Basket, Forged Feedback |
| Sensitive Data Exposure | 12 | Password Hash Leak, Exposed Creds, Dev Backup |
| Broken Authentication | 9 | Password Strength, Reset flows |
| Vulnerable Components | 7 | Unsigned JWT, Legacy Typosquatting |

### Immediate Low-Hanging Fruit (Difficulty 1-2)
- Score Board (hidden route discovery)
- DOM XSS (owasp-juice-shop pattern: iframe src injection)
- Login Admin (SQLi bypass)
- Confidential Document (/ftp/acquisitions.md — ALREADY ACCESSED)
- Error Handling (trigger 500 error)
- Zero Stars (submit 0-star feedback)
- Exposed Metrics (/metrics — ALREADY CONFIRMED)
- Password Hash Leak (/rest/user/whoami after login)
- Reflected XSS (search parameter)
- Password Strength (admin weak password)
- Admin Section (/#/administration route)
- Deprecated Interface (B2B endpoint)

### Key User Targets (for credential attacks)
- admin@juice-sh.op (administrator)
- jim@juice-sh.op (Jim — security questions)
- bender@juice-sh.op (Bender — security questions)
- bjoern@juice-sh.op (Bjoern — developer account)
- mc.safesearch@juice-sh.op (MC SafeSearch — social OSINT)

### Attack Entry Points
1. /rest/user/login — Authentication endpoint (SQLi target)
2. /rest/products/search — Product search (SQLi target, q parameter)
3. /api/Feedbacks — POST feedback (XSS injection point)
4. /ftp/ — File download (null byte bypass for .bak files)
5. /rest/user/change-password — Password change (missing old password validation)
6. /api/Users/ — User registration (admin role registration)
7. /#/score-board — Hidden route
8. /#/administration — Admin panel (IDOR target)
