# SmsForwarder iOS

SmsForwarder 设备远程控制 iOS 应用（纯 SwiftUI 实现，视觉风格对齐 iOS 18）。

## 🚀 快速打包成 ipa（无需 Mac）

👉 **看 [`打包安装指南.md`](./打包安装指南.md)**：把本目录 + `.github/` 上传到 GitHub 公开仓库，云端 macOS 自动编译生成未签名 `SmsForwarder.ipa`，下载后用**全能签**重签安装到 iPhone 16 Pro / iOS 18.6，全程免费。

打包用 **XcodeGen**（`project.yml`）生成 `.xcodeproj`，由 `.github/workflows/build-ipa.yml` 驱动 `xcodebuild` 编译，无需手写 Xcode 工程。

## 如何在 Xcode 16 中打开运行

本仓库以 **Swift Package Manager** 形式组织，避免手写复杂的 `.xcodeproj`。

### 方式一：作为 Swift Package 在 Xcode 中打开

1. 打开 Xcode 16。
2. `File → Open`（或 `⌘O`）选择本目录 `ios/` 下的 `Package.swift`。
3. Xcode 会自动解析依赖并生成可执行 target `SmsForwarder`。
4. 选择一个 iOS 17+ 模拟器或真机，点击 ▶ 运行。

> ⚠️ SwiftPM 的 iOS executable target 在 Xcode 16 中可直接运行到模拟器/真机。若 Xcode 提示无法直接运行 executable，请改用方式二。

### 方式二：新建 Xcode 工程引用源码（最稳妥）

1. Xcode → `File → New → Project` → 选择 `App` 模板，名称 `SmsForwarder`，Interface 选 `SwiftUI`，语言 `Swift`。
2. 删除新建工程自带的 `ContentView.swift`、`SmsForwarderApp.swift`（或留空覆盖）。
3. 将 `Sources/SmsForwarder/` 下所有 `.swift` 文件拖入工程（勾选 "Copy items if needed"）。
4. 在 target 的 `Info` 选项卡下添加 `App Transport Security Settings` → `Allow Arbitrary Loads` = `YES`（因为设备是局域网 HTTP 服务）。
5. 选择真机/模拟器运行。

## 技术栈

- SwiftUI（iOS 17+）
- @Observable 宏（Observation 框架）
- URLSession + async/await
- 无第三方依赖

## 文件结构

```
ios/
├── Package.swift
├── README.md
└── Sources/SmsForwarder/
    ├── SmsForwarderApp.swift
    ├── Info.plist
    ├── Models/
    │   ├── APIResponse.swift
    │   └── AppModels.swift
    ├── Network/
    │   └── SmsForwarderAPI.swift
    └── Views/
        ├── ContentView.swift
        ├── DashboardView.swift
        ├── SMSView.swift
        ├── CallsView.swift
        ├── ContactsView.swift
        ├── BatteryView.swift
        ├── LocationView.swift
        ├── WOLView.swift
        ├── SettingsView.swift
        ├── MoreView.swift
        └── SharedUI.swift
```

## 功能对照（与 Web 版一致）

| 模块 | 功能 | 后端接口 |
|------|------|---------|
| 仪表盘 | 设备状态 + 电量概览 + 定位概览 + 快捷入口 | `config/query`、`battery/query`、`location/query` |
| 短信 | 发送（SIM1/2、号码、内容）+ 查询（收/发、关键字、分页） | `sms/send`、`sms/query` |
| 通话 | 查询（全部/呼入/呼出/未接、号码、分页） | `call/query` |
| 联系人 | 添加 + 查询（号码、姓名） | `contact/add`、`contact/query` |
| 电量 | level/status/health/plugged/voltage/temperature | `battery/query` |
| 定位 | 地址/经纬度/时间/供应商 + 地图 | `location/query` |
| WOL | MAC/IP/端口 → 发送唤醒包 | `wol/send` |
| 设置 | 设备 IP/端口/密钥 + 测试连接 | 本地 UserDefaults |

## 签名算法

与 Web 版 Python 实现完全一致：

1. `sign_str = "{timestamp}\n{secret_key}"`
2. `HMAC-SHA256(key=secret_key, msg=sign_str)` → 字节
3. base64 编码 → 字符串
4. URL 编码（percent encoding）→ 最终 sign

## 注意事项

- 设备为局域网 HTTP 服务，已在 `Info.plist` 中配置 `NSAppTransportSecurity → NSAllowsArbitraryLoads = YES`。
- 时间显示统一为北京时间 `yyyy-MM-dd HH:mm:ss`（`Asia/Shanghai`）。
- 电量/时间戳等字段做了宽松解码，兼容后端返回数字或字符串（如 `"85%"`、`"1700000000000"`）。
