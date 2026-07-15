# SmsForwarder Web Control 项目记忆

## 项目构成
- `app.py` / `config.py` / `utils.py`：Flask Web 控制台，通过 HTTP API 控制 SmsForwarder Android 设备
- `templates/`：8 个 HTML 页面（dashboard/sms/call/contact/battery/location/wol/base）
- `ios/`：iOS 原生 SwiftUI 控制应用复刻（视觉对齐 iOS 18）

## iOS 工程打包约定
- 用 XcodeGen（`ios/project.yml`）生成 .xcodeproj，不用手写 pbxproj
- GitHub Actions（`.github/workflows/build-ipa.yml`，macos-15/Xcode 16）编译未签名 ipa
- 用户用全能签 + 自有 p12 / .mobileprovision 重签安装到 iPhone 16 Pro iOS 18.6
- 未签名 build：`CODE_SIGNING_ALLOWED=NO`，.app → `Payload/` → zip 成 ipa
- AppIcon 单尺寸 1024（Xcode 15+ 支持），用 PIL 生成

## 技术细节
- ~~iOS App 通过 Flask Web 面板 JSON API 获取数据~~（已改为 Go 面板代理模式）
- **Go 面板 API**：`POST /api/auth/login`（用户名+密码+Turnstile token）→ Bearer token
- **设备代理**：`POST /api/device/:id/proxy{path}` 转发所有数据请求到设备
- **Turnstile**：Cloudflare 人机验证，site_key=`0x4AAAAAADinuFAATCEbWkGv`，iOS 用 WKWebView 渲染
- iOS AppSettings 存 `serverURL` + `token` + `username` + `currentDeviceId`（多设备管理）
- DeviceStore（@Observable）管理设备列表，持久化当前选中设备
- 模型宽松解码：兼容数字或字符串（如 "85%"、"1700000000000"）
- 时间统一北京时间 Asia/Shanghai
- Info.plist 配 `NSAllowsArbitraryLoads=YES` + `UIRequiresFullScreen=true`
- Info.plist 启动屏用 `UILaunchStoryboardName=LaunchScreen`（非 `UILaunchScreen`+`UIColorName`），配套 `LaunchScreen.storyboard`
- **XcodeGen `info` 键缺陷**：Xcode 26 中不正确设置 `INFOPLIST_FILE`，需移除 `info` 键、在 build settings 中显式设 `INFOPLIST_FILE: Sources/SmsForwarder/Info.plist` + `GENERATE_INFOPLIST_FILE: NO`
- 部署目标 iOS 17（@Observable 宏需要）；Swift 5.9
- **Turnstile WKWebView**：baseURL 必须设为面板服务器地址（与 site_key 注册域名匹配），不能用 `challenges.cloudflare.com`
- **Dashboard 错误隔离**：各 API 调用用 `async let` + `try?` 独立捕获错误，不因一个失败导致全部失败（类似 Promise.allSettled）
- **checkProxyHealth 容错**：不走标准 proxyCall，直接发请求并多格式解析（标准 APIResponse / 简单 JSON / 任意 200 响应）
- **验证码灵动岛**：Widget Extension（app-extension）+ ActivityKit Live Activity；ActivityAttributes 放 `Sources/Shared/`（App+Widget 各编译，无需 App Group）；WebSocketClient 连 wss://面板/api/ws，audio 后台保活（静音 WAV）；规则匹配项目名 `【】`+验证码正则；Info.plist 需 NSSupportsLiveActivities + UIBackgroundModes(audio)

## 关键路径
- iOS 源码：`ios/Sources/SmsForwarder/`（App 入口 + Models + Network + 12 Views）
- 打包教程：`ios/打包安装指南.md`
- 图标生成 venv：`C:\Users\Administrator\.workbuddy\binaries\python\envs\default`
- **GCM 推送问题**：Windows GCM OAuth token 过期后非交互环境无法刷新。解决方法：用 PAT + 禁用凭据助手推送 `git -c credential.helper= push https://x-access-token:PAT@github.com/... main`
- **GitHub 推送推荐**：用本机 gh CLI（已认证 qintengyi），`gh auth setup-git` 后 `git push origin main`；用户文本给的 PAT 可能已失效
- **Go 面板后端源码**：`D:\esp32-ai\panel\server\`（部署目录只有二进制）；本机 Go 1.26 交叉编译 linux amd64

## 服务器部署架构
- **面板**：Go 编译二进制（`smsforwarder-panel`），非 Python Flask
- **部署路径**：`/www/wwwroot/smsf.xiaoyyua.top/smsforwarder-panel-deploy/`
- **SSH**：`ssh -p 5321 root@192.168.1.2`（密码 qty8520123），但 192.168.1.2 是网关转发
- **服务器真实 IP**：192.168.1.8（ens2）、192.168.1.9（ens6）
- **默认网关**：192.168.1.12（部分公网 IP 不可达，需特定路由走 192.168.1.1 小米路由器）
- **永久路由**：`route-frps.service` 将 47.106.203.46 走 192.168.1.1
- **面板端口**：12123，Nginx 反代 HTTPS（smsf.xiaoyyua.top）
- **数据库**：MySQL smsf_xiaoyyua_top，表 users/devices/api_keys/api_logs
- **Turnstile**：登录需人机验证，测试时可临时设 TURNSTILE_ENABLED=false
- **frps**：在公网 47.106.203.46:7105，Lucky 面板管理（端口 16601）
- **手机 frpc**：内嵌在 smsforwarder-daemon（Magisk 模块），配置 /data/adb/smsforwarder/frpc.toml
- **手机 daemon**：监听 0.0.0.0:5000，sign_key=qty8520123，内嵌 frp v0.57.0
- **frp 版本**：手机内嵌 v0.57.0，frps 必须匹配（v0.61.1 不兼容）
- **网络问题**：服务器→手机 192.168.1.17:5000 HTTP 超时（TCP 可达），服务器→47.106.203.46 需走 192.168.1.1 网关
- **WebSocket 实时推送**：`GET /api/ws`（JWT 鉴权 ?token=），Hub 周期 4s 轮询设备 /sms/query 去重推送；Nginx 已配 WS 反代；客户端发 `{"action":"subscribe","device_id":N}`
- **Koishi QQ 机器人**：systemd `koishi.service`，Node.js v24.12.0，目录 `/www/wwwroot/koishi/`
- **sms_binding 表**：在 `koishidb` 数据库（非面板库 smsf_xiaoyyua_top），由 Koishi 插件 `koishi-plugin-smsforwarder` 管理
- **Koishi 插件源码**：`/www/wwwroot/koishi/external/koishi-plugin-smsforwarder/`（src/index.ts + lib/index.js）
- **Bot 注册流程**：Koishi 插件调 `POST /api/bot/register`（X-Bot-Secret 鉴权）→ Go 面板创建 users 记录 → Koishi 插件写 sms_binding 记录（两步无事务）
- **Koishi 唯一索引语法**：`unique: ['a','b']` = 两个独立唯一索引；`unique: [['a','b']]` = 复合唯一索引
- **SSH paramiko**：`ssh` 命令密码认证失败(Permission denied)，需用 Python paramiko 库连接
