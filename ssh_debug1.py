import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

cmds = [
    # 最新日志 - 看WS连接频率是否还是每2秒一次
    "journalctl -u smsforwarder.service --since '5 min ago' --no-pager 2>/dev/null | tail -60",
    # 检查设备proxy请求日志 - 看Hub轮询是否在调设备
    "journalctl -u smsforwarder.service --since '5 min ago' --no-pager 2>/dev/null | grep -iE 'proxy|sms/query|device' | tail -20",
    # 查看数据库中设备信息
    "mysql -u root -e 'SELECT id,user_id,name,api_base_url,sign_key FROM smsf_xiaoyyua_top.devices;' 2>/dev/null || mysql -u root -pqty8520123 -e 'SELECT id,user_id,name,api_base_url,sign_key FROM smsf_xiaoyyua_top.devices;' 2>/dev/null",
    # 查看设备是否能ping通
    "mysql -u root -e 'SELECT id,user_id,name,api_base_url FROM smsf_xiaoyyua_top.devices;' 2>/dev/null",
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
