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

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private var reconnectAttempts: Int = 0
    private var shouldRun: Bool = false
    private let settingsStore = SettingsStore.shared

    /// 收到匹配设备的短信回调：(deviceId, deviceName, sms)
    var onSMS: ((Int, String, WSSmsRecord) -> Void)?

    // MARK: - 连接管理

    func start() {
        shouldRun = true
        connect()
    }

    func stop() {
        shouldRun = false
        teardown()
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

    private func connect() {
        guard shouldRun else { return }
        let settings = settingsStore.settings
        guard settings.isLoggedIn, let token = settings.token, !token.isEmpty else { return }
        guard let url = buildWSURL(serverURL: settings.serverURL, token: token) else { return }

        teardown()

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
        receiveLoop()
        startPing()
        // 连接建立后订阅当前规则涉及的所有设备
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.subscribeAll()
        }
    }

    private func reconnect() {
        guard shouldRun else { return }
        reconnectAttempts += 1
        let delay = min(2.0 * Double(reconnectAttempts), 15.0)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
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

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                }
                self.reconnect()
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
                self.receiveLoop()
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
            DispatchQueue.main.async {
                self.onSMS?(deviceId, deviceName, sms)
            }
        case "ack", "pong":
            break
        default:
            break
        }
    }

    // MARK: - 订阅

    func subscribeAll() {
        let ids = RuleStore.shared.subscribedDeviceIds
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
        task?.send(.string(str)) { _ in }
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.send(["action": "ping"])
        }
    }
}
