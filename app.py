from flask import Flask, render_template, request, jsonify, redirect, url_for, flash, session, g
from config import Config
from utils import sms_forwarder_api
from functools import wraps
import time
import re
import hmac
import hashlib
import base64
import json

app = Flask(__name__)
app.config.from_object(Config)
app.secret_key = Config.SECRET_KEY


# MARK: - 认证系统

def generate_token(username):
    """生成认证 token: base64(username:timestamp:hmac)"""
    timestamp = str(int(time.time()))
    sign_str = f"{username}:{timestamp}"
    sign = hmac.new(
        Config.AUTH_SECRET.encode('utf-8'),
        sign_str.encode('utf-8'),
        hashlib.sha256
    ).hexdigest()
    token_data = f"{username}:{timestamp}:{sign}"
    return base64.b64encode(token_data.encode('utf-8')).decode('utf-8')


def verify_token(token):
    """验证 token 是否有效（7 天有效期）"""
    try:
        decoded = base64.b64decode(token).decode('utf-8')
        parts = decoded.split(':')
        if len(parts) != 3:
            return False
        username, timestamp_str, sign = parts
        timestamp = int(timestamp_str)
        # 7 天过期
        if time.time() - timestamp > 7 * 24 * 3600:
            return False
        # 验证签名
        sign_str = f"{username}:{timestamp_str}"
        expected_sign = hmac.new(
            Config.AUTH_SECRET.encode('utf-8'),
            sign_str.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(sign, expected_sign)
    except Exception:
        return False


def require_auth(f):
    """API 认证装饰器：检查 Authorization: Bearer <token>"""
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get('Authorization', '')
        if auth_header.startswith('Bearer '):
            token = auth_header[7:]
            if verify_token(token):
                return f(*args, **kwargs)
        return jsonify({'code': 401, 'msg': '未登录或登录已过期', 'data': None}), 200
    return decorated

# 注册模板过滤器
@app.template_filter('timestamp_to_datetime')
def timestamp_to_datetime(timestamp):
    if not timestamp:
        return ''
    try:
        timestamp = int(timestamp)
        return time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(timestamp / 1000))
    except (ValueError, TypeError):
        return str(timestamp)

def is_valid_mac(mac):
    """验证MAC地址格式"""
    mac_pattern = r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$'
    return re.match(mac_pattern, mac) is not None

# 首页 - 仪表盘
@app.route('/')
def dashboard():
    # 获取配置信息
    config_response = sms_forwarder_api.query_config()
    
    # 获取电量信息
    battery_response = sms_forwarder_api.query_battery()
    
    # 获取定位信息
    location_response = sms_forwarder_api.query_location()
    
    return render_template('dashboard.html', 
                         config=config_response, 
                         battery=battery_response,
                         location=location_response,
                         device_ip=Config.SMSFORWARDER_IP)

# 短信功能
@app.route('/sms', methods=['GET', 'POST'])
def sms():
    if request.method == 'POST':
        action = request.form.get('action')
        
        if action == 'send':
            sim_slot = int(request.form.get('sim_slot', 1))
            phone_numbers = request.form.get('phone_numbers', '').strip()
            msg_content = request.form.get('msg_content', '').strip()
            
            if not phone_numbers or not msg_content:
                flash('手机号码和短信内容不能为空', 'error')
                return redirect(url_for('sms'))
            
            response = sms_forwarder_api.send_sms(sim_slot, phone_numbers, msg_content)
            if response.get('code') == 200:
                flash('短信发送成功', 'success')
            else:
                flash(f'短信发送失败: {response.get("msg", "未知错误")}', 'error')
        
        elif action == 'query':
            sms_type = int(request.form.get('sms_type', 1))
            page_num = int(request.form.get('page_num', 1))
            page_size = int(request.form.get('page_size', 10))
            keyword = request.form.get('keyword', '')
            
            response = sms_forwarder_api.query_sms(sms_type, page_num, page_size, keyword)
            if response.get('code') == 200:
                sms_list = response.get('data', [])
                return render_template('sms.html', 
                                     sms_list=sms_list,
                                     sms_type=sms_type,
                                     page_num=page_num,
                                     page_size=page_size,
                                     keyword=keyword)
            else:
                flash(f'查询短信失败: {response.get("msg", "未知错误")}', 'error')
    
    return render_template('sms.html', sms_list=[])

