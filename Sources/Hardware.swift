import AppKit
import Foundation

struct MonitorProbe: Codable {
    var display: DisplayInfo
    var registryID: UInt64?
    var registryPath: String?
    var edid: EDIDInfo?
    var capabilities = ""
    var capabilitiesStatus = "unavailable"
    var features: [VCPFeature] = []
    var note = ""
    var scannedAt = Date()
    var fullScan = false
}

enum Hardware {
    static let queue = DispatchQueue(label: "MonitorBar.hardware", qos: .userInitiated)
    // An app's own bundle identifier is not a separate defaults suite.
    static let commandPreferences = Bundle.main.bundleIdentifier == "local.monitorbar.app"
        ? UserDefaults.standard : UserDefaults(suiteName: "local.monitorbar.app") ?? .standard
    static let pauseKey = "hardwareCommandsPaused"
    static let pauseReasonKey = "hardwarePauseReason"
    static let pauseMessage = "Hardware controls paused for all monitors. DDC reads and writes are disabled."
    static var hardwareCommandsPaused: Bool { commandsPaused(in: commandPreferences) }
    static let samsungControlCodes: [UInt8] = [0x10, 0x12, 0x87, 0x16, 0x18, 0x1A, 0x62]
    static let samsungPictureModeChoices: [(UInt16, String)] = [
        (0, "Entertain"), (1, "Graphic"), (2, "Eco"), (3, "Game Standard"), (4, "RPG"),
        (5, "RTS"), (6, "FPS"), (7, "Sports"), (8, "Original"), (9, "Custom")
    ]
    private static var samsungConnections: [String: DDCHDMIConnection] = [:]
    private static let samsungLock = NSLock()

    static func samsungEnableKey(_ display: DisplayInfo) -> String { "samsungHardwareEnabled.\(display.identity)" }
    static func samsungPictureModeEnableKey(_ display: DisplayInfo) -> String { "samsungPictureModeEnabled.\(display.identity)" }

    static func canUseSamsungControls(_ display: DisplayInfo, preferences: UserDefaults = commandPreferences) -> Bool {
        guard preferences.synchronize() else { return false }
        guard display.isSamsungG91SD,
              let value = preferences.object(forKey: samsungEnableKey(display)) as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return value.boolValue
    }

    static func canUseSamsungPictureMode(_ display: DisplayInfo, preferences: UserDefaults = commandPreferences) -> Bool {
        guard canUseSamsungControls(display, preferences: preferences),
              let value = preferences.object(forKey: samsungPictureModeEnableKey(display)) as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return value.boolValue
    }

    static func isValidSamsungPictureMode(_ feature: VCPFeature) -> Bool {
        feature.code == 0x2D && feature.isReadable && feature.type == 0 && feature.maximum == 10 && feature.current <= 9
    }

    static func pauseReason(in preferences: UserDefaults = commandPreferences) -> String? {
        preferences.synchronize()
        return preferences.string(forKey: pauseReasonKey)
    }

    static func pauseAfterFault(_ reason: String, preferences: UserDefaults = commandPreferences) {
        preferences.set(reason, forKey: pauseReasonKey)
        preferences.set(true, forKey: pauseKey)
        preferences.synchronize()
    }

    static func resetSamsungSession() {
        samsungLock.lock()
        defer { samsungLock.unlock() }
        samsungConnections.removeAll()
    }

    static func validateSamsungConnection(previous: DDCHDMIConnection?, current: DDCHDMIConnection?,
                                           pause: (String) -> Void = { pauseAfterFault($0) }) -> Bool {
        guard var previous else { return current != nil }
        if var current, DDCHDMIConnectionsMatch(&previous, &current) == 1 { return true }
        pause("The Samsung HDMI connection changed. Hardware controls were paused; explicitly resume to check the new connection.")
        return false
    }

