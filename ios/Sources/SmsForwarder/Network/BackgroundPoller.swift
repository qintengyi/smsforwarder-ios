import Foundation
import Observation

// MARK: - 后台短信轮询器

/// 当 WebSocket 在后台不可靠时，改用 HTTP 轮询获取最新短信
/// 依赖 location 后台保活维持 App 运行，让异步任务在后台正常工作
@Observable
final class BackgroundPoller {
    static let shared = BackgroundPoller()

    var isPolling: Bool = false
    var lastPollTime: String = ""
    var pollCount: Int = 0

    private var pollTask: Task<Void, Never>?
    /// 每个设备已知的最大 date 时间戳，用于去重
    private var lastMaxDate: [Int: Int64] = [:]
    private let settingsStore = SettingsStore.shared

    /// 收到新短信回调：(deviceId, deviceName, sms)
    var onSMS: ((Int, String, WSSmsRecord) -> Void)?

    func start() {
        guard !isPolling else { return }
        isPolling = true
        print("[Poller] started")
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func stop() {
        isPolling = false
        pollTask?.cancel()
        pollTask = nil
        print("[Poller] stopped")
    }

    // MARK: - 轮询循环

    private func pollLoop() async {
        // 首次立即轮询一次
        await pollOnce()
        while isPolling && !Task.isCancelled {
            // 间隔 5 秒
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard isPolling, !Task.isCancelled else { break }
            await pollOnce()
        }
    }

    /// 单次轮询（可供 KeepAliveManager 在位置唤醒时调用）
    func pollOnce() async {
        let settings = settingsStore.settings
        guard settings.isLoggedIn, let token = settings.token, !token.isEmpty else { return }

        let deviceIds = Array(RuleStore.shared.subscribedDeviceIds)
        guard !deviceIds.isEmpty else { return }

        // 并发轮询所有设备
        await withTaskGroup(of: Void.self) { group in
            for deviceId in deviceIds {
                group.addTask { [weak self] in
                    await self?.pollDevice(deviceId: deviceId, serverURL: settings.serverURL, token: token)
                }
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        lastPollTime = formatter.string(from: Date())
        pollCount += 1
        print("[Poller] poll #\(pollCount) completed at \(lastPollTime)")
    }

    // MARK: - 轮询单个设备

    private func pollDevice(deviceId: Int, serverURL: String, token: String) async {
        guard let url = buildPollURL(serverURL: serverURL, deviceId: deviceId) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        // type=1 收件箱，page_size=10 取最新 10 条
        let body: [String: Any] = ["type": 1, "page_num": 1, "page_size": 10, "keyword": ""]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                print("[Poller] device \(deviceId) HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let smsArray = extractSmsArray(json: json)
            guard !smsArray.isEmpty else { return }

            let deviceName = DeviceStore.shared.devices.first { $0.id == deviceId }?.name ?? "设备\(deviceId)"

            let prevMax = lastMaxDate[deviceId] ?? 0
            var newMax = prevMax
            var newSMSList: [(Int64, [String: Any])] = []

            for smsJson in smsArray {
                // date 兼容数字或字符串
                let date: Int64
                if let n = smsJson["date"] as? NSNumber {
                    date = n.int64Value
                } else if let i = smsJson["date"] as? Int {
                    date = Int64(i)
                } else if let s = smsJson["date"] as? String, let parsed = Int64(s) {
                    date = parsed
                } else {
                    continue
                }

                if date > newMax { newMax = date }
                if date > prevMax && prevMax > 0 {
                    newSMSList.append((date, smsJson))
                }
            }

            // 按时间升序处理新短信
            newSMSList.sort { $0.0 < $1.0 }

            for (_, smsJson) in newSMSList {
                let sms = WSSmsRecord(
                    name: smsJson["name"] as? String,
                    number: smsJson["number"] as? String,
                    content: smsJson["content"] as? String
                )
                print("[Poller] new SMS: device=\(deviceId) content=\(String((sms.content ?? "").prefix(60)))")
                await MainActor.run {
                    self.onSMS?(deviceId, deviceName, sms)
                }
            }

            if prevMax == 0 {
                print("[Poller] device \(deviceId) initialized baseline, maxDate=\(newMax)")
            } else if !newSMSList.isEmpty {
                print("[Poller] device \(deviceId) found \(newSMSList.count) new SMS, prevMax=\(prevMax) newMax=\(newMax)")
            }

            lastMaxDate[deviceId] = newMax
        } catch {
            print("[Poller] device \(deviceId) error: \(error.localizedDescription)")
        }
    }

    // MARK: - 响应解析

    /// 兼容多种响应格式：data 为数组 / data.list 为数组 / 顶层为数组
    private func extractSmsArray(json: [String: Any]) -> [[String: Any]] {
        if let arr = json["data"] as? [[String: Any]] { return arr }
        if let dataObj = json["data"] as? [String: Any], let arr = dataObj["list"] as? [[String: Any]] { return arr }
        if let arr = json["list"] as? [[String: Any]] { return arr }
        return []
    }

    // MARK: - URL 构建

    private func buildPollURL(serverURL: String, deviceId: Int) -> URL? {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s.removeLast() }
        return URL(string: "\(s)/api/device/\(deviceId)/proxy/sms/query")
    }
}
