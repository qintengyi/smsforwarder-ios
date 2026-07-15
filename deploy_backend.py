import paramiko
import os

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("192.168.1.2", port=5321, username="root", password="qty8520123", timeout=15)

# 1. 上传新二进制
print("=== Uploading binary ===")
sftp = ssh.open_sftp()
local_path = "/tmp/smsforwarder-panel"
remote_path = "/www/wwwroot/smsf.xiaoyyua.top/smsforwarder-panel-deploy/smsforwarder-panel.new"
sftp.put(local_path, remote_path)
sftp.chmod(remote_path, 0o755)
remote_size = sftp.stat(remote_path).st_size
local_size = os.path.getsize(local_path)
print(f"Uploaded: local={local_size} remote={remote_size}")
sftp.close()

# 2. 停止服务 → 替换 → 启动
cmds = [
    "systemctl stop smsforwarder.service",
    "mv /www/wwwroot/smsf.xiaoyyua.top/smsforwarder-panel-deploy/smsforwarder-panel.new /www/wwwroot/smsf.xiaoyyua.top/smsforwarder-panel-deploy/smsforwarder-panel",
    "systemctl start smsforwarder.service",
    "sleep 2 && systemctl is-active smsforwarder.service",
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
print("Done!")
