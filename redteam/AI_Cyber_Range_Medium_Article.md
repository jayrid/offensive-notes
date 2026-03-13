# How I Built an AI Red Team vs. Blue Team Cybersecurity Lab That Attacks and Defends Itself

*Two AI pipelines. One fires. The other responds. No human in the loop.*

---

The attack started at 2:10 AM.

Not from a person — from an AI agent. It scanned the target, found the open port, confirmed default credentials, and started mapping vulnerabilities. By 2:21 AM it had dumped five password hashes from a backend database, executed arbitrary commands on the web server, and written a full professional pentest report with remediation notes.

Then, within five minutes of finishing, a second AI pipeline automatically kicked in — reading the attacker's own notes as forensic evidence, generating security alerts, mapping the attack to MITRE ATT&CK, and producing a defensive incident report with prioritized remediation recommendations.

I didn't touch a keyboard for any of it.

Here's how I built that system, why it matters, and how you can build your own.

---

## The Problem I Was Solving

Security training has a fundamental tension: **you can't learn to defend what you haven't learned to attack, and you can't learn to attack without something to attack**.

Traditional solutions are slow. Setting up a lab takes hours. Running an attack manually takes more hours. Writing up the report takes even more. By the time you get the defensive perspective, you've lost the thread of what the attacker actually did.

I wanted something different. I wanted a system where:

1. I fire off an attack with one command
2. The AI executes the full offensive kill chain autonomously
3. The defensive analysis happens automatically afterward
4. I get both a red team report *and* a blue team incident report without writing either myself

What I built is what I'm calling an **AI cyber range** — a fully automated offensive and defensive lab where AI agents play both sides.

---

## The Architecture: Two Pipelines, One File System

The whole system lives in `/home/jayrid/RedTeam/`. The core insight is simple: **the attacker's mission artifacts are the defender's evidence**.

When the red team pipeline finishes, it leaves behind a structured directory tree:

```
missions/dvwa/2026-03-13-001/
├── timeline.log        ← every attack phase, timestamped
├── commands.log        ← every command executed
├── exploit/            ← proof-of-concept files
├── loot/               ← credentials, sensitive files
└── report/             ← attacker's own write-up
```

The blue team pipeline reads that exact same directory and reconstructs the incident from the defender's perspective — without needing a SIEM, without Suricata running during the attack, without any additional instrumentation.

The attacker's notes become the forensic evidence. The attacker's walkthrough becomes the incident timeline. It's an elegant loop.

---

## The Red Team: Teaching an AI to Hack

The offensive pipeline is built on **Claude Code** as the orchestrator and **Gemini CLI** as the executor.

Here's the key architectural decision that made everything work: *Claude thinks, Gemini acts.*

Claude maintains the mission state, enforces scope constraints, decides what to do next. Gemini runs the actual commands — nmap, curl, sqlmap, gobuster — and writes the results to disk. This keeps Claude's context window clean and uses each AI for what it's best at.

The pipeline has seven phases:

```
plan → recon → scan → enumerate → exploit → post-exploit → report
```

To launch a mission:

```bash
./attack.py juiceshop 10.10.30.130
```

That single command:
1. Runs a mission planner agent that reads a vulnerability map and writes `mission_plan.json` with scope constraints, allowed attack types, and learning objectives
2. Hands off to the mission master, which executes each phase in sequence
3. Enforces the scope rules (no DoS, no attacks outside the target IP, max 5 exploits)
4. Produces a professional pentest report and step-by-step walkthrough at the end

The scope enforcement is real. If the exploit agent finds a vulnerability that's listed as out-of-scope, the master logs it as `OUT-OF-SCOPE BLOCKED` and discards the result. This matters a lot when you're running automated attacks — guardrails aren't optional.

### What the AI Actually Found

Against OWASP Juice Shop in one 14-minute session, the red team pipeline:

- Bypassed authentication via SQL injection (`OR 1=1--`)
- Dumped all 22 user credential hashes via UNION SELECT
- Discovered the JWT RSA public key sitting in an unauthenticated `/encryptionkeys/` endpoint
- Used that public key as an HMAC secret to forge a non-expiring admin token (JWT algorithm confusion — RS256 to HS256)
- Downloaded a KeePass credential database from an open FTP directory
- Exploited a stored XSS vulnerability via the product review API
- Accessed an unauthenticated admin configuration endpoint exposing OAuth secrets

