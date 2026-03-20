# Scan Findings — bWAPP Mission 2026-03-19-001
**Date:** 2026-03-19
**Target:** 10.10.30.128

---

## Nmap Full Port Scan Results

Open ports: **80/tcp (HTTP)**, **3306/tcp (MySQL)**
All other scanned ports closed.

```
PORT     STATE  SERVICE   VERSION
80/tcp   open   http      Apache httpd 2.4.7 ((Ubuntu))
3306/tcp open   mysql     MySQL (connection errors - not directly accessible)
```

PHPSESSID cookie confirmed **without HttpOnly flag** (nmap script finding).

## Complete Challenge Endpoint Map (from bugs.txt via LFI)

Obtained by reading `/var/www/html/bugs.txt` via php://filter LFI on rlfi.php.

### A2 - Broken Auth / Session Management
| Challenge | Endpoint |
|---|---|
| Session Management - Administrative Portals | /smgmt_admin_portal.php |
| Broken Authentication - CAPTCHA Bypassing | /ba_captcha_bypass.php |
| Broken Authentication - Forgotten Function | /ba_forgotten.php |
| Broken Authentication - Insecure Login Forms | /ba_insecure_login.php |

### A7 - Missing Functional Level Access Control
| Challenge | Endpoint |
|---|---|
| Directory Traversal - Files | /directory_traversal_1.php?page=message.txt |
| Directory Traversal - Directories | /directory_traversal_2.php?directory=documents |
| Remote & Local File Inclusion (RFI/LFI) | /rlfi.php |
| Server Side Request Forgery (SSRF) | /ssrf.php (info page only — exploit via rlfi.php) |
| XML External Entity Attacks (XXE) | /xxe-1.php (UI), /xxe-2.php (POST XML data receiver) |

## Key Discoveries

### LFI Confirmed Working
php://filter wrapper works on rlfi.php — used to read bugs.txt source.
Full filesystem accessible (no open_basedir restriction).

### SSRF Architecture Clarification
ssrf.php is an informational page only. bWAPP's SSRF is demonstrated via:
1. RFI path through rlfi.php using URL wrappers (blocked: allow_url_include=Off)
2. XXE-based SSRF via xxe-2.php

### XXE Endpoint Identified
- `xxe-1.php` — UI page with "Reset Secret" button
- `xxe-2.php` — POST endpoint receiving `Content-Type: text/xml`
- Payload format: `<reset><login>bee</login><secret>Any bugs?</secret></reset>`
- XMLHttpRequest call, no CSRF token observed

### Session Admin Portal
- `/smgmt_admin_portal.php` — redirects to `?admin=0` for bee user
- Query parameter `admin` controls access level check

## Attack Surface Summary

| Attack Vector | Endpoint | Method | Status |
|---|---|---|---|
| LFI | /rlfi.php?language=<path>&action=go | GET | CONFIRMED |
| XXE | /xxe-2.php | POST (text/xml) | CONFIRMED |
| Broken Auth (admin bypass) | /smgmt_admin_portal.php | GET/POST | CONFIRMED |
| SSRF via RFI | /rlfi.php?language=http://... | GET | BLOCKED (allow_url_include=Off) |
| SSRF via XXE | /xxe-2.php + SYSTEM entity | POST | TO TEST |
