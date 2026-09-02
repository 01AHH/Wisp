import AVFoundation
import CoreAudio
import Foundation

/// Input devices on this Mac, and which one Wisp should use.
enum AudioDevices {
    struct Device: Equatable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    /// Fires on the main queue whenever devices appear/disappear or the default changes.
    static var onChange: (() -> Void)?

    static func startWatching() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var addr = AudioObjectPropertyAddress(mSelector: selector,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(system, &addr, .main) { _, _ in onChange?() }
        }
    }

    /// All devices that can record, in system order.
    static func inputs() -> [Device] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputStreamCount(id) > 0, let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return Device(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? "Microphone")
        }
    }

    static func systemDefault() -> Device? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return Device(id: id, uid: string(id, kAudioDevicePropertyDeviceUID) ?? "",
                      name: string(id, kAudioObjectPropertyName) ?? "Microphone")
    }

    /// The device Wisp will record from: the chosen one if it's plugged in, else the system default.
    static func selected() -> Device? {
        let uid = Settings.microphoneUID
        if !uid.isEmpty, let match = inputs().first(where: { $0.uid == uid }) { return match }
        return systemDefault()
    }

    /// The AVCaptureDevice to record from (its uniqueID is the CoreAudio UID).
    static func captureDevice() -> AVCaptureDevice? {
        let uid = Settings.microphoneUID
        if !uid.isEmpty, let device = AVCaptureDevice(uniqueID: uid) { return device }
        return AVCaptureDevice.default(for: .audio)
    }

    // MARK: property helpers

    private static func inputStreamCount(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                              mScope: kAudioObjectPropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let cf = value?.takeRetainedValue() else { return nil }
        return cf as String
    }
}
