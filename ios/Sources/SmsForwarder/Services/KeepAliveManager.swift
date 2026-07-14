import AVFoundation
import Observation

// MARK: - 后台保活管理器

/// 通过播放静音音频保持 App 在后台持续运行，使 WebSocket 能持续接收短信
/// 需要 Info.plist 配置 UIBackgroundModes: audio
@Observable
final class KeepAliveManager {
    static let shared = KeepAliveManager()

    var isKeepingAlive: Bool = false

    private var audioPlayer: AVAudioPlayer?

    func start() {
        guard !isKeepingAlive else { return }
        configureAudioSession()
        guard playSilence() else { return }
        isKeepingAlive = true
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isKeepingAlive = false
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // playback + mixWithOthers：静音播放不打断用户正在听的音乐
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func playSilence() -> Bool {
        guard let url = silenceURL() else { return false }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1   // 无限循环
            player.volume = 0
            return player.play()
        } catch {
            return false
        }
    }

    /// 静音 WAV 文件（1 秒），首次生成后复用
    private func silenceURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("smsf_silence.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let data = Self.silenceWavData(seconds: 1)
        try? data.write(to: url)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 生成 1 秒静音 PCM WAV（44100Hz / 16bit / mono）
    static func silenceWavData(seconds: Int) -> Data {
        let sampleRate = 44100
        let channels = 1
        let bitsPerSample = 16
        let dataBytes = sampleRate * channels * bitsPerSample / 8 * seconds

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
        d.append(Data(count: dataBytes))                          // 全零 = 静音
        return d
    }
}
