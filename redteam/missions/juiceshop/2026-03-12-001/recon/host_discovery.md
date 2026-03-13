# Host Discovery — Recon Phase
## Mission: 2026-03-12-001
## Target: 10.10.30.130

## ICMP Ping Results
- Host is UP (3 packets sent, 3 received, 0% loss)
- RTT avg: 2.137ms
- TTL: 63 (Linux host, likely 1 hop behind a router/NAT)

## TCP Port 3000
- Status: OPEN
- Protocol: HTTP/1.1
- Application: OWASP Juice Shop v19.2.0-SNAPSHOT
- Server: Node.js (Express framework)
- Framework: Angular frontend

## HTTP Headers (Port 3000)
- Access-Control-Allow-Origin: * (CORS misconfiguration)
- X-Content-Type-Options: nosniff
- X-Frame-Options: SAMEORIGIN
- Feature-Policy: payment 'self'
- X-Recruiting: /#/jobs (non-standard header, hints at job listings page)
- Content-Type: text/html; charset=UTF-8
- No X-Powered-By header (hidden)
- No Server header (hidden)

## Technology Stack
- Backend: Node.js + Express
- Frontend: Angular (SPA)
- Database: SQLite (inferred from Juice Shop defaults)
- Architecture: REST API + Angular SPA
