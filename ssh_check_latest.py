import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

cmds = [
    # 最近的 Hub 日志（看是否推送了 SMS）
    "journalctl -u smsforwarder.service --since '10 min ago' --no-pager -o cat 2>/dev/null | grep '\\[Hub\\]' | tail -40",
    # 最近的 WS 连接
    "journalctl -u smsforwarder.service --since '10 min ago' --no-pager -o cat 2>/dev/null | grep '/api/ws' | tail -20",
    # 最近的 sms/query 请求
    "journalctl -u smsforwarder.service --since '10 min ago' --no-pager -o cat 2>/dev/null | grep 'sms/query' | tail -20",
    # 完整最近日志（不过滤）
    "journalctl -u smsforwarder.service --since '5 min ago' --no-pager -o cat 2>/dev/null | tail -60",
]
for cmd in cmds:
    print(f"=== {cmd[:100]} ===")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=20)
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    if out.strip():
        print(out.strip())
    if err.strip():
        print("STDERR:", err.strip())
    print()
ssh.close()
