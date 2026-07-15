import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

cmds = [
    "find / -maxdepth 4 -name '*.py' -path '*bot*' 2>/dev/null | head -20",
    "find / -maxdepth 4 -name '*.js' -path '*bot*' 2>/dev/null | head -20",
    "find / -maxdepth 4 -type d -name '*bot*' 2>/dev/null | head -20",
    "find / -maxdepth 4 -name 'sms_binding*' 2>/dev/null | head -20",
    "ps aux | grep -i bot | grep -v grep",
    "ps aux | grep -i qq | grep -v grep",
    "ps aux | grep -i napcat | grep -v grep",
    "ps aux | grep -i onebot | grep -v grep",
    "docker ps 2>/dev/null | head -20",
    "systemctl list-units --type=service --state=running 2>/dev/null | grep -iE 'bot|qq|napcat|onebot|sms'",
    "find / -maxdepth 3 -name 'config*' -path '*napcat*' 2>/dev/null | head -10",
    "find / -maxdepth 3 -name 'config*' -path '*lagrange*' 2>/dev/null | head -10",
    "find /www -maxdepth 3 -type d 2>/dev/null | head -30",
]
for cmd in cmds:
    print(f"=== {cmd} ===")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=15)
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    if out.strip():
        print(out.strip())
    if err.strip():
        print("STDERR:", err.strip())
    print()
ssh.close()
