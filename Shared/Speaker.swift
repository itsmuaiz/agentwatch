import Foundation
import AVFoundation

/// Text-to-speech helper. Toggle with `Speaker.shared.enabled`.
@MainActor
public final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    public static let shared = Speaker()

    public var enabled = false {
        didSet { UserDefaults.standard.set(enabled, forKey: "tts_enabled") }
    }

    private let synth = AVSpeechSynthesizer()

    private override init() {
        super.init()
        enabled = UserDefaults.standard.bool(forKey: "tts_enabled")
        synth.delegate = self
    }

    public func speak(_ text: String) {
        guard enabled, !text.isEmpty else { return }
        // Truncate very long responses
        let snippet = text.count > 400 ? String(text.prefix(400)) + "…" : text
        synth.stopSpeaking(at: .immediate)
        let utt = AVSpeechUtterance(string: snippet)
        utt.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utt)
    }

    public func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}
