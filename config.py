import os
from dotenv import load_dotenv

# 加载环境变量
load_dotenv()

class Config:
    # 服务器配置
    HOST = os.getenv('HOST', '0.0.0.0')
    PORT = int(os.getenv('PORT', 5001))
    DEBUG = os.getenv('DEBUG', 'False').lower() == 'true'
    
    # SmsForwarder 配置
    SMSFORWARDER_IP = os.getenv('SMSFORWARDER_IP', '192.168.1.16')  # 替换为您的手机IP
    SMSFORWARDER_PORT = int(os.getenv('SMSFORWARDER_PORT', 5000))
    SMSFORWARDER_SECRET = os.getenv('SMSFORWARDER_SECRET', 'your-secret-key-here')
    
    # 加密配置
    USE_ENCRYPTION = os.getenv('USE_ENCRYPTION', 'False').lower() == 'true'
    ENCRYPTION_TYPE = os.getenv('ENCRYPTION_TYPE', 'SM4')  # RSA or SM4
    
    # 安全配置
    SECRET_KEY = os.getenv('SECRET_KEY', 'your-flask-secret-key')

    # 登录认证配置
    AUTH_USERNAME = os.getenv('AUTH_USERNAME', 'admin')
    AUTH_PASSWORD = os.getenv('AUTH_PASSWORD', 'admin')
    AUTH_SECRET = os.getenv('AUTH_SECRET', 'smsf-auth-secret-2024')