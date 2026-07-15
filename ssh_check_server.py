import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

cmds = [
    # Check smsforwarder service logs for WS activity
    "journalctl -u smsforwarder.service --since '1 hour ago' --no-pager 2>/dev/null | grep -iE 'ws|websocket|subscribe|poll' | tail -30",
    # Check if smsforwarder is running
    "systemctl status smsforwarder.service 2>/dev/null | head -15",
    # Check Nginx config for WebSocket
    "cat /www/server/panel/vhost/nginx/smsf.xiaoyyua.top.conf 2>/dev/null | head -80",
    "grep -r 'proxy_pass.*12123\\|Upgrade\\|Connection.*upgrade\\|api/ws' /www/server/panel/vhost/nginx/ 2>/dev/null | head -20",
    # Check if WS endpoint is reachable
    "curl -s -o /dev/null -w '%{http_code}' -H 'Upgrade: websocket' -H 'Connection: Upgrade' -H 'Sec-WebSocket-Key: test' -H 'Sec-WebSocket-Version: 13' 'https://smsf.xiaoyyua.top/api/ws?token=test' 2>/dev/null",
    # Check smsforwarder service logs - general
    "journalctl -u smsforwarder.service --since '10 min ago' --no-pager 2>/dev/null | tail -40",
    # Check if the binary has the ws handler
    "strings /www/wwwroot/smsf.xiaoyyua.top/smsforwarder-panel-deploy/smsforwarder-panel 2>/dev/null | grep -i 'websocket\\|/api/ws' | head -10",
    # Check what port it's listening on
    "ss -tlnp | grep smsforwarder 2>/dev/null || ss -tlnp | grep 12123 2>/dev/null",
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
