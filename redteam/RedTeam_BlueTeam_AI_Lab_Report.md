# RedTeam / BlueTeam AI Cyber Range — Technical Build Report

**Author:** Personal Lab Notes
**Date:** 2026-03-13
**Location:** `/home/jayrid/RedTeam/`
**Status:** Fully Operational

---

## Table of Contents

1. [Lab Architecture Overview](#1-lab-architecture-overview)
2. [RedTeam Pipeline](#2-redteam-pipeline)
3. [BlueTeam Pipeline](#3-blueteam-pipeline)
4. [Mission Artifact Structure](#4-mission-artifact-structure)
5. [Agent Architecture](#5-agent-architecture)
6. [How attack.py Works](#6-how-attackpy-works)
7. [How BlueTeam Agents Analyze Missions](#7-how-blueteam-agents-analyze-missions)
8. [How mission_watcher.py Works](#8-how-mission_watcherpy-works)
9. [Cron Automation](#9-cron-automation)
10. [Completed Missions Summary](#10-completed-missions-summary)
11. [Lessons Learned](#11-lessons-learned)
12. [Future Improvements](#12-future-improvements)

---

## 1. Lab Architecture Overview

This is a fully automated AI-driven cyber range where a RedTeam agent pipeline attacks vulnerable web applications and a BlueTeam agent pipeline automatically analyzes the attack artifacts, generates incident reports, and produces defensive recommendations — with no human in the loop beyond the initial trigger.

```
┌──────────────────────────────────────────────────────────────────┐
│                    AI CYBER RANGE                                │
│                                                                  │
│  ┌─────────────┐    ┌──────────────────────────────────────┐    │
│  │  attack.py  │───▶│         RedTeam Pipeline             │    │
│  └─────────────┘    │  planner → master → recon → scan →   │    │
│                     │  enum → exploit → postex → report    │    │
│                     └──────────────┬───────────────────────┘    │
│                                    │ writes                      │
│                     ┌──────────────▼───────────────────────┐    │
│                     │   missions/<target>/<mission_id>/    │    │
│                     │   mission_state.json (status=done)   │    │
│                     └──────────────┬───────────────────────┘    │
│                                    │ polls every 5 min           │
│  ┌─────────────────────────────────▼──────────────────────┐     │
│  │              mission_watcher.py (cron)                 │     │
│  └─────────────────────────────────┬───────────────────────┘    │
│                                    │ triggers                    │
│                     ┌──────────────▼───────────────────────┐    │
│                     │         BlueTeam Pipeline            │    │
│                     │  master → alert-monitor →            │    │
│                     │  evidence-collector →                │    │
│                     │  threat-analyst → report-writer      │    │
│                     └──────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

### Directory Layout

```
/home/jayrid/RedTeam/
├── attack.py                    ← RedTeam entry point
├── missions/                    ← All mission data
│   ├── dvwa/
│   │   └── 2026-03-13-001/
│   └── juiceshop/
│       ├── 2026-03-12-001/
│       ├── 2026-03-12-002/
│       └── 2026-03-12-003/
├── blue/                        ← BlueTeam automation
│   ├── mission_watcher.py
│   ├── mission_watcher.service
│   ├── mission_watcher.cron
│   └── watcher.log
├── challenge_maps/              ← Vulnerability maps per target
├── CLAUDE.md                    ← Claude agent workspace config
└── GEMINI.md                    ← Gemini workspace config
```

### Agent Stack

```
Claude Code (orchestrator)
├── RedTeam agents  → ~/.claude/agents/redteam-*.md
└── BlueTeam agents → ~/.claude/agents/blueteam-*.md

Gemini CLI (executor)
└── gemini --yolo --prompt "..."  ← performs actual I/O, tool calls, file writes
```

**Key architectural rule:** Claude orchestrates. Gemini executes. This separation keeps Claude's context window clean, leverages Gemini's tool-use for file operations, and delegates heavy analysis without burning Claude tokens on low-level I/O.

---

## 2. RedTeam Pipeline

### 2.1 Pipeline Phases

```
mission-planner → master → recon → scan → enum → exploit → postex → report
```

| Phase | Agent | Key Output |
|---|---|---|
| Planning | `redteam-mission-planner` | `mission_plan.json`, `missions/index.json` entry |
| Orchestration | `redteam-master` | `mission_state.json`, `timeline.log` |
| Recon | `redteam-recon` | `recon/ping.txt`, `recon/dns.txt` |
| Scan | `redteam-scan` | `scan/nmap_full.txt`, `scan/open_ports.txt` |
| Enumeration | `redteam-enum` | `enum/gobuster.txt`, `enum/findings.txt` |
| Exploitation | `redteam-exploit-specialist` | `exploit/foothold.txt`, exploit artifacts |
| Post-Exploitation | `redteam-postex-specialist` | `postex/access_level.txt`, `loot/credentials.txt` |
| Reporting | `redteam-report-writer` | `report/mission_report.md`, `report/walkthrough.md` |

### 2.2 Mission State Machine

```
planned → running → [phase_failed] → running → ... → completed
```

`mission_state.json` tracks the current phase and transitions. The master agent is the sole writer of this file. Sub-agents write only within their designated phase subdirectory.

### 2.3 File Ownership (RedTeam)

- `redteam-master` owns: `mission_state.json`, `timeline.log`
- Sub-agents own: their phase directory only
- `commands.log`: all agents append, never overwrite

### 2.4 Targets

| Target | Type | IP | Port |
|---|---|---|---|
| DVWA | PHP/MySQL web app | 10.10.30.129 | 80 |
| OWASP Juice Shop | Node.js/REST API | 10.10.30.130 | 3000 |

---

## 3. BlueTeam Pipeline

### 3.1 Pipeline Phases

```
blueteam-master → alert-monitor → evidence-collector → threat-analyst → report-writer
```

| Phase | Agent | Key Output |
|---|---|---|
| Orchestration | `blueteam-master` | `incident_state.json`, `response_timeline.log` |
| Alert Monitoring | `blueteam-alert-monitor` | `alerts/alert_summary.txt`, `alerts/high_severity.json` |
| Evidence Collection | `blueteam-evidence-collector` | `evidence/artifact_manifest.txt`, `evidence/attack_indicators.txt`, `evidence/network_iocs.txt` |
| Threat Analysis | `blueteam-threat-analyst` | `analysis/threat_assessment.md`, `analysis/mitre_mapping.txt`, `analysis/ioc_list.txt`, `analysis/severity_rating.txt` |
| Incident Reporting | `blueteam-report-writer` | `reports/incident_report.md`, `reports/defensive_recommendations.md` |

### 3.2 Operating Mode

The BlueTeam operates in **mission artifact analysis mode** since Suricata IDS was not active during the attack windows. Agents read the completed RedTeam mission artifacts (timeline.log, commands.log, exploit/, loot/) and reconstruct attack activity from the attacker's own records — essentially treating the RedTeam's documentation as forensic evidence.

### 3.3 File Ownership (BlueTeam)

- `blueteam-master` owns: `blueteam/incident_state.json`, `blueteam/response_timeline.log`
- Sub-agents write only within their designated subdirectory
- Neither BlueTeam agent modifies RedTeam artifacts

### 3.4 Incident State Machine

```
running → alert_monitoring → evidence_collection → threat_analysis → reporting → complete
```

Mirrors the RedTeam state machine for consistency and resumability.

---

## 4. Mission Artifact Structure

### Full Tree (per mission)

```
missions/<target>/<mission_id>/
├── mission_plan.json           ← Scope, allowed attack types, learning objectives
├── mission_state.json          ← Phase tracker, status, constraints
├── timeline.log                ← Chronological event log
├── commands.log                ← Every command executed
├── recon/
│   ├── ping.txt
│   └── dns.txt
├── scan/
│   ├── nmap_full.txt
│   ├── open_ports.txt
│   └── findings.txt
├── enum/
│   ├── gobuster.txt
│   ├── ffuf.json
│   ├── nikto.txt
│   └── findings.txt
├── exploit/
│   └── foothold.txt (+ per-exploit markdown files)
├── postex/
│   ├── access_level.txt
│   ├── system_info.txt
│   ├── network_info.txt
│   └── privesc_scan.txt
├── loot/
│   ├── credentials.txt
│   └── interesting_files.txt
├── report/
│   ├── mission_report.md
│   └── walkthrough.md
└── blueteam/                   ← BlueTeam analysis layer (added post-mission)
    ├── incident_state.json
    ├── response_timeline.log
    ├── alerts/
    │   ├── alert_summary.txt
    │   └── high_severity.json
    ├── evidence/
    │   ├── artifact_manifest.txt
    │   ├── attack_indicators.txt
    │   └── network_iocs.txt
    ├── analysis/
    │   ├── threat_assessment.md
    │   ├── mitre_mapping.txt
    │   ├── ioc_list.txt
    │   └── severity_rating.txt
    └── reports/
        ├── incident_report.md
        └── defensive_recommendations.md
```

---

## 5. Agent Architecture

### 5.1 Agent File Format

All agents are markdown files in `~/.claude/agents/` with YAML frontmatter:

```yaml
---
name: agent-name
description: "When to invoke this agent (used for auto-routing)"
model: sonnet
memory: user
---
```

The description field is critical — it determines when Claude Code auto-selects the agent.

### 5.2 Gemini Delegation Model

Every agent follows the same 3-step pattern:

```
Step 1 — Pre-flight checks (Claude)
  └── Verify directories exist, verify required inputs

Step 2 — Delegate to Gemini (Claude executes Bash)
  └── gemini --yolo --prompt "$(cat <<'GEMINI_PROMPT' ... GEMINI_PROMPT)"

Step 3 — Verify outputs (Claude)
  └── ls -la expected output files, report failure if missing
```

Claude never reads artifact content directly. Gemini handles all file I/O, analysis, and writing. This prevents Claude's context from filling with raw log data.

### 5.3 Agent Roster

**RedTeam (8 agents):**
```
redteam-mission-planner    ← scope definition, mission_plan.json creation
redteam-master             ← pipeline orchestrator
redteam-recon              ← host discovery
redteam-scan               ← port scanning
redteam-enum               ← service/web enumeration
redteam-exploit-specialist ← vulnerability exploitation
redteam-postex-specialist  ← post-exploitation, loot
redteam-report-writer      ← mission_report.md + walkthrough.md
```

**BlueTeam (5 agents):**
```
blueteam-master            ← pipeline orchestrator
blueteam-alert-monitor     ← IDS alert generation / artifact analysis
blueteam-evidence-collector← IOC extraction, artifact manifest
blueteam-threat-analyst    ← MITRE ATT&CK mapping, severity rating
blueteam-report-writer     ← incident_report.md + defensive_recommendations.md
```

**Additional agents in ecosystem:**
```
redteam-mission-planner    ← (see above)
bb-master-agent            ← Bug bounty pipeline
htb-pwn-master             ← HackTheBox specialized pipeline
```

---

## 6. How attack.py Works

```python
# Full flow:
attack.py <target> <ip> [resume]
    │
    ├── No 'resume' flag:
    │   ├── subprocess.run(claude -p "use @redteam-mission-planner target:<t> ip:<ip>")
    │   └── subprocess.run(claude -p "use @redteam-master target:<t> ip:<ip>")
    │
    └── 'resume' flag:
        └── subprocess.run(claude --dangerously-skip-permissions -p "use @redteam-master ... resume")
```

**Key design choices:**
- Forces `cwd` to `~/RedTeam` before any subprocess call (ensures correct relative paths)
- Runs mission planner first (creates `mission_plan.json` and `index.json` entry)
- Runs master second (reads the plan, executes pipeline)
- Resume path skips the planner (plan already exists) and passes `resume` to master
- Uses `--dangerously-skip-permissions` on resume to avoid interactive prompts in headless mode

**Usage:**
```bash
./attack.py dvwa 10.10.30.129
./attack.py juiceshop 10.10.30.130
./attack.py juiceshop 10.10.30.130 resume
```

---

## 7. How BlueTeam Agents Analyze Missions

### 7.1 Alert Monitor

Reads `timeline.log`, `commands.log`, and all phase directories. Reconstructs defender-perspective alerts by categorizing attacker actions by severity:

- CRITICAL: exploitation confirmed, credentials stolen, admin access gained
- HIGH: active enumeration, exploitation attempt, data exfiltration
- MEDIUM: port scanning, directory brute-force
- LOW: ICMP ping, DNS resolution

Outputs structured `high_severity.json` for machine-readable downstream consumption.

### 7.2 Evidence Collector

Runs `find` against the mission directory tree, builds a full artifact manifest, then extracts IOCs:

- **Network IOCs:** attacker/target IPs, open ports exploited, URIs accessed, protocols
- **Host IOCs:** tools deployed, commands of interest, files accessed, credentials harvested
- **Alert correlation:** cross-references each HIGH/CRITICAL alert against collected evidence

### 7.3 Threat Analyst

Maps all observed activity to MITRE ATT&CK framework. For each tactic (TA0001–TA0010+), determines if it was observed and cites the supporting evidence file. Assigns overall severity (CRITICAL/HIGH/MEDIUM/LOW) with structured justification. Identifies specific defensive gaps.

### 7.4 Report Writer

Synthesizes all prior phase outputs into two documents without re-reading raw artifacts (reads only the prior agents' summaries):

1. `incident_report.md` — executive summary, attack timeline table, technical findings, MITRE mapping, IOC block
2. `defensive_recommendations.md` — CRITICAL (24h), HIGH (7 days), MEDIUM (30 days) action items with detection rule suggestions

**Token efficiency:** Each agent passes a clean summary to the next agent. The report writer reads `threat_assessment.md` (not `commands.log`). Avoids re-processing the same raw data at every stage.

---

## 8. How mission_watcher.py Works

### 8.1 Core Logic

```python
for each mission_state.json in /home/jayrid/RedTeam/missions/:
    if status in ["completed", "complete"]:
        if blueteam/ directory does NOT exist:
            os.makedirs(blueteam/, exist_ok=False)   # atomic lock
            write .watcher_lock
            subprocess.run(["claude", "-p", "use @blueteam-master mission:<path>"],
                           timeout=1800)
        else:
            log [SKIP]
```

### 8.2 Duplicate Prevention

Uses `os.makedirs(exist_ok=False)` as an atomic mutex. If two watcher instances run simultaneously, only one will succeed in creating `blueteam/`. The other hits `FileExistsError` and logs `[SKIP]`. This is race-condition safe on a single host.

Once the BlueTeam pipeline writes real output files, subsequent watcher runs see the directory exists and skip regardless of the lock file.

### 8.3 CLI Flags

| Flag | Behavior |
|---|---|
| `--once` | Single scan cycle, then exit (cron mode) |
| `--dry-run` | Scan and log but don't trigger or create locks |
| `--missions-dir PATH` | Override default missions path |
| `--log-path PATH` | Override default log path |

### 8.4 Log Format

```
2026-03-13T10:47:34 [SCAN]      Starting scan cycle
2026-03-13T10:47:34 [FOUND]     Detected completed mission: .../dvwa/2026-03-13-001
2026-03-13T10:47:34 [SKIP]      BlueTeam directory already exists
2026-03-13T10:47:35 [TRIGGER]   Invoking blueteam-master for mission: ...
2026-03-13T10:52:11 [SUCCESS]   BlueTeam analysis completed
2026-03-13T10:52:11 [CYCLE_END] Found: 4, Triggered: 1, Skipped: 3
```

---

## 9. Cron Automation

### 9.1 Installed Cron Entry

```cron
*/5 * * * * /usr/bin/python3 /home/jayrid/RedTeam/blue/mission_watcher.py --once >> /home/jayrid/RedTeam/blue/watcher.log 2>&1
```

Runs every 5 minutes. `--once` exits after a single scan so cron manages the schedule. Stdout and stderr both redirect to `watcher.log`.

### 9.2 Systemd Alternative

```ini
# /etc/systemd/system/mission_watcher.service
[Unit]
Description=Red Team Mission Watcher
After=network.target

[Service]
Type=simple
User=jayrid
WorkingDirectory=/home/jayrid/RedTeam
ExecStart=/usr/bin/python3 /home/jayrid/RedTeam/blue/mission_watcher.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo cp /home/jayrid/RedTeam/blue/mission_watcher.service /etc/systemd/system/
sudo systemctl enable --now mission_watcher
sudo journalctl -u mission_watcher -f
```

### 9.3 Full Automation Flow

```
attack.py finishes → mission_state.json status=completed
    ↓ (within 5 minutes)
cron fires mission_watcher.py --once
    ↓
watcher detects completed mission, no blueteam/ dir
    ↓
watcher creates blueteam/.watcher_lock (atomic)
    ↓
watcher invokes: claude -p "use @blueteam-master mission:<path>"
    ↓
blueteam-master runs 4-phase pipeline (~10-15 minutes)
    ↓
blueteam/reports/incident_report.md written
    ↓
watcher logs [SUCCESS]
```

---

## 10. Completed Missions Summary

### DVWA (2026-03-13-001) — 10.10.30.129

| # | Vulnerability | Severity | MITRE Technique |
|---|---|---|---|
| 1 | SQL Injection — UNION credential dump | CRITICAL | T1190, T1555 |
| 2 | OS Command Injection — arbitrary execution as www-data | CRITICAL | T1059.004 |
| 3 | Reflected XSS — session cookie exposure | HIGH | T1603 |
| 4 | Sensitive Data Exposure — config.inc.php.bak | HIGH | T1552.001 |

Kill chain stages: 7/14 | No persistence | No lateral movement
Credentials exfiltrated: 5 user MD5 hashes (admin, gordonb, 1337, pablo, smithy) + DB credentials

---

### OWASP Juice Shop — Mission 1 (2026-03-12-001) — 10.10.30.130:3000

| # | Vulnerability | Severity |
|---|---|---|
| 1 | SQLi Authentication Bypass | CRITICAL |
| 2 | SQLi UNION Credential Dump (22 accounts) | CRITICAL |
| 3 | Null Byte Path Traversal + KeePass Exfil | HIGH |
| 4 | Stored XSS — Product Review API | HIGH |
| 5 | Open FTP Directory Listing | HIGH |
| 6 | IDOR on User Baskets | HIGH |
| 7 | Unauthenticated Prometheus Metrics | MEDIUM |
| 8 | Unauthenticated Admin Config Endpoint | HIGH |

8 alerts, 8/8 true positives

---

### OWASP Juice Shop — Mission 2 (2026-03-12-002) — 10.10.30.130:3000

| # | Vulnerability | Severity | Note |
|---|---|---|---|
| 1 | SQLi Login Bypass | CRITICAL | |
| 2 | SQLi UNION Credential Dump (22 accounts) | CRITICAL | |
| 3 | JWT Algorithm Confusion (RS256→HS256) | CRITICAL | Non-expiring forged admin token, zero credentials needed |
| 4 | Stored XSS — Product Review API | HIGH | |
| 5 | Open FTP / Null Byte Bypass + KeePass DB | HIGH | Full credential vault exfiltrated |
| 6 | Unauthenticated Admin Config Endpoint | HIGH | |
| 7 | Open Directories — /encryptionkeys/, /support/logs | HIGH | JWT RSA public key exposed |

14-minute total compromise time from first probe to full admin.

---

### OWASP Juice Shop — Mission 3 (2026-03-12-003) — 10.10.30.130:3000

| # | Vulnerability | Severity | Note |
|---|---|---|---|
| 1 | IDOR Read — Admin basket | CRITICAL | Customer account accessed admin data |
| 2 | IDOR Write — Modify other user's basket | CRITICAL | |
| 3 | IDOR Read — Cross-user basket enumeration | CRITICAL | 6 users affected |
| 4 | Mass User Enumeration via /api/Users | HIGH | |
| 5 | Unauthenticated Admin Login | HIGH | |

Root cause: Express JWT middleware validates token signature but never checks `token.data.id` against `basket.UserId`. Zero privilege escalation required from a standard customer account.

---

## 11. Lessons Learned

### Architecture

1. **Claude as orchestrator, Gemini as executor is the right split.** Claude maintains clean state and context across phases. Gemini handles the messy I/O work without polluting the conversation context.

2. **File ownership rules are essential.** Without strict rules about which agent writes which file, agents will overwrite each other's state. The `mission_state.json` / `incident_state.json` ownership model prevented corruption across parallel runs.

3. **Atomic locking with `os.makedirs(exist_ok=False)` works reliably** for preventing duplicate BlueTeam investigations. The directory itself becomes the lock token.

4. **Gemini has heredoc shell limitations.** Multi-line heredocs in Gemini's bash tool cause parse errors. All file writes had to use `printf`, `base64 | decode`, or `write_file` tool workarounds. This is a known constraint to design around.

### Security Analysis

5. **JWT Algorithm Confusion is the most dangerous vulnerability found.** It requires zero credentials, produces a non-expiring token, and is invisible to most WAFs. If you expose RSA public keys (via `/encryptionkeys/` or JWKS endpoint), you are vulnerable.

6. **IDOR at the middleware layer is architectural, not fixable with input validation.** The fix must happen at the ownership check layer — every resource request must validate `requester.id == resource.owner_id`.

7. **MD5 password hashing in 2026 is unacceptable.** Every credential dump in these missions produced instantly crackable hashes. Bcrypt/Argon2id are the minimum bar.

8. **Open FTP directories with sensitive files is an immediate critical.** Both KeePass databases and M&A documents were accessible with a single anonymous FTP connection.

### Process

9. **The BlueTeam analysis surfaced findings the RedTeam report didn't explicitly flag.** The MITRE ATT&CK mapping added context (e.g., T1552.001 vs "credentials exposed") that is more actionable for defenders.

10. **Running BlueTeam against your own RedTeam missions is high signal training.** You see both perspectives on the same attack chain — what the attacker executed, and what a defender would have seen.

---

## 12. Future Improvements

### Near-term

- [ ] **Enable Suricata** during attack windows so BlueTeam alert-monitor gets real IDS alerts instead of artifact reconstruction
- [ ] **Add timestamp normalization** — mission artifacts use mixed timestamp formats; a preprocessing step would improve timeline accuracy
- [ ] **Watcher notification** — add Slack/Discord webhook to `mission_watcher.py` on `[SUCCESS]` events
- [ ] **Fix relative `mission_dir` paths** in some `mission_state.json` files (JS-001 and JS-002 have relative paths; should be absolute)

### Medium-term

- [ ] **Add `metasploitable` as a target** — network-layer exploitation, not just web app
- [ ] **Live dashboard** — a simple web UI reading `watcher.log` and `incident_state.json` files to show pipeline status in real time
- [ ] **CVSS scoring** in BlueTeam threat analyst output (groundwork exists in JS-002 report)
- [ ] **Defense simulation agent** — after BlueTeam report, apply recommendations automatically to the target and re-run the RedTeam mission to verify they work

### Long-term

- [ ] **Multi-target parallel missions** — run DVWA and Juice Shop simultaneously, correlate findings
- [ ] **Adversary emulation profiles** — map RedTeam missions to specific APT TTPs (e.g., OWASP Top 10, OWASP API Top 10)
- [ ] **Knowledge base accumulation** — persist MITRE mappings and IOCs across missions to a searchable database
- [ ] **Auto-remediation agent** — a `blueteam-remediator` that applies patches/configs based on defensive recommendations

---

*End of Technical Build Report*
*All missions conducted in controlled lab environment against intentionally vulnerable targets.*
