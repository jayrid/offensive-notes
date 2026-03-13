# Incident Report: BLUE-2026-03-12-003

**Target:** 10.10.30.130 — OWASP Juice Shop v19.2.0-SNAPSHOT
**Date:** 2026-03-12
**Severity:** CRITICAL
**Status:** Closed — Post-Incident Analysis
**Prepared by:** Blue Team Operations

---

## Executive Summary
The OWASP Juice Shop application was subjected to a targeted attack exploiting Insecure Direct Object Reference (IDOR) vulnerabilities on March 12, 2026. The attacker successfully enumerated 22 users, gained unauthorized administrative access through harvested credentials, and exfiltrated sensitive basket data from multiple accounts, including the admin account. This incident resulted in a full compromise of customer purchase data and unauthorized modification of cart items. The threat has been neutralized, and post-incident analysis is complete.

## Incident Timeline
| Timestamp | Phase | Event |
|---|---|---|
| 2026-03-12T00:00:00Z | MASTER | MISSION STARTED |
| 2026-03-12T00:01:00Z | recon | PHASE STARTED: recon |
| 2026-03-12T00:05:00Z | recon | PHASE COMPLETED: recon |
| 2026-03-12T00:06:00Z | scan | PHASE STARTED: scan |
| 2026-03-12T00:08:00Z | scan | PHASE COMPLETED: scan |
| 2026-03-12T00:09:00Z | enum | PHASE STARTED: enum |
| 2026-03-12T00:12:00Z | enum | PHASE COMPLETED: enum |
| 2026-03-12T00:13:00Z | exploit | PHASE STARTED: exploit |
| 2026-03-12T00:18:00Z | exploit | PHASE COMPLETED: exploit |
| 2026-03-12T00:19:00Z | postex | PHASE STARTED: postex |
| 2026-03-12T00:21:00Z | postex | PHASE COMPLETED: postex |
| 2026-03-12T00:25:00Z | MASTER | MISSION COMPLETE |

## Alert Summary
Total Alerts: 9
Severity Breakdown: Critical: 4 | High: 4 | Medium: 1 | Low: 0
Most Significant Alerts:
- [CRITICAL] IDOR exploit: Unauthorized read of admin basket
- [CRITICAL] IDOR exploit: Unauthorized modification of Jim's basket item
- [CRITICAL] IDOR exploit: Unauthorized read of customer basket (Bender)
- [CRITICAL] Mass exfiltration of 6 user baskets
- [HIGH] Unauthorized administrative login

## Attack Overview
The attack proceeded in several distinct phases, starting with reconnaissance where the attacker performed massive user enumeration using the /api/Users endpoint. Administrative credentials were harvested from unsecured application notes. The attacker then confirmed IDOR vulnerabilities on /rest/basket/:id by using a low-privilege JWT to access baskets belonging to other users. This led to the unauthorized reading and modification of customer and administrative basket data, culminating in the mass exfiltration of sensitive information.

## Scope of Compromise
- **Systems Affected:** 10.10.30.130 (OWASP Juice Shop)
- **Data Exposed:** 6 user baskets dumped, including sensitive purchase history and cart contents for admin, Jim, Bender, Amy, and Uvogin.
- **Access Level Achieved:** admin (Administrative credentials compromised: admin@juice-sh.op:[REDACTED])
- **Persistence Established:** NO
- **Lateral Movement:** NO

## Technical Findings

### Network Indicators
- **Attacker IPs:** lab-attacker
- **Target IPs/Hosts:** 10.10.30.130:3000
- **Open Ports Exploited:** 3000/tcp
- **Services Targeted:** OWASP Juice Shop (Express/Node.js)
- **URIs/Paths Accessed:** /api/Users, /rest/user/login, /rest/basket/:id, /api/BasketItems/:id, /api/BasketItems, /rest/track-order/:id
- **Protocols Used:** HTTP

### Host Indicators
- **Tools Used by Attacker:** curl, python3
- **Commands of Interest:**
  - curl -X POST /api/Users
  - curl GET /rest/basket/1
  - curl PUT /api/BasketItems/4
- **Files Accessed or Modified:** /rest/basket/1 (read), /api/BasketItems/4 (write), /rest/basket/3 (read), /api/BasketItems (read), /rest/track-order/:id (read)
- **Credentials Compromised:** admin@juice-sh.op:[REDACTED], idortest@pwn.lab (User ID 24)

### MITRE ATT&CK Coverage
| Tactic | Technique | Observed |
|---|---|---|
| Reconnaissance | T1592 — Gather Victim Host Information | YES |
| Initial Access | T1190 — Exploit Public-Facing Application | YES |
| Execution | T1059.003 — Command and Scripting Interpreter | YES |
| Credential Access | T1552 — Unsecured Credentials | YES |
| Discovery | T1087 — Account Discovery | YES |
| Collection | T1530 — Data from Cloud Storage Object | YES |
| Exfiltration | T1041 — Exfiltration Over C2 Channel | YES |

## IOCs for Detection
- **IP Addresses:** lab-attacker
- **URIs/Paths:** /api/Users, /rest/user/login, /rest/basket/:id, /api/BasketItems/:id, /api/BasketItems, /rest/track-order/:id
- **Behavioral Patterns:** Automated user enumeration followed by scripted IDOR testing on sensitive API endpoints. Sequential scanning of basket IDs.

## Gaps in Defensive Coverage
- **Lack of Ownership Validation:** Server-side failure to ensure user ownership of accessed resources (baskets).
- **Verbose API Endpoints:** /api/Users and /api/BasketItems provide excessive information.
- **Missing Security Headers:** Absence of CSP and HSTS headers.
- **Permissive CORS:** Wildcard CORS policy enabled.

---
