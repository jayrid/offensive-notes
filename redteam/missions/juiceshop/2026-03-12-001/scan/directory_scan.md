# Directory/Path Scan Results
## Mission: 2026-03-12-001

## Open Directories with Directory Listing Enabled
| Path | Status | Notes |
|------|--------|-------|
| /ftp/ | 200 | 11 files including incident-support.kdbx, package.json.bak |
| /support/logs | 200 | Access logs + audit.json EXPOSED |
| /encryptionkeys/ | 200 | jwt.pub + premium.key EXPOSED |
| /quarantine | 200 | Subdirectory of /ftp/ |

## Exposed Sensitive Files
| File | Content |
|------|---------|
| /encryptionkeys/jwt.pub | RSA public key for JWT verification |
| /encryptionkeys/premium.key | 1337133713371337.EA99A61D92D2955B1E9285B55BF2AD42 |
| /support/logs/access.log.2026-03-12 | Live access log with IP addresses, routes, UA strings |
| /support/logs/access.log.2026-03-11 | Previous day's access log |
| /support/logs/audit.json | Log audit file with MD5 hashes |

## JWT Public Key
```
-----BEGIN RSA PUBLIC KEY-----
MIGJAoGBAM3CosR73CBNcJsLv5E90NsFt6qN1uziQ484gbOoule8leXHFbyIzPQRozgEpSpiwhr6d2/c0CfZHEJ3m5tV0klxfjfM7oqjRMURnH/rmBjcETQ7qzIISZQ/iptJ3p7Gi78X5ZMhLNtDkUFU9WaGdiEb+SnC39wjErmJSfmGb7i1AgMBAAE=
-----END RSA PUBLIC KEY-----
```

## Premium Key
```
1337133713371337.EA99A61D92D2955B1E9285B55BF2AD42
```

## API Routes Discovered
| Path | Status | Notes |
|------|--------|-------|
| /api | 500 | Internal Server Error |
| /rest | 500 | Internal Server Error |
| /graphql | 200 | GraphQL endpoint (serves Angular app, not API) |
| /b2b/v2 | 401 | JWT Auth required |
| /api-docs | 301 | Redirect |

## HTTP Methods Allowed (from CORS preflight)
GET, HEAD, PUT, PATCH, POST, DELETE (full CRUD via Access-Control-Allow-Methods)

## Nmap Service Scan
- Port 3000/tcp OPEN — HTTP (Node.js/Express)
- CORS: Access-Control-Allow-Origin: *
- CORS Methods: GET,HEAD,PUT,PATCH,POST,DELETE
- No additional ports discovered in initial scan
