import CoreAudio
import Foundation

/// A microphone the user can pick in Settings.
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// Core Audio device UID — stable across reboots and reconnections.
    let uid: String
    let name: String
    let isDefault: Bool

    var id: String { uid }
}

/// Core Audio device queries. Plain HAL property reads: cheap, thread-safe, no side effects
/// (they never open a device, so they don't light the microphone indicator).
enum AudioDevices {
    /// Every input-capable device, default first.
    static func inputDevices() -> [AudioInputDevice] {
        let defaultID = defaultInputDeviceID()
        let devices = allDeviceIDs().compactMap { id -> AudioInputDevice? in
            guard hasInput(id), let uid = uid(of: id) else { return nil }
            return AudioInputDevice(uid: uid, name: name(of: id) ?? uid, isDefault: id == defaultID)
        }
        return devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// The device to record from: the one with `uid` if it's still connected and has inputs,
    /// otherwise the system default input.
    static func resolveInputDevice(uid: String?) -> AudioDeviceID? {
        if let uid {
            if let id = allDeviceIDs().first(where: { self.uid(of: $0) == uid }), hasInput(id) {
                return id
            }
            Log.audio.notice("input device \(uid, privacy: .public) is gone; using the system default")
        }
        return defaultInputDeviceID()
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    static func name(of id: AudioDeviceID) -> String? {
        stringProperty(kAudioObjectPropertyName, of: id)
    }

    // MARK: - HAL helpers

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// A device can record if it exposes at least one input stream.
    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func uid(of id: AudioDeviceID) -> String? {
        stringProperty(kAudioDevicePropertyDeviceUID, of: id)
    }

    /// Reads a CFString property. The HAL returns these at +1, hence `takeRetainedValue`.
    private static func stringProperty(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
