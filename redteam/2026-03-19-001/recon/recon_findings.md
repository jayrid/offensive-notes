# Recon Findings — bWAPP Mission 2026-03-19-001
**Date:** 2026-03-19
**Target:** 10.10.30.128
**Analyst:** redteam-master

---

## Target Fingerprint

| Property | Value |
|---|---|
| IP | 10.10.30.128 |
| Web Server | Apache/2.4.7 (Ubuntu) |
| PHP Version | 5.5.9-1ubuntu4.14 |
| OS | Ubuntu 14.04 LTS (Docker container) |
| Document Root | /var/www/html |
| App Version | bWAPP v2.2 |
| Login Endpoint | http://10.10.30.128/login.php |
| Portal | http://10.10.30.128/portal.php |

## PHP Configuration (Critical)

| Setting | Value | Security Implication |
|---|---|---|
| allow_url_fopen | On | HTTP/file wrappers usable |
| allow_url_include | Off | RFI blocked at PHP level |
| open_basedir | (no value) | No directory jail — full LFI traversal possible |

## Session / Cookie Analysis

- PHPSESSID set without HttpOnly flag (from prior mission)
- security_level cookie set via login form parameter — downgrade trivially possible
- Login with `security_level=0` grants low-security session

## Confirmed Credentials

| Username | Password | Role |
|---|---|---|
| bee | bug | Normal user |
| A.I.M. | bug | Admin (admin=1 in DB) |

## Challenge Endpoints Confirmed (HTTP 200)

| Bug ID | Challenge | Endpoint |
|---|---|---|
| 109 | Remote & Local File Inclusion (RFI/LFI) | /rlfi.php |
| 41 | Session Management - Administrative Portals | /smgmt_admin_portal.php |
| 31 | XML/XPath Injection (Login Form) | /xmli_1.php |
| 32 | XML/XPath Injection (Search) | /xmli_2.php |
| 105 | Directory Traversal - Files | /directory_traversal_1.php |

## SSRF Endpoint — Not Resolved via Naming

Bug 112 (SSRF) does not map to /ssrf-1.php or /ssrf-2.php (404). The portal self-redirects
to ssrf.php but that is just a portal page alias. SSRF endpoint name TBD — needs directory
enumeration in scan phase.

## XXE Endpoint — Not Found

Bug 113 (XXE) not at /xxe.php, /xxe_1.php, or /xxe_2.php. xmli_1.php is XML/XPath Injection
(not XXE). True XXE endpoint requires further discovery.

## robots.txt Disclosures

```
Disallow: /admin/
Disallow: /documents/
Disallow: /passwords/
```

## Key Attack Surfaces

1. **LFI via /rlfi.php** — `language` GET parameter accepts PHP filename, include() call. No open_basedir = full traversal possible.
2. **Session admin bypass via /smgmt_admin_portal.php** — `admin` query parameter controls access. Value=1 changes display but likely insufficient — need deeper analysis.
3. **XML injection /xmli_1.php** — login form with XML backend, XPath injection possible.
4. **SSRF endpoint TBD** — confirm in scan/enum phase.
5. **XXE endpoint TBD** — confirm in scan/enum phase.