# 通话功能
@app.route('/calls', methods=['GET', 'POST'])
def calls():
    if request.method == 'POST':
        call_type = int(request.form.get('call_type', 0))
        page_num = int(request.form.get('page_num', 1))
        page_size = int(request.form.get('page_size', 10))
        phone_number = request.form.get('phone_number', '')
        
        response = sms_forwarder_api.query_calls(call_type, page_num, page_size, phone_number)
        if response.get('code') == 200:
            call_list = response.get('data', [])
            return render_template('call.html', 
                                 call_list=call_list,
                                 call_type=call_type,
                                 page_num=page_num,
                                 page_size=page_size,
                                 phone_number=phone_number)
        else:
            flash(f'查询通话记录失败: {response.get("msg", "未知错误")}', 'error')
    
    return render_template('call.html', call_list=[])

# 联系人功能
@app.route('/contacts', methods=['GET', 'POST'])
def contacts():
    if request.method == 'POST':
        action = request.form.get('action')
        
        if action == 'query':
            phone_number = request.form.get('phone_number', '')
            name = request.form.get('name', '')
            
            response = sms_forwarder_api.query_contacts(phone_number, name)
            if response.get('code') == 200:
                contact_list = response.get('data', [])
                return render_template('contact.html', 
                                     contact_list=contact_list,
                                     phone_number=phone_number,
                                     name=name)
            else:
                flash(f'查询联系人失败: {response.get("msg", "未知错误")}', 'error')
        
        elif action == 'add':
            phone_number = request.form.get('phone_number', '').strip()
            name = request.form.get('name', '').strip()
            
            if not phone_number:
                flash('手机号码不能为空', 'error')
                return redirect(url_for('contacts'))
            
            response = sms_forwarder_api.add_contact(phone_number, name)
            if response.get('code') == 200:
                flash('联系人添加成功', 'success')
            else:
                flash(f'添加联系人失败: {response.get("msg", "未知错误")}', 'error')
    
    return render_template('contact.html', contact_list=[])

# 电量功能
@app.route('/battery')
def battery():
    response = sms_forwarder_api.query_battery()
    if response.get('code') == 200:
        battery_data = response.get('data', {})
    else:
        battery_data = {}
        flash(f'查询电量失败: {response.get("msg", "未知错误")}', 'error')
    
    return render_template('battery.html', battery=battery_data)

# 定位功能
@app.route('/location')
def location():
    response = sms_forwarder_api.query_location()
    if response.get('code') == 200:
        location_data = response.get('data', {})
    else:
        location_data = {}
        flash(f'查询定位失败: {response.get("msg", "未知错误")}', 'error')
    
    return render_template('location.html', location=location_data)

# WOL功能
@app.route('/wol', methods=['GET', 'POST'])
def wol():
    if request.method == 'POST':
        mac = request.form.get('mac', '').strip().replace('-', ':')
        ip = request.form.get('ip', '').strip()
        port = int(request.form.get('port', 9))
        
        if not mac or not is_valid_mac(mac):
            flash('MAC地址格式不正确', 'error')
            return redirect(url_for('wol'))
        
        response = sms_forwarder_api.send_wol(mac, ip, port)
        if response.get('code') == 200:
            flash('WOL包发送成功', 'success')
        else:
            flash(f'WOL发送失败: {response.get("msg", "未知错误")}', 'error')
    
    return render_template('wol.html')

# API 端点 - 用于 AJAX 请求 / iOS App 调用

@app.route('/api/login', methods=['POST'])
def api_login():
    """用户登录 - 返回认证 token"""
    data = request.get_json(silent=True) or {}
    username = data.get('username', '').strip()
    password = data.get('password', '').strip()
    if not username or not password:
        return jsonify({'code': 400, 'msg': '用户名和密码不能为空', 'data': None})
    if username == Config.AUTH_USERNAME and password == Config.AUTH_PASSWORD:
        token = generate_token(username)
        return jsonify({'code': 200, 'msg': '登录成功', 'data': {'token': token, 'username': username}})
    return jsonify({'code': 401, 'msg': '用户名或密码错误', 'data': None})

