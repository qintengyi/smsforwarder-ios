import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

cmds = [
    # List koishi root directory
    "ls -la /www/wwwroot/koishi/",
    # Look for plugins directory (local plugins)
    "ls -la /www/wwwroot/koishi/plugins/ 2>/dev/null || echo 'no plugins dir'",
    "ls -la /www/wwwroot/koishi/external/ 2>/dev/null || echo 'no external dir'",
    # Koishi data directory
    "ls -la /www/wwwroot/koishi/data/ 2>/dev/null | head -20",
    # Look for local custom plugins (not in node_modules)
    "find /www/wwwroot/koishi -maxdepth 2 -name '*.ts' -not -path '*/node_modules/*' 2>/dev/null | head -30",
    "find /www/wwwroot/koishi -maxdepth 2 -name '*.js' -not -path '*/node_modules/*' 2>/dev/null | head -30",
    # grep without node_modules
    "grep -r 'sms_binding' /www/wwwroot/koishi/ --include='*.js' --include='*.ts' -l --exclude-dir=node_modules 2>/dev/null",
    # Check koishi.yml or similar config
    "cat /www/wwwroot/koishi/koishi.yml 2>/dev/null | head -50 || echo 'no koishi.yml'",
    # Check package.json
    "cat /www/wwwroot/koishi/package.json 2>/dev/null",
]
for cmd in cmds:
    print(f"=== {cmd} ===")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=20)
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    if out.strip():
        print(out.strip())
    if err.strip():
        print("STDERR:", err.strip())
    print()
ssh.close()