    static func commandsPaused(in preferences: UserDefaults) -> Bool {
        guard preferences.synchronize() else { return true }
        guard let value = preferences.object(forKey: pauseKey) else { return false }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return true }
        return number.boolValue
    }

    @MainActor static func displays() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            guard CGDisplayIsBuiltin(id) == 0 else { return nil }
            var modes = (CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode]) ?? []
            let size = CGDisplayScreenSize(id)
            let current = CGDisplayCopyDisplayMode(id)
            let currentID = current?.ioDisplayModeID ?? -1
            if let current, !modes.contains(where: { $0.ioDisplayModeID == currentID }) { modes.append(current) }
            let sorted = modes.sorted {
                if $0.ioDisplayModeID == $1.ioDisplayModeID { return false }
                if $0.ioDisplayModeID == currentID { return true }
                if $1.ioDisplayModeID == currentID { return false }
                if $0.width * $0.height != $1.width * $1.height { return $0.width * $0.height > $1.width * $1.height }
                if $0.refreshRate != $1.refreshRate { return $0.refreshRate > $1.refreshRate }
                return $0.ioDisplayModeID < $1.ioDisplayModeID
            }.map { DisplayModeInfo(id: $0.ioDisplayModeID, width: $0.width, height: $0.height, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight, refreshRate: $0.refreshRate, ioFlags: $0.ioFlags, isDesktopUsable: $0.isUsableForDesktopGUI()) }
            return DisplayInfo(id: id, name: screen.localizedName, vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id), builtIn: false, widthMM: size.width, heightMM: size.height, rotation: CGDisplayRotation(id), currentModeID: currentID, modes: sorted)
        }
    }

    struct Service {
        let id: UInt64
        let path: String
        let edid: EDIDInfo
    }

    private static func activeExternalIDs() -> [CGDirectDisplayID]? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success, count <= ids.count else { return nil }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }
    }

    private static func cachedSamsungConnection(_ display: DisplayInfo) -> DDCHDMIConnection? {
        guard display.isSamsungG91SD, activeExternalIDs() == [display.id],
              CGDisplayVendorNumber(display.id) == display.vendor,
              CGDisplayModelNumber(display.id) == display.product,
              CGDisplaySerialNumber(display.id) == display.serial else { return nil }
        var connection = DDCHDMIConnection()
        guard DDCCopyCachedHDMIConnection(&connection) == 1,
              let service = service(from: connection.display),
              service.edid.vendor == display.vendor, service.edid.product == display.product,
              service.edid.serial == display.serial,
              activeExternalIDs() == [display.id] else { return nil }
        return connection
    }

    private static func service(from item: DDCDisplay) -> Service? {
        var record = item
        let bytes = withUnsafeBytes(of: &record.edid) { Array($0.prefix(Int(min(record.edidLength, 4096)))) }
        guard let edid = EDIDInfo(bytes: bytes) else { return nil }
        let path = withUnsafeBytes(of: &record.registryPath) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return Service(id: record.registryID, path: path, edid: edid)
    }

    static func services() -> [Service] {
        guard !hardwareCommandsPaused else { return [] }
        // The generic enumerator reads every proxy's EDID. Never route a Samsung
        // through that discovery path, including in a mixed-monitor setup.
        guard let ids = activeExternalIDs(), !ids.contains(where: {
            CGDisplayVendorNumber($0) == 0x4C2D && CGDisplayModelNumber($0) == 0x778D
        }) else { return [] }
        var records = [DDCDisplay](repeating: DDCDisplay(), count: 16)
        let count = DDCEnumerate(&records, records.count)
        guard count > 0 else { return [] }
        return records.prefix(Int(count)).compactMap { service(from: $0) }
    }

    static func service(for display: DisplayInfo) -> Service? {
        if display.isSamsungG91SD {
            guard !hardwareCommandsPaused, canUseSamsungControls(display),
                  let connection = cachedSamsungConnection(display) else { return nil }
            return service(from: connection.display)
        }
        let matches = services().filter { $0.edid.vendor == display.vendor && $0.edid.product == display.product && $0.edid.serial == display.serial }
        return matches.count == 1 ? matches[0] : nil
    }

    static func feature(_ handle: OpaquePointer, _ code: UInt8) -> VCPFeature {
        guard !hardwareCommandsPaused else { return VCPFeature(code: code, current: 0, maximum: 0, type: 0, status: "paused") }
        let value = DDCGetVCP(handle, code)
        return VCPFeature(code: code, current: value.current, maximum: value.maximum, type: value.type, status: String(cString: DDCStatusName(value.status)))
    }

    static func probe(_ display: DisplayInfo, deep: Bool, progress: ((Int) -> Void)? = nil) -> MonitorProbe {
        if display.isSamsungG91SD { return probeSamsung(display, progress: progress) }
        var result = MonitorProbe(display: display, fullScan: deep)
        guard !hardwareCommandsPaused else {
            result.note = pauseMessage
            return result
        }
        guard let service = service(for: display) else {
            result.note = "No uniquely matching DDC connection. Check the cable and the monitor’s DDC/CI setting."
            return result
        }
        result.registryID = service.id
        result.registryPath = service.path
        result.edid = service.edid
        guard let handle = DDCOpen(service.id) else {
            result.note = "The monitor was identified, but its DDC connection could not be opened."
            return result
        }
        defer { DDCClose(handle) }
        var buffer = [CChar](repeating: 0, count: 16384)
        result.capabilitiesStatus = String(cString: DDCStatusName(DDCCapabilities(handle, &buffer, buffer.count)))
        result.capabilities = String(cString: buffer)
        let advertised = Capabilities.features(result.capabilities)
        let codes = deep ? Array(UInt8.min...UInt8.max) : Array(Set(advertised.keys).union([0x10, 0x12, 0x14, 0x16, 0x18, 0x1A, 0x60, 0x62, 0x6C, 0x6E, 0x70, 0x87, 0x8D, 0xC9, 0xD6, 0xDF])).sorted()
        for (index, code) in codes.enumerated() {
            guard !hardwareCommandsPaused else {
                result.features = []
                result.note = pauseMessage
                return result
            }
            result.features.append(feature(handle, code))
            progress?(index + 1)
        }
        let readable = result.features.filter(\.isReadable).count
        result.note = readable > 0 ? "\(readable) readable hardware features." : "The monitor did not return usable DDC values. Software dimming and macOS display modes remain available."
        result.scannedAt = Date()
        return result
    }

    static func write(_ display: DisplayInfo, feature: VCPFeature, value: UInt16) -> (VCPFeature?, String) {
        guard !hardwareCommandsPaused else { return (nil, pauseMessage) }
        if display.isSamsungG91SD { return writeSamsung(display, feature: feature, value: value) }
        guard let service = service(for: display), let handle = DDCOpen(service.id) else { return (nil, "The display connection changed. Rescan before trying again.") }
        defer { DDCClose(handle) }
        let status = DDCSetVCP(handle, feature.code, value)
        guard status == DDC_OK else { return (nil, "Could not send \(feature.name): \(String(cString: DDCStatusName(status))).") }
        return verifyWrite(feature: feature, value: value) { self.feature(handle, feature.code) }
    }

    private static func samsungSession(_ handle: OpaquePointer) -> SamsungSession {
        SamsungSession(read: { DDCGetVCPOnce(handle, $0, 0) }, send: { DDCSetVCP(handle, $0, $1) },
                       isPaused: { hardwareCommandsPaused }, pause: { pauseAfterFault($0) })
    }

    private static func probeSamsung(_ display: DisplayInfo, progress: ((Int) -> Void)?) -> MonitorProbe {
        samsungLock.lock()
        defer { samsungLock.unlock() }
        var result = MonitorProbe(display: display)
        guard !hardwareCommandsPaused else { result.note = pauseReason() ?? pauseMessage; return result }
        guard canUseSamsungControls(display) else {
            result.note = "Hardware controls have not been verified and enabled for this Samsung display."
            return result
        }
        let cached = cachedSamsungConnection(display)
        guard validateSamsungConnection(previous: samsungConnections[display.identity], current: cached),
              var connection = cached, let service = service(from: connection.display) else {
            result.note = pauseReason() ?? "Samsung controls require the Samsung as the only external display and one uniquely matching active HDMI connection."
            return result
        }
        result.registryID = service.id
        result.registryPath = service.path
        result.edid = service.edid
        guard let handle = DDCOpen(service.id) else {
            pauseAfterFault("The Samsung HDMI control connection could not be opened. Hardware controls were paused.")
            result.note = pauseReason() ?? pauseMessage
            return result
        }
        defer { DDCClose(handle) }
        guard DDCGuardHDMIConnection(handle, &connection) == 1 else {
            result.note = pauseReason() ?? pauseMessage
            return result
        }
        let session = samsungSession(handle)
        result.features = session.scan(includePictureMode: canUseSamsungPictureMode(display), progress: progress)
        if hardwareCommandsPaused || session.fault != nil {
            result.features = []
            result.note = pauseReason() ?? session.fault ?? pauseMessage
            return result
        }
        samsungConnections[display.identity] = connection
        result.capabilitiesStatus = "not requested"
        result.note = "\(result.features.filter(\.isReadable).count) verified Samsung hardware controls."
        result.scannedAt = Date()
        return result
    }

    private static func writeSamsung(_ display: DisplayInfo, feature: VCPFeature, value: UInt16) -> (VCPFeature?, String) {
        samsungLock.lock()
        defer { samsungLock.unlock() }
        guard !hardwareCommandsPaused else { return (nil, pauseReason() ?? pauseMessage) }
        guard canUseSamsungControls(display) else { return (nil, "Hardware controls are not enabled for this Samsung display.") }
        let pictureMode = feature.code == 0x2D
        let allowed = pictureMode
            ? canUseSamsungPictureMode(display) && isValidSamsungPictureMode(feature) && value <= 9
            : samsungControlCodes.contains(feature.code) && feature.isSlider && value <= feature.maximum
        guard allowed else {
            return (nil, "This Samsung control or value is not supported.")
        }
        guard var connection = samsungConnections[display.identity] else { return (nil, "Rescan this Samsung display before changing a control.") }
        guard cachedSamsungConnection(display) != nil, let handle = DDCOpen(connection.display.registryID) else {
            pauseAfterFault("The Samsung HDMI connection changed. Hardware controls were paused; rescan after reconnecting.")
            return (nil, pauseReason() ?? pauseMessage)
        }
        defer { DDCClose(handle) }
        guard DDCGuardHDMIConnection(handle, &connection) == 1 else { return (nil, pauseReason() ?? pauseMessage) }
        let session = samsungSession(handle)
        return pictureMode ? session.writePictureMode(feature: feature, value: value) : session.write(feature: feature, value: value)
    }

    // Injected operations keep the complete Samsung request budget testable offline.
    final class SamsungSession {
        let read: (UInt8) -> DDCValue
        let send: (UInt8, UInt16) -> DDCStatus
        let isPaused: () -> Bool
        let pause: (String) -> Void
        let wait: () -> Void
        private(set) var fault: String?

        init(read: @escaping (UInt8) -> DDCValue, send: @escaping (UInt8, UInt16) -> DDCStatus,
             isPaused: @escaping () -> Bool, pause: @escaping (String) -> Void,
             wait: @escaping () -> Void = { Thread.sleep(forTimeInterval: 0.15) }) {
            self.read = read; self.send = send; self.isPaused = isPaused; self.pause = pause; self.wait = wait
        }

        private func fail(_ reason: String) {
            guard fault == nil else { return }
            fault = reason
            pause(reason)
        }

        func feature(_ code: UInt8) -> VCPFeature {
            guard samsungControlCodes.contains(code) else {
                return VCPFeature(code: code, current: 0, maximum: 0, type: 0, status: "unsupported")
            }
            var result = readFeature(code)
            if result.isReadable && (result.type != 0 || result.maximum == 0 || result.current > result.maximum) {
                result.status = "unavailable"
            }
            return result
        }

        private func readFeature(_ code: UInt8) -> VCPFeature {
            var result = VCPFeature(code: code, current: 0, maximum: 0, type: 0, status: "paused")
            guard !isPaused(), fault == nil else { return result }
            wait()
            guard !isPaused(), fault == nil else { return result }
            let value = read(code)
            result = VCPFeature(code: code, current: value.current, maximum: value.maximum,
                                type: value.type, status: String(cString: DDCStatusName(value.status)))
            guard !isPaused() else { result.status = "paused"; return result }
            if value.status == DDC_UNSUPPORTED { return result }
            guard value.status == DDC_OK, value.ioReturn == 0 else {
                fail("Samsung \(result.name) read failed (\(result.status), I/O \(value.ioReturn)). Hardware controls were paused.")
                return result
            }
            return result
        }

        private func pcInputAvailable() -> Bool {
            let input = readFeature(0xE4)
            return input.isReadable && input.type == 0 && input.current == 0
        }

        private func pictureModeFeature() -> VCPFeature {
            var mode = readFeature(0x2D)
            if mode.isReadable && !isValidSamsungPictureMode(mode) { mode.status = "unavailable" }
            return mode
        }

        func scan(includePictureMode: Bool = false, progress: ((Int) -> Void)? = nil) -> [VCPFeature] {
            var features: [VCPFeature] = []
            for (index, code) in samsungControlCodes.enumerated() {
                guard !isPaused(), fault == nil else { return [] }
                features.append(feature(code))
                progress?(index + 1)
            }
            if includePictureMode && !isPaused() && fault == nil {
                let pc = pcInputAvailable()
                progress?(8)
                if pc && !isPaused() && fault == nil {
                    features.append(pictureModeFeature())
                    progress?(9)
                } else {
                    features.append(VCPFeature(code: 0x2D, current: 0, maximum: 0, type: 0, status: "unavailable"))
                }
            }
            return isPaused() || fault != nil ? [] : features
        }

        func writePictureMode(feature original: VCPFeature, value: UInt16) -> (VCPFeature?, String) {
            guard isValidSamsungPictureMode(original), value <= 9 else {
                return (nil, "This Samsung Picture Mode has not been validated for PC input.")
            }
            guard pcInputAvailable() else {
                if isPaused() || fault != nil { return (nil, fault ?? pauseReason() ?? pauseMessage) }
                var unavailable = original
                unavailable.status = "unavailable"
                return (unavailable, "Picture Mode requires a verified PC input; nothing was written.")
            }
            let before = pictureModeFeature()
            guard !isPaused(), fault == nil else { return (nil, fault ?? pauseReason() ?? pauseMessage) }
            guard isValidSamsungPictureMode(before) else {
                return (before, "Picture Mode is currently unavailable; nothing was written.")
            }
            if before.current == value { return (before, "Picture Mode confirmed: \(value).") }
            guard before.current == original.current else {
                return (before, "Picture Mode changed on the monitor to \(before.current). Review the refreshed value; nothing was written.")
            }
            wait()
            guard !isPaused() else { return (nil, pauseReason() ?? pauseMessage) }
            let sent = send(0x2D, value)
            guard !isPaused() else { return (nil, pauseReason() ?? pauseMessage) }
            guard sent == DDC_OK else {
                fail("Samsung Picture Mode write failed (\(String(cString: DDCStatusName(sent)))). Hardware controls were paused.")
                return (nil, fault!)
            }
            // Presets get the validated 250 ms settling interval, including readFeature's 150 ms wait.
            Thread.sleep(forTimeInterval: 0.1)
            let after = pictureModeFeature()
            guard !isPaused(), fault == nil else { return (nil, fault ?? pauseReason() ?? pauseMessage) }
            guard isValidSamsungPictureMode(after), after.current == value else {
                fail("Samsung Picture Mode reported \(after.current)/\(after.maximum) (\(after.status)) after requesting \(value). Hardware controls were paused because the change was not confirmed.")
                return (after, fault!)
            }
            return (after, "Picture Mode confirmed: \(value).")
        }

        func write(feature original: VCPFeature, value: UInt16) -> (VCPFeature?, String) {
            guard samsungControlCodes.contains(original.code), original.isSlider, value <= original.maximum else {
                return (nil, "This Samsung control or value is not supported.")
            }
            let before = feature(original.code)
            guard !isPaused(), fault == nil else { return (nil, fault ?? pauseReason() ?? pauseMessage) }
            guard before.isSlider, value <= before.maximum else {
                return (before, "\(before.name) is currently unavailable or outside the monitor’s reported range.")
            }
            if before.current == value { return (before, "\(before.name) confirmed: \(value).") }
            guard before.current == original.current, before.maximum == original.maximum else {
                return (before, "\(before.name) changed on the monitor to \(before.current)/\(before.maximum). Review the refreshed value before trying again; nothing was written.")
            }
            wait()
            guard !isPaused() else { return (nil, pauseReason() ?? pauseMessage) }
            let sent = send(original.code, value)
            guard !isPaused() else { return (nil, pauseReason() ?? pauseMessage) }
            guard sent == DDC_OK else {
                fail("Samsung \(before.name) write failed (\(String(cString: DDCStatusName(sent)))). Hardware controls were paused.")
                return (nil, fault!)
            }
            let after = feature(original.code)
            guard !isPaused(), fault == nil else { return (nil, fault ?? pauseReason() ?? pauseMessage) }
            guard after.isSlider, after.current == value, after.maximum == before.maximum else {
                fail("Samsung \(after.name) reported \(after.current)/\(after.maximum) (\(after.status)) after requesting \(value). Hardware controls were paused because the change was not confirmed.")
                return (after, fault!)
            }
            return (after, "\(after.name) confirmed: \(value).")
        }
    }

    static func verifyWrite(feature: VCPFeature, value: UInt16, read: () -> VCPFeature) -> (VCPFeature?, String) {
        var lastReadable: VCPFeature?
        for delay in [0.0, 0.1, 0.2] {
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            let readback = read()
            guard readback.isReadable else { continue }
            lastReadable = readback
            if readback.current == value { return (readback, "\(feature.name) confirmed: \(value).") }
        }
        guard let readback = lastReadable else { return (nil, "\(feature.name) was sent; the monitor did not confirm it. Input or power changes can disconnect DDC.") }
        return (readback, "The monitor last reported \(readback.current) after requesting \(value) for \(feature.name); the change was not confirmed.")
    }
}