**All of this happened autonomously. No human typed a single command.**

The most dangerous finding — the JWT algorithm confusion — requires zero credentials and produces a token that never expires. The AI found it, exploited it, documented it, and flagged it as critical. A human analyst reading the report afterward learned about an attack class they might never have encountered in a traditional tutorial.

---

## The Blue Team: Teaching an AI to Investigate

After the red team mission completes, a five-agent blue team pipeline analyzes the attack.

```
alert-monitor → evidence-collector → threat-analyst → report-writer
```

Each agent is coordinated by a `blueteam-master` orchestrator that tracks incident state, enforces file ownership, and ensures no agent overwrites another's work.

### Phase 1: Alert Monitoring

The alert monitor reads all mission artifacts and generates IDS-style alerts from the defender's perspective. It classifies each attack event by severity:

- **CRITICAL**: Confirmed exploitation, credential theft, admin access
- **HIGH**: Active enumeration, exploitation attempts, data exfiltration
- **MEDIUM**: Port scanning, directory brute-force
- **LOW**: Passive recon, DNS lookups

Against the DVWA mission, it generated 9 alerts: 3 critical, 3 high, 2 medium, 1 low. All 9 were true positives.

### Phase 2: Evidence Collection

The evidence collector catalogs every artifact produced during the attack and extracts two categories of IOCs:

- **Network**: Attacker IPs, targeted ports, URIs accessed, protocols
- **Host**: Tools used, commands executed, files accessed, credentials stolen

It then cross-references each high-severity alert against the collected evidence to confirm corroboration. This is the step that would normally take a SOC analyst hours.

### Phase 3: Threat Analysis

This is where the analysis gets genuinely educational. The threat analyst maps the entire attack chain to the MITRE ATT&CK framework:

```
TA0043 Reconnaissance     → T1595 Active Scanning          ✓
TA0001 Initial Access     → T1190 Exploit Public-Facing App ✓
TA0002 Execution          → T1059.004 Unix Shell            ✓
TA0006 Credential Access  → T1552.001 Credentials in Files  ✓
TA0007 Discovery          → T1046 Network Service Discovery ✓
TA0009 Collection         → T1213 Data from Repositories   ✓
```

For the DVWA mission, 7 of 14 MITRE ATT&CK kill chain stages were completed. No persistence was established, no lateral movement occurred. The analyst assigned CRITICAL severity and identified the specific defensive gaps that allowed the attack to succeed.

### Phase 4: Incident Report

The report writer synthesizes everything into two documents:

1. **`incident_report.md`** — Executive summary, attack timeline, technical findings, IOC block, MITRE mapping. Written for a CISO or security team.

2. **`defensive_recommendations.md`** — Prioritized remediation: CRITICAL items for the next 24 hours, HIGH for the next week, MEDIUM for the next month. Includes specific detection rules based on observed IOCs.

The result is indistinguishable from a report a skilled human analyst would write — because it's built from the same evidence a human analyst would use.

---

## The Automation Layer: Closing the Loop

The final piece is what makes it truly autonomous: `mission_watcher.py`.

```python
# The core logic:
for each mission in /missions/:
    if status == "completed" and blueteam/ not yet created:
        atomically create blueteam/.watcher_lock
        trigger: claude -p "use @blueteam-master mission:<path>"
```

A cron job runs this script every 5 minutes:

```cron
*/5 * * * * python3 /home/jayrid/RedTeam/blue/mission_watcher.py --once
```

The duplicate prevention is elegant: `os.makedirs(exist_ok=False)` is atomic. If two watcher instances run simultaneously, only one succeeds in creating the `blueteam/` directory. The other hits `FileExistsError` and logs `[SKIP]`. No database, no external lock service needed.

The full flow from trigger to finished incident report looks like this:

```
attack.py completes → mission_state.json: status=completed
    ↓ within 5 minutes
cron fires watcher → detects completed mission → creates lock
    ↓
claude -p "use @blueteam-master mission:<path>"
    ↓
4-phase BlueTeam pipeline runs (~10-15 minutes)
    ↓
incident_report.md and defensive_recommendations.md written
```

You run `./attack.py juiceshop 10.10.30.130`, go make coffee, and come back to a folder with a complete pentest report and a complete incident response analysis.

