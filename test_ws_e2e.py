"""
端到端测试 WebSocket 短信推送链路（直接用 JWT secret 签发 token）
"""
import json
import time
import requests
import threading
import websocket
import jwt  # PyJWT

SERVER = "https://smsf.xiaoyyua.top"
WS_URL = "wss://smsf.xiaoyyua.top/api/ws"
DEVICE_ID = 1
JWT_SECRET = "gagsegsdaw4124fqr"

# 1. 直接签发 JWT token
print("=== 1. 签发 JWT token ===")
payload = {
    "uid": 1,
    "usr": "qty666",
    "exp": int(time.time()) + 3600,
    "iat": int(time.time()),
}
token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")
print(f"Token: {token[:60]}...")

# 2. 直接调 /sms/query 看设备返回的原始数据格式
print("\n=== 2. 直接查询设备 SMS（看原始数据格式）===")
proxy_r = requests.post(
    f"{SERVER}/api/device/{DEVICE_ID}/proxy/sms/query",
    headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    json={"type": 1, "page_num": 1, "page_size": 5, "keyword": ""},
    timeout=30
)
print(f"SMS query status: {proxy_r.status_code}")
try:
    sms_data = proxy_r.json()
    sms_str = json.dumps(sms_data, ensure_ascii=False)
    print(f"SMS response ({len(sms_str)} chars): {sms_str[:3000]}")
    # 特别关注 date 字段的类型和值
    if "data" in sms_data:
        data = sms_data["data"]
        if isinstance(data, list):
            records = data
        elif isinstance(data, dict):
            records = data.get("list", data.get("records", []))
        else:
            records = []
        print(f"\nRecords count: {len(records)}")
        for i, rec in enumerate(records[:5]):
            date_val = rec.get("date")
            print(f"  Record {i}: date={date_val!r} (type={type(date_val).__name__}), "
                  f"name={rec.get('name')!r}, content={str(rec.get('content',''))[:80]!r}")
except Exception as e:
    print(f"Parse error: {e}")
    print(f"Raw response: {proxy_r.text[:500]}")

# 3. 连接 WebSocket
print("\n=== 3. 连接 WebSocket ===")
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
    # 订阅设备
    sub_msg = json.dumps({"action": "subscribe", "device_id": DEVICE_ID})
    ws.send(sub_msg)
    print(f"  [{time.strftime('%H:%M:%S')} WS SEND] {sub_msg}")
    # ping loop
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

print(f"  Running WS for 45 seconds (waiting for new SMS)...")
wst = threading.Thread(target=ws.run_forever, kwargs={"ping_interval": 25, "ping_timeout": 10}, daemon=True)
wst.start()
time.sleep(45)

print(f"\n=== 4. 结果 ===")
print(f"Total messages received: {len(messages_received)}")
for msg in messages_received:
    print(f"  {msg[:300]}")

ws.close()
print("\nDone.")
