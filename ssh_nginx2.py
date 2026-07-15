import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

cmds = [
    # Check for map directive defining $connection_upgrade
    "nginx -T 2>&1 | grep -A2 'connection_upgrade' | head -20",
    # Check the full nginx.conf
    "cat /www/server/nginx/conf/nginx.conf 2>/dev/null | head -60",
    # Check if there's a map directive somewhere
    "grep -r 'map.*\\$http_upgrade' /www/server/nginx/ 2>/dev/null | head -10",
    "grep -r 'map.*connection_upgrade' /www/server/nginx/ 2>/dev/null | head -10",
    # Test WS connection directly to backend (bypass Nginx)
    "curl -s -o /dev/null -w '%{http_code}' -H 'Upgrade: websocket' -H 'Connection: Upgrade' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Sec-WebSocket-Version: 13' 'http://127.0.0.1:12123/api/ws?token=test' 2>/dev/null",
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
