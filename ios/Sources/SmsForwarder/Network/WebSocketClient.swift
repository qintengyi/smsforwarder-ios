import Foundation
import Observation

// MARK: - WebSocket 收到的短信记录

struct WSSmsRecord: Decodable {
    let name: String?
    let number: String?
    let content: String?
}

// MARK: - WebSocket 客户端

/// 连接面板 /api/ws，接收实时短信推送
@Observable
final class WebSocketClient {
    static let shared = WebSocketClient()

    var isConnected: Bool = false
    var lastError: String?
    var connectCount: Int = 0
    var lastReceivedSMSContent: String = ""
    var lastReceivedSMSTime: String = ""

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private var reconnectAttempts: Int = 0
    private var shouldRun: Bool = false
    private let settingsStore = SettingsStore.shared

    /// 连接代次（每次 connect() 递增），用于识别过期的回调
    private var generation: Int = 0

    /// 收到匹配设备的短信回调：(deviceId, deviceName, sms)
    var onSMS: ((Int, String, WSSmsRecord) -> Void)?

    // MARK: - 连接管理

    func start() {
        shouldRun = true
        // 已连接则不重复连接，避免连接次数无谓增长
        guard !isConnected else { return }
        if Thread.isMainThread {
            connect()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.connect()
            }
        }
    }

    func stop() {
        shouldRun = false
        if Thread.isMainThread {
            teardown()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.teardown()
            }
        }
    }

    private func teardown() {
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
    }

    /// 必须在主线程调用
    private func connect() {
        assert(Thread.isMainThread, "connect() must be on main thread")
        guard shouldRun else { return }
        let settings = settingsStore.settings
        guard settings.isLoggedIn, let token = settings.token, !token.isEmpty else { return }
        guard let url = buildWSURL(serverURL: settings.serverURL, token: token) else { return }

        teardown()
        generation += 1
        let gen = generation

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        isConnected = true
        reconnectAttempts = 0
        connectCount += 1
        lastError = nil

        receiveLoop(generation: gen)
        startPing()

        // 连接建立后立即订阅（URLSessionWebSocketTask 会排队消息，等连接就绪后发送）
        subscribeAll()
    }

    private func reconnect() {
        guard shouldRun else { return }
        reconnectAttempts += 1
        let delay = min(2.0 * Double(reconnectAttempts), 15.0)
        let attempts = reconnectAttempts
        print("[WSClient] reconnect in \(delay)s (attempt \(attempts))")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            // 再次检查 shouldRun，避免 stop 后又重连
            guard self.shouldRun else { return }
            self.connect()
        }
    }

    // MARK: - URL 构建

    /// https://host → wss://host/api/ws?token=xxx
    private func buildWSURL(serverURL: String, token: String) -> URL? {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("http://") { s = "ws://" + s.dropFirst(7) }
        else if s.hasPrefix("https://") { s = "wss://" + s.dropFirst(8) }
        else if !s.hasPrefix("ws://") && !s.hasPrefix("wss://") { s = "wss://" + s }
        if s.hasSuffix("/") { s.removeLast() }
        let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        s += "/api/ws?token=\(encoded)"
        return URL(string: s)
    }

    // MARK: - 接收循环

    /// 带代次标记的接收循环，过期回调不会触发重连
    private func receiveLoop(generation gen: Int) {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            // 切到主线程处理，确保 generation 检查安全
            DispatchQueue.main.async {
                // 如果代次不匹配，说明这是旧连接的回调，忽略
                guard self.generation == gen else {
                    print("[WSClient] stale receive callback (gen \(gen), current \(self.generation)), ignoring")
                    return
                }
                switch result {
                case .failure(let error):
                    self.isConnected = false
                    // 主动断开（stop() 被调用）时不设置 lastError 也不重连，
                    // 避免 iOS 后台强制中断的 "Software caused connection abort" 暴露给用户
                    if self.shouldRun {
                        self.lastError = error.localizedDescription
                        print("[WSClient] receive error: \(error.localizedDescription)")
                        self.reconnect()
                    } else {
                        print("[WSClient] connection closed by stop(), ignoring error")
                    }
                case .success(let msg):
                    switch msg {
                    case .data(let data):
                        self.handleData(data)
                    case .string(let str):
                        if let data = str.data(using: .utf8) {
                            self.handleData(data)
                        }
                    @unknown default:
                        break
                    }
                    self.receiveLoop(generation: gen)
                }
            }
        }
    }

    private func handleData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = json["type"] as? String ?? ""
        switch type {
        case "sms":
            let deviceId = (json["device_id"] as? NSNumber)?.intValue
                ?? (json["device_id"] as? Int) ?? 0
            let deviceName = json["device_name"] as? String ?? ""
            guard deviceId > 0, let smsJson = json["sms"] else { return }
            guard let smsData = try? JSONSerialization.data(withJSONObject: smsJson),
                  let sms = try? JSONDecoder().decode(WSSmsRecord.self, from: smsData) else { return }
            print("[WSClient] received SMS: device=\(deviceId) name=\(deviceName) content=\(String((sms.content ?? "").prefix(60)))")
            self.lastReceivedSMSContent = String((sms.content ?? "").prefix(100))
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            self.lastReceivedSMSTime = formatter.string(from: Date())
            self.onSMS?(deviceId, deviceName, sms)
        case "ack":
            // 订阅确认，记录但不处理
            if let ok = json["ok"] as? Bool, let devId = json["device_id"] as? NSNumber {
                print("[WSClient] subscribe ack: device=\(devId.intValue) ok=\(ok)")
            }
        case "pong":
            break
        default:
            print("[WSClient] unknown message type: \(type)")
        }
    }

    // MARK: - 订阅

    func subscribeAll() {
        let ids = RuleStore.shared.subscribedDeviceIds
        print("[WSClient] subscribeAll: deviceIds = \(ids.map { String($0) }.joined(separator: ","))")
        for id in ids { subscribe(deviceId: id) }
    }

    func subscribe(deviceId: Int) {
        send(["action": "subscribe", "device_id": deviceId])
    }

    func unsubscribe(deviceId: Int) {
        send(["action": "unsubscribe", "device_id": deviceId])
    }

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { error in
            if let error = error {
                print("[WSClient] send error: \(error.localizedDescription)")
            }
        }
    }

    private func startPing() {
        pingTimer?.invalidate()
        // Timer 必须在主线程创建才能在主 RunLoop 上调度
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.send(["action": "ping"])
        }
    }
}
