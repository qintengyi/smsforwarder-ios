import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

cmds = [
    # Find the plugin that handles sms_binding
    "grep -r 'sms_binding' /www/wwwroot/koishi/ --include='*.js' --include='*.ts' -l 2>/dev/null",
    "grep -r 'sms_binding' /www/wwwroot/koishi/ --include='*.json' -l 2>/dev/null",
    # List plugins
    "ls -la /www/wwwroot/koishi/node_modules/koishi-plugin-* 2>/dev/null | head -30",
    "find /www/wwwroot/koishi -maxdepth 3 -name '*.js' -path '*sms*' 2>/dev/null | head -20",
    "find /www/wwwroot/koishi -maxdepth 3 -name '*.ts' -path '*sms*' 2>/dev/null | head -20",
    # Look for external plugins
    "ls -la /www/wwwroot/koishi/plugins/ 2>/dev/null",
    "ls -la /www/wwwroot/koishi/external/ 2>/dev/null",
    # Koishi config
    "cat /www/wwwroot/koishi/package.json 2>/dev/null",
    # Look for koishi config file
    "find /www/wwwroot/koishi -maxdepth 2 -name 'koishi.*' -o -name 'config.*' 2>/dev/null | head -10",
    "ls -la /www/wwwroot/koishi/ 2>/dev/null",
    # Check Koishi data directory for plugin configs
    "ls -la /www/wwwroot/koishi/data/ 2>/dev/null | head -20",
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
