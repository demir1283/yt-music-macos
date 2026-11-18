import Foundation
import CoreAudio
import Observation

/// The Mac's audio outputs (built-in speakers, Bluetooth, USB, a monitor's HDMI or
/// DisplayPort speakers…) and the one YT Music plays to.
///
/// No choice (`chosenUID == nil`) follows the system output, the one Control Center sets.
/// A chosen device only changes where YT Music plays, not the system output, and is
/// remembered across launches. While it is unplugged the app follows the system output and
/// goes back to it as soon as it is connected again. AirPlay receivers are not listed here:
/// they are picked in the system AirPlay menu (`AirPlayButton`).
@MainActor @Observable
final class AudioOutputs {
    static let shared = AudioOutputs()

    enum Kind {
        case builtIn, bluetooth, usb, display, other

        var symbol: String {
            switch self {
            case .builtIn: "laptopcomputer"
            case .bluetooth: "hifispeaker"
            case .usb: "cable.connector"
            case .display: "display"
            case .other: "speaker.wave.2"
            }
        }
    }

    struct Device: Identifiable, Equatable {
        let uid: String
        let name: String
        let kind: Kind
        var id: String { uid }
    }

    private(set) var devices: [Device] = []
    /// Name of the current system output, shown beside "System output".
    private(set) var systemName = ""
    /// The remembered choice, which may be unplugged right now.
    private(set) var chosenUID: String? = UserDefaults.standard.string(forKey: uidKey)
    /// Its name, so an unplugged choice can still be named.
    private(set) var chosenName: String? = UserDefaults.standard.string(forKey: nameKey)

    /// The device actually played to: the choice while it is connected, otherwise nil
    /// (the system output).
    var activeUID: String? {
        guard let uid = chosenUID, devices.contains(where: { $0.uid == uid }) else { return nil }
        return uid
    }

    /// Called whenever `activeUID` changes, to move the players to it.
    @ObservationIgnored var onChange: ((String?) -> Void)?

    private static let uidKey = "audioOutputUID"
    private static let nameKey = "audioOutputName"
    @ObservationIgnored private var listening = false

    private init() {}

    /// Reads the device list once and then keeps it current: CoreAudio calls back when a
    /// device comes or goes, or the system output changes. Nothing polls.
    func start() {
        guard !listening else { return }
        listening = true
        refresh()
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
                Task { @MainActor in AudioOutputs.shared.refresh() }
            }
        }
    }

    /// nil = follow the system output.
    func choose(_ device: Device?) {
        let before = activeUID
        chosenUID = device?.uid
        chosenName = device?.name
        let defaults = UserDefaults.standard
        if let device {
            defaults.set(device.uid, forKey: Self.uidKey)
            defaults.set(device.name, forKey: Self.nameKey)
        } else {
            defaults.removeObject(forKey: Self.uidKey)
            defaults.removeObject(forKey: Self.nameKey)
        }
        if activeUID != before { onChange?(activeUID) }
    }

    private func refresh() {
        let before = activeUID
        devices = Self.outputDevices()
        systemName = Self.defaultOutput().flatMap { Self.string($0, kAudioObjectPropertyName) } ?? ""
        if activeUID != before { onChange?(activeUID) }
    }

    // MARK: CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func outputDevices() -> [Device] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = ids.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, buffer.baseAddress!)
        }
        guard status == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutput(id), uint32(id, kAudioDevicePropertyIsHidden) != 1,
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            let transport = uint32(id, kAudioDevicePropertyTransportType) ?? 0
            // AirPlay has its own menu; the system's private aggregates are not real outputs.
            if transport == kAudioDeviceTransportTypeAirPlay || uid.hasPrefix("CADefaultDeviceAggregate") { return nil }
            let kind: Kind
            switch transport {
            case kAudioDeviceTransportTypeBuiltIn: kind = .builtIn
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: kind = .bluetooth
            case kAudioDeviceTransportTypeUSB: kind = .usb
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: kind = .display
            default: kind = .other
            }
            return Device(uid: uid, name: name, kind: kind)
        }
    }

    private static func defaultOutput() -> AudioObjectID? {
        uint32(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
            .map { AudioObjectID($0) }
    }

    /// A device can play when it has at least one output stream.
    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
