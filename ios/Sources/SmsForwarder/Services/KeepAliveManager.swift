import AVFoundation
import Observation

// MARK: - 后台保活管理器

/// 通过播放极低音量音频保持 App 在后台持续运行
///
/// 关键点：
/// - 不能用纯静音（全零 WAV），iOS 14+ 会检测并终止后台音频权限
/// - 必须播放有实际音频信号的文件，配合极低 volume（0.01）使其不可感知
/// - 需要 Info.plist 配置 UIBackgroundModes: audio
@Observable
final class KeepAliveManager {
    static let shared = KeepAliveManager()

    /// 是否正在保活
    var isKeepingAlive: Bool = false
    /// 供调试面板查看的最后一次错误
    var lastError: String = ""
    /// 供调试面板查看的最后启动时间
    var startedAt: String = ""

    private var audioPlayer: AVAudioPlayer?
    private var wasInterrupted: Bool = false
    private var healthTimer: Timer?

    func start() {
        guard !isKeepingAlive else { return }

        // 1. 配置音频会话
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            print("[KeepAlive] audio session configured successfully")
        } catch {
            lastError = "session: \(error.localizedDescription)"
            print("[KeepAlive] ERROR: audio session config failed: \(error.localizedDescription)")
            return
        }

        // 2. 播放极低音量音频
        guard let url = keepAliveAudioURL() else {
            lastError = "wav file generation failed"
            print("[KeepAlive] ERROR: failed to create keep-alive audio file")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1   // 无限循环
            player.volume = 0.01        // 极低但非零，避免 iOS 检测静音
            guard player.prepareToPlay() else {
                lastError = "prepareToPlay returned false"
                print("[KeepAlive] ERROR: prepareToPlay failed")
                return
            }
            guard player.play() else {
                lastError = "play() returned false"
                print("[KeepAlive] ERROR: play() failed")
                return
            }
            audioPlayer = player
            isKeepingAlive = true
            lastError = ""

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            startedAt = formatter.string(from: Date())

            print("[KeepAlive] started successfully, player.isPlaying=\(player.isPlaying) duration=\(player.duration)s volume=\(player.volume)")

            registerObservers()
            startHealthCheck()
        } catch {
            lastError = "player: \(error.localizedDescription)"
            print("[KeepAlive] ERROR: AVAudioPlayer init failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isKeepingAlive = false
        unregisterObservers()
        print("[KeepAlive] stopped")
    }

    // MARK: - 健康检查

    /// 每 30 秒检查播放器是否还在播放，如果停了就重启
    private func startHealthCheck() {
        healthTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self, self.isKeepingAlive else { return }
            guard let player = self.audioPlayer else { return }
            if !player.isPlaying {
                print("[KeepAlive] player stopped unexpectedly, restarting")
                _ = player.play()
            }
        }
    }

    // MARK: - 音频文件

    /// 极低音量 WAV 文件（1 秒 200Hz 正弦波，振幅 ~1000/32767）
    /// 使用不同文件名避免复用旧版纯静音文件
    private func keepAliveAudioURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("smsf_keepalive_v2.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let data = Self.keepAliveWavData(seconds: 1)
        do {
            try data.write(to: url)
            print("[KeepAlive] generated keep-alive WAV: \(data.count) bytes")
            return url
        } catch {
            print("[KeepAlive] ERROR: failed to write WAV: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 中断 & 路由变化监听

    private func registerObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance()
        )
    }

    private func unregisterObservers() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            wasInterrupted = true
            print("[KeepAlive] audio interrupted (began)")
        case .ended:
            print("[KeepAlive] audio interruption ended, resuming")
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
            if wasInterrupted {
                wasInterrupted = false
                _ = audioPlayer?.play()
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            // 耳机拔出等，iOS 会暂停播放，需要恢复
            print("[KeepAlive] route change: old device unavailable, resuming playback")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                _ = self?.audioPlayer?.play()
            }
        default:
            break
        }
    }

    // MARK: - WAV 生成

    /// 生成 1 秒低振幅正弦波 PCM WAV（44100Hz / 16bit / mono）
    /// 振幅 ~1000/32767（约 3%），配合 volume=0.01 实际输出约 0.03%，完全不可感知
    static func keepAliveWavData(seconds: Int) -> Data {
        let sampleRate = 44100
        let channels = 1
        let bitsPerSample = 16
        let numSamples = sampleRate * channels * seconds
        let dataBytes = numSamples * bitsPerSample / 8

        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        func str(_ s: String) { d.append(s.data(using: .ascii)!) }

        str("RIFF"); u32(UInt32(36 + dataBytes)); str("WAVE")
        str("fmt "); u32(16); u16(1)                              // PCM
        u16(UInt16(channels)); u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * channels * bitsPerSample / 8))   // byte rate
        u16(UInt16(channels * bitsPerSample / 8))                 // block align
        u16(UInt16(bitsPerSample))
        str("data"); u32(UInt32(dataBytes))

        // 200Hz 正弦波，振幅 1000（非零，iOS 不会检测为静音）
        let frequency = 200.0
        let amplitude = 1000.0
        for i in 0..<numSamples {
            let sample = Int16(amplitude * sin(2.0 * .pi * frequency * Double(i) / Double(sampleRate)))
            var s = sample.littleEndian
            d.append(Data(bytes: &s, count: 2))
        }
        return d
    }
}
