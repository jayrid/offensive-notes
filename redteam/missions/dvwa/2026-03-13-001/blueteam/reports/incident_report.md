# Incident Report: BLUE-2026-03-13-001

**Target:** 10.10.30.129 (DVWA)
**Date:** 2026-03-13
**Severity:** CRITICAL
**Status:** Closed — Post-Incident Analysis
**Prepared by:** Blue Team Operations

---

## Executive Summary
On March 13, 2026, the DVWA application (10.10.30.129) was the target of a successful cyber attack by an external threat actor. The attacker leveraged multiple web application vulnerabilities to achieve unauthorized access to the system and its backend database. This resulted in the theft of administrative and user credentials, as well as the exposure of sensitive system configuration files. The incident has been contained, and the system is currently under post-incident analysis to implement necessary security hardening.

## Incident Timeline
| Timestamp | Phase | Event |
|---|---|---|
| 2026-03-13T02:10:05Z | recon | Host discovery and identification of DVWA instance; initial access via default credentials (admin/password). |
| 2026-03-13T02:12:01Z | scan | Port 80 scan and directory enumeration; discovery of sensitive configuration backup (/config/config.inc.php.bak). |
| 2026-03-13T02:16:01Z | enum | Systematic confirmation of SQL Injection, OS Command Injection, and Reflected XSS vulnerabilities. |
| 2026-03-13T02:21:01Z | exploit | Exfiltration of 5 user credential hashes, execution of arbitrary OS commands as www-data, and recovery of database credentials. |
| 2026-03-13T02:35:01Z | postex | Final impact assessment and confirmation of data exfiltration success. |
| 2026-03-13T02:40:01Z | report | Mission conclusion and generation of attacker-side documentation. |

## Alert Summary
- **Total Alerts:** 9
- **Severity Breakdown:** 3 Critical, 3 High, 2 Medium, 1 Low
- **Significant Alerts:**
    - [CRITICAL] SQL Injection Exploitation - 5 user credentials exfiltrated.
    - [CRITICAL] OS Command Injection Exploitation - Arbitrary command execution and /etc/passwd read.
    - [CRITICAL] Sensitive Data Disclosure - Database credentials exfiltrated from backup configuration file.
    - [HIGH] Reflected XSS - Potential session cookie exposure confirmed.

## Attack Overview
The attack unfolded in a methodical four-stage process: reconnaissance, scanning, enumeration, and exploitation. The threat actor (lab-attacker) utilized automated tools like nmap and curl to identify the target and confirm multiple injection vectors. The primary techniques involved SQL Injection to dump the user database, OS Command Injection via the web interface to read system files, and direct access to an unsecured configuration backup file. These combined efforts allowed for a complete compromise of the application's confidentiality.

## Scope of Compromise
- **Systems Affected:** 10.10.30.129 (DVWA Web Server)
- **Data Exposed:** /etc/passwd system file, backend database credentials (app/vulnerables), and 5 web application user hashes (admin, gordonb, 1337, pablo, smithy).
- **Access Level Achieved:** www-data (system user) and administrative control of the web application.
- **Persistence Established:** NO
- **Lateral Movement:** NO

## Technical Findings

### Network Indicators
- **Attacker IP:** lab-attacker
- **Target IP:** 10.10.30.129
- **Protocols/Ports:** HTTP (Port 80), ICMP
- **Targeted URIs:** /vulnerabilities/sqli/, /vulnerabilities/exec/, /vulnerabilities/xss_r/, /config/config.inc.php.bak

### Host Indicators
- **Tools:** nmap, curl, ping, bash, MariaDB
- **Commands:** 
    - `999' UNION SELECT user,password FROM users-- -`
    - `ip=127.0.0.1|id`
    - `ip=127.0.0.1|cat /etc/passwd`
    - `<script>alert(document.cookie)</script>`
- **Files Accessed:** /etc/passwd, /var/www/html/config/config.inc.php.bak
- **Credentials:** Redacted hashes for admin and 4 users; database user 'app' with password [REDACTED].

### MITRE ATT&CK Coverage
| Tactic | Technique | Observed |
|---|---|---|
| Reconnaissance | T1595 — Active Scanning | YES |
| Initial Access | T1190 — Exploit Public-Facing Application | YES |
| Execution | T1059.004 — Unix Shell | YES |
| Credential Access | T1552.001 — Credentials In Files | YES |
| Credential Access | T1603 — Steal Web Session Cookie | YES |
| Credential Access | T1555 — Credentials from Web Browsers | YES |
| Discovery | T1083 — File and Directory Discovery | YES |
| Discovery | T1046 — Network Service Discovery | YES |
| Collection | T1213 — Data from Information Repositories | YES |
| Exfiltration | T1041 — Exfiltration Over C2Channel | YES |

## IOCs for Detection
- **IPs:** `lab-attacker`, `10.10.30.129`
- **URIs:** `/vulnerabilities/sqli/`, `/vulnerabilities/exec/`, `/config/config.inc.php.bak`, `/phpinfo.php`
- **Signatures:**
    - HTTP requests containing `UNION SELECT`
    - Shell meta-characters (`|`, `;`, `&`) in POST parameters (specifically `ip=` field)
    - `<script>` tags in GET parameters

## Gaps in Defensive Coverage
- **Insecure File Management:** Sensitive configuration backups (.bak) were stored in the publicly accessible web root.
- **Input Validation Failure:** Lack of sanitization on parameters passed to database queries and system shell commands.
- **Weak Authentication:** Use of default administrative credentials (admin/password) enabled immediate initial access.
- **Information Leakage:** Detailed system information exposed via `/phpinfo.php` and unrestricted directory listings.
