# GEMINI.md - HTB Workspace Overview

This directory serves as a centralized workspace for Hack The Box (HTB) penetration testing labs. It is organized by machine name, with each directory containing the full lifecycle of a machine's compromise, from initial enumeration to final privilege escalation.

## Project Structure

The workspace is divided into several main subdirectories, each representing a specific HTB target:

- **Pterodactyl/**: A Hard-difficulty Linux machine (openSUSE).
    - Focus: PAM environment poisoning (CVE-2025-6018) and UDisks2/libblockdev race conditions (CVE-2025-6019).
    - `walkthrough.md`: Comprehensive step-by-step guide.
    - `exploits/`: Contains bash and Python scripts for automation.
- **Unknown/**: A Linux machine featuring Laravel.
    - Focus: Laravel encrypted cookie forgery and PHP object deserialization.
    - `exploits/laravel_exploit.py`: Main RCE exploit utilizing `phpggc`.
    - `notes/enumeration.md`: Detailed service discovery notes.
- **WingData/**: A machine focused on specialized services.
    - Focus: Wing FTP Server Unauthenticated RCE (CVE-2025-47812) via Lua injection.
    - `exploits/cve_2025_47812_wingftp_rce.py`: Python exploit for unauthenticated root access.

## Key Files & Artifacts

- **VPN Configuration**: `competitive_Jayrid.ovpn` is used for connecting to the HTB internal network.
- **Exploit Scripts**: Located in `*/exploits/`, these are mostly Python or Bash scripts tailored for specific CVEs or misconfigurations.
- **Loot**: Found in `*/loot/`, containing flags (`user.txt`, `root.txt`), captured credentials, and password hashes.
- **Scans**: Located in `*/scans/`, containing Nmap, Gobuster, and other tool outputs.

## Usage Guidelines

1.  **Connectivity**: Ensure the HTB VPN is active using the `.ovpn` file before running any exploit scripts.
    ```bash
    sudo openvpn competitive_Jayrid.ovpn
    ```
2.  **Target IPs**: Most scripts have target IPs hardcoded (e.g., `10.129.4.99` for Pterodactyl, `10.129.4.107` for WingData). Always verify the current machine IP in the HTB dashboard before execution.
3.  **Documentation**: Refer to the `walkthrough.md` files in each directory for detailed technical explanations of the exploitation chains.
4.  **Tools**: The workspace relies on standard penetration testing tools including:
    - `nmap`, `gobuster`, `ffuf` (Enumeration)
    - `phpggc` (Payload generation for PHP deserialization)
    - `udisksctl`, `gdbus` (Linux post-exploitation)
    - `python3` (Exploit automation)

## Development & Research Conventions

- **Surgical Exploits**: Exploits are designed to be as non-destructive as possible.
- **Note-Taking**: Every machine follows a standard structure of `scans/`, `exploits/`, `loot/`, and `notes/` to maintain consistency.
- **Cleanup**: Most walkthroughs include an "Artifacts Left on Target" section for proper cleanup after gaining root.
