import paramiko
import time

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

cmds = [
    # 检查 Go 进程到设备的网络连接（Hub 轮询会产生到 47.106.203.46:24000 的连接）
    "ss -tnp | grep 356530 | grep 47.106 2>/dev/null || echo 'no connections to device'",
    # 检查 Hub 是否有 goroutine 在 pollDevice
    "curl -s http://127.0.0.1:12123/api/auth/turnstile 2>/dev/null | head -5",
    # 检查 47.106.203.46:24000 是否可达
    "curl -s -o /dev/null -w 'http_code=%{http_code} time=%{time_total}' -m 5 http://47.106.203.46:24000/health 2>&1",
    # 直接从服务器内部调设备的 /sms/query
    """curl -s -m 10 -X POST http://47.106.203.46:24000/sms/query -H 'Content-Type: application/json' -d '{"data":{"type":1,"page_num":1,"page_size":3,"keyword":""},"timestamp":''' + str(int(time.time()*1000)) + ''',"sign":""}' 2>&1 | head -500""",
    # 检查 Go 进程的 goroutine 数量（如果 Hub 有泄漏）
    "ls /proc/356530/task/ 2>/dev/null | wc -l",
    # 检查设备 frp 隧道状态
    "curl -s -o /dev/null -w 'http_code=%{http_code} time=%{time_total}' -m 5 http://47.106.203.46:24000/config/query -X POST -H 'Content-Type: application/json' -d '{}' 2>&1",
]

for cmd in cmds:
    print(f"=== {cmd[:120]} ===")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=20)
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    if out.strip():
        print(out.strip()[:2000])
    if err.strip():
        print("STDERR:", err.strip()[:500])
    print()

ssh.close()
