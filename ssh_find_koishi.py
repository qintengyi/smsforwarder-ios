import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

cmds = [
    "systemctl cat koishi.service 2>/dev/null",
    "find / -maxdepth 4 -type d -name 'koishi' 2>/dev/null | head -10",
    "find / -maxdepth 4 -type d -name 'koishidev*' 2>/dev/null | head -10",
    "ls -la /www/wwwroot/koishidev.xiaoyyua.top/ 2>/dev/null | head -20",
    "find / -maxdepth 5 -name 'package.json' -path '*koishi*' 2>/dev/null | head -10",
    # Look for sms_binding in koishi databases
    "find / -maxdepth 5 -name '*.json' -path '*koishi*' 2>/dev/null | head -20",
    # Check koishi data directory
    "find /root -maxdepth 3 -type d -name 'koishi*' 2>/dev/null | head -10",
    "find / -maxdepth 3 -name 'koishi.yml' -o -name 'koishi.config.yml' 2>/dev/null | head -10",
    # Check llonebot directory
    "ls -la /www/wwwroot/llonebot/ 2>/dev/null | head -20",
    # Search for sms_binding in any file
    "grep -r 'sms_binding' /www/wwwroot/koishidev.xiaoyyua.top/ 2>/dev/null | head -20",
    "grep -r 'sms_binding' /www/wwwroot/llonebot/ 2>/dev/null | head -20",
    # Check MySQL for sms_binding table
    "mysql -u root -e 'SHOW DATABASES;' 2>/dev/null",
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
