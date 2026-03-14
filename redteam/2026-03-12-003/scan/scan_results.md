# Scan Results — Mission 2026-03-12-003
Target: 10.10.30.130
Date: 2026-03-12

## Port Scan Summary
Full TCP port scan (-p- --open --min-rate 5000):
- 3000/tcp OPEN — HTTP (Express/Node.js — OWASP Juice Shop)
- All other ports: CLOSED

## Attack Surface
Single exposed port: 3000/tcp
No SSH, FTP, SMB, or other network services exposed externally.
Entire attack surface is the web application at http://10.10.30.130:3000

## HTTP Methods Allowed (from CORS preflight)
GET, HEAD, PUT, PATCH, POST, DELETE (all methods allowed — no HTTP method restriction)

## Key Headers (Security Assessment)
| Header                  | Value              | Risk |
|-------------------------|--------------------|------|
| Access-Control-Allow-Origin | *             | HIGH — Any origin can make CORS requests |
| X-Frame-Options         | SAMEORIGIN         | Medium |
| X-Content-Type-Options  | nosniff            | OK |
| Content-Security-Policy | Not present        | HIGH — No CSP |
| Strict-Transport-Security | Not present      | HIGH — No HSTS (HTTP only) |

## Conclusion
Attack surface is exclusively web-based on port 3000. All exploitation must target the
web application layer. IDOR against /rest/basket/:id is the primary attack vector
consistent with allowed_attack_types: [idor, enumeration].
