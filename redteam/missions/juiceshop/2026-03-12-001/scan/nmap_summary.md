# Nmap Scan Summary
## Mission: 2026-03-12-001

## Service Scan (port 3000)
- Port 3000/tcp: OPEN
- Service: HTTP (Node.js/Express — unrecognized by nmap)
- HTTP Response: 200 OK on GET
- HTTP Response: 204 No Content on OPTIONS
- HTTP Response: 400 Bad Request on malformed protocols

## Headers Confirmed
- Access-Control-Allow-Origin: *
- Access-Control-Allow-Methods: GET,HEAD,PUT,PATCH,POST,DELETE
- X-Frame-Options: SAMEORIGIN
- Feature-Policy: payment 'self'
- X-Recruiting: /#/jobs
- No X-Powered-By
- No Server header

## Wide Port Scan Status
- Port scan 1-10000 initiated against 10.10.30.130
- Primary attack surface confirmed on port 3000

## Access Log Analysis
Observed IPs from logs:
- 10.10.30.159 — Regular browser user (Safari macOS)
- 10.10.1.50 — Our attack host
Server path: /juice-shop/logs/ (Node.js app running from /juice-shop/)
