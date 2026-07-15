import paramiko
import threading
import time

# 在后台线程中持续读取服务器日志
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

# 先启动日志监控
print("=== Starting log monitor ===")
log_lines = []
def monitor_logs():
    cmd = "journalctl -u smsforwarder.service -f --no-pager -o cat 2>/dev/null"
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=120)
    for line in stdout:
        line_str = line.decode('utf-8', errors='replace').strip()
        if line_str:
            log_lines.append(line_str)
            if '[Hub]' in line_str or 'ws' in line_str.lower() or 'subscribe' in line_str.lower():
                print(f"  [SERVER LOG] {line_str}")

t = threading.Thread(target=monitor_logs, daemon=True)
t.start()
time.sleep(2)

# 运行 E2E 测试
import json
import requests
import websocket
import jwt

SERVER = "https://smsf.xiaoyyua.top"
WS_URL = "wss://smsf.xiaoyyua.top/api/ws"
DEVICE_ID = 1
JWT_SECRET = "gagsegsdaw4124fqr"

# 签发 token
payload = {
    "uid": 1,
    "usr": "qty666",
    "exp": int(time.time()) + 3600,
    "iat": int(time.time()),
}
token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")
print(f"\n=== Connecting WS ===")

messages_received = []
def on_message(ws, message):
    ts = time.strftime("%H:%M:%S")
    print(f"  [{ts} WS RECV] {message[:300]}")
    messages_received.append(message)

def on_error(ws, error):
    print(f"  [WS ERROR] {error}")

def on_close(ws, close_status, close_msg):
    print(f"  [WS CLOSE] status={close_status} msg={close_msg}")

def on_open(ws):
    print(f"  [{time.strftime('%H:%M:%S')} WS OPEN] Connected!")
    sub_msg = json.dumps({"action": "subscribe", "device_id": DEVICE_ID})
    ws.send(sub_msg)
    print(f"  [{time.strftime('%H:%M:%S')} WS SEND] {sub_msg}")
    def ping_loop():
        while True:
            time.sleep(20)
            try:
                ws.send(json.dumps({"action": "ping"}))
                print(f"  [{time.strftime('%H:%M:%S')} WS SEND] ping")
            except:
                break
    threading.Thread(target=ping_loop, daemon=True).start()

ws = websocket.WebSocketApp(
    f"{WS_URL}?token={token}",
    on_open=on_open,
    on_message=on_message,
    on_error=on_error,
    on_close=on_close,
)

print("  Running WS for 60 seconds...")
wst = threading.Thread(target=ws.run_forever, kwargs={"ping_interval": 25, "ping_timeout": 10}, daemon=True)
wst.start()
time.sleep(60)

ws.close()
time.sleep(1)

print(f"\n=== Results ===")
print(f"Total WS messages received: {len(messages_received)}")
for msg in messages_received:
    print(f"  {msg[:300]}")

print(f"\n=== Server Hub logs ({len([l for l in log_lines if '[Hub]' in l])} lines) ===")
hub_logs = [l for l in log_lines if '[Hub]' in l]
for log in hub_logs[-30:]:
    print(f"  {log}")

ssh.close()
print("\nDone.")
