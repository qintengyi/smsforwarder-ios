import time
import hmac
import hashlib
import base64
import urllib.parse
import json
import requests
from config import Config

class SmsForwarderAPI:
    def __init__(self):
        self.config = Config
        self.base_url = f"http://{self.config.SMSFORWARDER_IP}:{self.config.SMSFORWARDER_PORT}"
    
    def generate_sign(self, timestamp):
        """生成签名"""
        if not self.config.SMSFORWARDER_SECRET:
            return ""
        
        sign_str = f"{timestamp}\n{self.config.SMSFORWARDER_SECRET}"
        hmac_sha256 = hmac.new(
            self.config.SMSFORWARDER_SECRET.encode('utf-8'),
            sign_str.encode('utf-8'),
            hashlib.sha256
        ).digest()
        base64_encoded = base64.b64encode(hmac_sha256).decode('utf-8')
        url_encoded = urllib.parse.quote(base64_encoded)
        return url_encoded
    
    def make_request(self, endpoint, data=None, method='POST'):
        """发送API请求"""
        timestamp = int(time.time() * 1000)
        sign = self.generate_sign(timestamp)
        
        payload = {
            "timestamp": timestamp,
            "sign": sign,
            "data": data or {}
        }
        
        headers = {
            'Content-Type': 'application/json; charset=utf-8'
        }
        
        url = f"{self.base_url}/{endpoint}"
        
        try:
            if method == 'POST':
                response = requests.post(url, json=payload, headers=headers, timeout=10)
            else:
                return {'code': 500, 'msg': 'Unsupported method'}
            
            response.raise_for_status()
            
            # 尝试解析JSON响应
            try:
                return response.json()
            except json.JSONDecodeError:
                # 如果不是JSON，返回原始文本
                return {
                    'code': 500,
                    'msg': f'Invalid JSON response: {response.text[:100]}...',
                    'raw_response': response.text
                }
                
        except requests.exceptions.RequestException as e:
            return {'code': 500, 'msg': f'Request failed: {str(e)}'}
        except Exception as e:
            return {'code': 500, 'msg': f'Unexpected error: {str(e)}'}
    
    def query_config(self):
        """查询服务端配置"""
        return self.make_request('config/query')
    
    def send_sms(self, sim_slot, phone_numbers, msg_content):
        """发送短信"""
        data = {
            "sim_slot": sim_slot,
            "phone_numbers": phone_numbers,
            "msg_content": msg_content
        }
        return self.make_request('sms/send', data)
    
    def query_sms(self, sms_type=1, page_num=1, page_size=10, keyword=""):
        """查询短信"""
        data = {
            "type": sms_type,
            "page_num": page_num,
            "page_size": page_size,
            "keyword": keyword
        }
        return self.make_request('sms/query', data)
    
    def query_calls(self, call_type=0, page_num=1, page_size=10, phone_number=""):
        """查询通话记录"""
        data = {
            "type": call_type,
            "page_num": page_num,
            "page_size": page_size,
            "phone_number": phone_number
        }
        return self.make_request('call/query', data)
    
    def query_contacts(self, phone_number="", name=""):
        """查询联系人"""
        data = {
            "phone_number": phone_number,
            "name": name
        }
        return self.make_request('contact/query', data)
    
    def add_contact(self, phone_number, name=""):
        """添加联系人"""
        data = {
            "phone_number": phone_number,
            "name": name
        }
        return self.make_request('contact/add', data)
    
    def query_battery(self):
        """查询电量"""
        return self.make_request('battery/query')
    
    def send_wol(self, mac, ip="", port=9):
        """发送WOL包"""
        data = {
            "mac": mac,
            "ip": ip,
            "port": port
        }
        return self.make_request('wol/send', data)
    
    def query_location(self):
        """查询定位"""
        return self.make_request('location/query')

# 创建API实例
sms_forwarder_api = SmsForwarderAPI()