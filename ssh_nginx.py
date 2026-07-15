import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

cmds = [
    "cat /www/server/panel/vhost/nginx/smsf.xiaoyyua.top.conf",
    # Check if $connection_upgrade map is defined
    "grep -r 'connection_upgrade' /www/server/nginx/conf/ 2>/dev/null | head -5",
    "grep -r 'connection_upgrade' /etc/nginx/ 2>/dev/null | head -5",
    # Check nginx proxy timeout settings
    "nginx -T 2>/dev/null | grep -iE 'proxy_read_timeout|proxy_send_timeout' | head -10",
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
