import AudioToolbox
import Foundation

// MARK: - Sound Service
// Light "嘟" cues for recording start/stop. Uses AudioServices system sound
// IDs (no lifetime/retain issues, thread-safe). Played start-before-engine and
// stop-after-engine so the mic doesn't capture the beep.

enum SoundService {

    // Pop = soft low cue for start; Tink = light high cue for stop.
    private static let startID: SystemSoundID = makeSound("Pop")
    private static let stopID: SystemSoundID = makeSound("Tink")

    private static func makeSound(_ name: String) -> SystemSoundID {
        var id: SystemSoundID = 0
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        AudioServicesCreateSystemSoundID(url as CFURL, &id)
        return id
    }

    static func playStart() { AudioServicesPlaySystemSound(startID) }
    static func playStop()  { AudioServicesPlaySystemSound(stopID) }
}