@app.route('/api/config')
@require_auth
def api_config():
    response = sms_forwarder_api.query_config()
    return jsonify(response)

@app.route('/api/battery')
@require_auth
def api_battery():
    response = sms_forwarder_api.query_battery()
    return jsonify(response)

@app.route('/api/location')
@require_auth
def api_location():
    response = sms_forwarder_api.query_location()
    return jsonify(response)

@app.route('/api/sms', methods=['GET'])
@require_auth
def api_sms_query():
    """查询短信列表 - iOS App 调用"""
    sms_type = int(request.args.get('type', 1))
    page_num = int(request.args.get('page_num', 1))
    page_size = int(request.args.get('page_size', 20))
    keyword = request.args.get('keyword', '')
    response = sms_forwarder_api.query_sms(sms_type, page_num, page_size, keyword)
    return jsonify(response)

@app.route('/api/sms/send', methods=['POST'])
@require_auth
def api_sms_send():
    """发送短信 - iOS App 调用"""
    data = request.get_json(silent=True) or {}
    sim_slot = int(data.get('sim_slot', 1))
    phone_numbers = data.get('phone_numbers', '').strip()
    msg_content = data.get('msg_content', '').strip()
    if not phone_numbers or not msg_content:
        return jsonify({'code': 400, 'msg': '手机号码和短信内容不能为空', 'data': None})
    response = sms_forwarder_api.send_sms(sim_slot, phone_numbers, msg_content)
    return jsonify(response)

@app.route('/api/calls', methods=['GET'])
@require_auth
def api_calls_query():
    """查询通话记录 - iOS App 调用"""
    call_type = int(request.args.get('type', 0))
    page_num = int(request.args.get('page_num', 1))
    page_size = int(request.args.get('page_size', 20))
    phone_number = request.args.get('phone_number', '')
    response = sms_forwarder_api.query_calls(call_type, page_num, page_size, phone_number)
    return jsonify(response)

@app.route('/api/contacts', methods=['GET'])
@require_auth
def api_contacts_query():
    """查询联系人 - iOS App 调用"""
    phone_number = request.args.get('phone_number', '')
    name = request.args.get('name', '')
    response = sms_forwarder_api.query_contacts(phone_number, name)
    return jsonify(response)

@app.route('/api/contacts/add', methods=['POST'])
@require_auth
def api_contacts_add():
    """添加联系人 - iOS App 调用"""
    data = request.get_json(silent=True) or {}
    phone_number = data.get('phone_number', '').strip()
    name = data.get('name', '').strip()
    if not phone_number:
        return jsonify({'code': 400, 'msg': '手机号码不能为空', 'data': None})
    response = sms_forwarder_api.add_contact(phone_number, name)
    return jsonify(response)

@app.route('/api/wol', methods=['POST'])
@require_auth
def api_wol_send():
    """发送 WOL 唤醒包 - iOS App 调用"""
    data = request.get_json(silent=True) or {}
    mac = data.get('mac', '').strip().replace('-', ':')
    ip = data.get('ip', '').strip()
    port = int(data.get('port', 9))
    if not mac or not is_valid_mac(mac):
        return jsonify({'code': 400, 'msg': 'MAC地址格式不正确', 'data': None})
    response = sms_forwarder_api.send_wol(mac, ip, port)
    return jsonify(response)

@app.route('/api/dashboard', methods=['GET'])
@require_auth
def api_dashboard():
    """仪表盘聚合数据 - iOS App 调用（一次请求获取 config + battery + location）"""
    config_resp = sms_forwarder_api.query_config()
    battery_resp = sms_forwarder_api.query_battery()
    location_resp = sms_forwarder_api.query_location()
    return jsonify({
        'code': 200,
        'msg': 'success',
        'data': {
            'config': config_resp,
            'battery': battery_resp,
            'location': location_resp
        }
    })

if __name__ == '__main__':
    app.run(host=Config.HOST, port=Config.PORT, debug=Config.DEBUG)