enum Capabilities {
    static func features(_ text: String) -> [UInt8: [UInt16]] {
        guard let start = text.range(of: "vcp(", options: .caseInsensitive),
              start.lowerBound == text.startIndex || text[text.index(before: start.lowerBound)] == ")" || text[text.index(before: start.lowerBound)].isWhitespace || text[text.index(before: start.lowerBound)] == "(" else { return [:] }
        let body = Array(text[start.upperBound...])
        var index = 0
        var result: [UInt8: [UInt16]] = [:]
        func skipSpace() { while index < body.count && body[index].isWhitespace { index += 1 } }
        func token() -> String {
            let begin = index
            while index < body.count && !body[index].isWhitespace && body[index] != "(" && body[index] != ")" { index += 1 }
            return String(body[begin..<index])
        }
        while index < body.count {
            skipSpace()
            guard index < body.count else { return [:] }
            if body[index] == ")" { return result }
            let raw = token()
            guard raw.count == 2, let code = UInt8(raw, radix: 16), result[code] == nil else { return [:] }
            skipSpace()
            var values: [UInt16] = []
            if index < body.count && body[index] == "(" {
                index += 1
                while index < body.count {
                    skipSpace()
                    guard index < body.count else { return [:] }
                    if body[index] == ")" { break }
                    let rawValue = token()
                    guard (rawValue.count == 2 || rawValue.count == 4), let value = UInt16(rawValue, radix: 16) else { return [:] }
                    values.append(value)
                }
                guard index < body.count && body[index] == ")" else { return [:] }
                index += 1
            }
            result[code] = values
        }
        return [:]
    }
}