---

## Why This Accelerates Learning

Traditional cybersecurity training is sequential: you learn an attack, then separately you learn the defense. You rarely see both perspectives on the same event at the same time.

This lab collapses that gap.

When the IDOR vulnerability in Juice Shop was exploited, the red team report described *how* to do it — the specific API endpoints, the curl commands, the bypassed authorization checks. The blue team report described *what it looked like* — the anomalous pattern of HTTP 200 responses for `/rest/basket/*` with sequential user IDs from a single source.

Reading both reports side by side gives you something most training can't: **the attacker's playbook and the defender's detection opportunity for the same vulnerability, in the same session.**

The JWT algorithm confusion finding is a perfect example. Most people learn about it from a blog post with a diagram. Here you can read the exact exploit steps the AI used, the exact forged token it created, and the exact detection rules the blue team recommended to catch it in the future. That's a different level of understanding.

---

## Building Your Own

You need:

1. **A vulnerable target** — DVWA or OWASP Juice Shop are free and easy to spin up with Docker
2. **Claude Code** — the CLI tool this system runs on
3. **Gemini CLI** — handles the actual command execution (`npm install -g @google/generative-ai-cli`)
4. **The agent files** — markdown files in `~/.claude/agents/` that define each agent's behavior

The agent architecture is the most important part to get right. Each agent is a markdown file with:
- A frontmatter description that tells Claude when to invoke it
- A clear "ONLY responsibilities" list (Claude orchestrates, Gemini executes)
- Pre-flight checks, a Gemini delegation block, and post-flight verification

The scope enforcement in `mission_plan.json` is essential if you're running this on any network that isn't completely isolated. Define exactly what's in-scope, what's out-of-scope, and what the maximum number of exploits is. The agents honor these constraints — but you need to set them first.

---

## The Bigger Picture

We're at the beginning of a shift in how security professionals learn and practice.

AI agents can now execute a full attack chain autonomously, document every step, and then immediately switch perspectives and analyze what just happened from the defender's side. That feedback loop — attack, observe, analyze, defend — used to take days. Now it takes 20 minutes.

That doesn't replace human expertise. It amplifies it. A junior analyst running this lab against DVWA for a week will encounter SQL injection, command injection, XSS, IDOR, JWT confusion, path traversal, and credential exposure — with both the attacker's methodology and the defender's response documented for each one.

That's the point. Offensive skills make you a better defender. Defensive skills make you a better attacker. This system forces you to develop both at the same time, on the same targets, with AI doing the heavy lifting so you can focus on understanding what happened and why.

The machines are running the attacks. The machines are writing the reports. Your job is to read them, question them, and get better.

---

## Key Takeaways

- **Claude orchestrates, Gemini executes.** This architectural split keeps context clean, leverages each AI's strengths, and scales to complex multi-phase pipelines.
- **The attacker's notes are the defender's evidence.** When both sides live in the same file system, cross-perspective analysis is automatic.
- **Scope enforcement isn't optional.** Automated attack pipelines must have guardrails. `mission_plan.json` scope constraints are checked before every phase.
- **JWT algorithm confusion and IDOR are architectural vulnerabilities** — they can't be fixed with WAF rules. Understanding them at the code level is the only real defense.
- **Atomic directory creation is a reliable distributed lock** for single-host automation. No external dependencies needed.

---

## Start Here

If you want to build this yourself, start small:

1. **Spin up DVWA in Docker** — it runs in under two minutes
2. **Install Claude Code** and write a single agent that runs nmap against your lab target
3. **Add Gemini CLI** and move the nmap execution into a `gemini --yolo --prompt` block
4. **Extend to a full scan phase**, then an enum phase
5. **Add the BlueTeam layer** once the RedTeam pipeline produces reliable artifacts

The full system took significant iteration to get right. The Gemini heredoc shell limitations alone required several workarounds. But the architecture is sound, and the results are real — four completed missions, four full incident response analyses, and a mission watcher that will automatically analyze every future mission within five minutes of completion.

The lab runs itself now. That's the goal.

---

*If this sparked an idea, drop a comment with what target you'd point it at first. And if you build your own version — I want to hear about what the AI finds.*

---

*Tags: cybersecurity, AI agents, penetration testing, blue team, red team, OWASP, home lab, Claude, Python*
