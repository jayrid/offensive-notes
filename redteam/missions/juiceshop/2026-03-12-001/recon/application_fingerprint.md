# Application Fingerprinting — Recon Phase
## Mission: 2026-03-12-001

## Application Identity
- Name: OWASP Juice Shop
- Version: 19.2.0-SNAPSHOT
- Build Date: Sun, 15 Feb 2026
- Domain configured: juice-sh.op
- Privacy Contact: donotreply@owasp-juice.shop

## Exposed Endpoints (No Auth)
- /rest/admin/application-version — Version disclosure
- /rest/admin/application-configuration — Full config dump (CRITICAL)
- /rest/products/search — Product search (SQLi candidate)
- /api/Products — Product listing
- /api/Challenges — Challenge list (full attack surface map)
- /api/Feedbacks — User feedback with partial email disclosure
- /metrics — Prometheus metrics (exposed, no auth)
- /ftp/ — Directory listing enabled

## robots.txt
- Disallow: /ftp (but directory listing is active and accessible)

## FTP Directory Contents (/ftp/)
- acquisitions.md (CONFIDENTIAL — planned acquisitions)
- announcement_encrypted.md
- coupons_2013.md.bak
- eastere.gg
- encrypt.pyc
- incident-support.kdbx (KeePass database — high value)
- legal.md
- package.json.bak (BLOCKED — only .md and .pdf allowed, but accessible via null-byte bypass)
- package-lock.json.bak
- quarantine/ (subdirectory)
- suspicious_errors.yml

## Confidential Document: acquisitions.md
Content: "This document is confidential! Do not distribute!"
Contains: Planned acquisitions of competitors with stock market impact details

## API Security
- /api/Users — Requires Authorization header (JWT protected)
- /api/Products — Open (no auth)
- /api/Challenges — Open (no auth)
- /api/Feedbacks — Open, leaks partial email addresses (e.g., ***in@juice-sh.op)

## Google OAuth Configuration
- Client ID: 1005568560502-6hm16lef8oh46hr2d98vf2ohlnj4nfhq.apps.googleusercontent.com
- Authorized redirect URIs include demo.owasp-juice.shop

## Metrics Exposure
- /metrics endpoint exposes Prometheus metrics with no authentication
- Process CPU, memory, startup times, file upload stats visible
