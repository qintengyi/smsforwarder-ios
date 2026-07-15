import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

cmds = [
    # 查看最近3分钟的 Hub 日志
    "journalctl -u smsforwarder.service --since '3 min ago' --no-pager -o cat 2>/dev/null | grep -i '\\[Hub\\]' | tail -30",
    # 查看最近3分钟的所有日志（不过滤）
    "journalctl -u smsforwarder.service --since '3 min ago' --no-pager -o cat 2>/dev/null | tail -50",
    # 确认新二进制在运行
    "journalctl -u smsforwarder.service --since '5 min ago' --no-pager -o cat 2>/dev/null | head -10",
]
for cmd in cmds:
    print(f"=== {cmd[:120]} ===")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=20)
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    if out.strip():
        print(out.strip())
    if err.strip():
        print("STDERR:", err.strip())
    print()
ssh.close()
