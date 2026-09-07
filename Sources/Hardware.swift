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

    static func services() -> [Service] {
        var records = [DDCDisplay](repeating: DDCDisplay(), count: 16)
        let count = DDCEnumerate(&records, records.count)
        guard count > 0 else { return [] }
        return records.prefix(Int(count)).compactMap { item in
            var record = item
            let bytes = withUnsafeBytes(of: &record.edid) { Array($0.prefix(Int(min(record.edidLength, 4096)))) }
            guard let edid = EDIDInfo(bytes: bytes) else { return nil }
            let path = withUnsafeBytes(of: &record.registryPath) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return Service(id: record.registryID, path: path, edid: edid)
        }
    }

    static func service(for display: DisplayInfo) -> Service? {
        let matches = services().filter { $0.edid.vendor == display.vendor && $0.edid.product == display.product && $0.edid.serial == display.serial }
        return matches.count == 1 ? matches[0] : nil
    }

    static func feature(_ handle: OpaquePointer, _ code: UInt8) -> VCPFeature {
        let value = DDCGetVCP(handle, code)
        return VCPFeature(code: code, current: value.current, maximum: value.maximum, type: value.type, status: String(cString: DDCStatusName(value.status)))
    }

    static func probe(_ display: DisplayInfo, deep: Bool, progress: ((Int) -> Void)? = nil) -> MonitorProbe {
        var result = MonitorProbe(display: display, fullScan: deep)
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
            result.features.append(feature(handle, code))
            progress?(index + 1)
        }
        let readable = result.features.filter(\.isReadable).count
        result.note = readable > 0 ? "\(readable) readable hardware features." : "The monitor did not return usable DDC values. Software dimming and macOS display modes remain available."
        result.scannedAt = Date()
        return result
    }

    static func write(_ display: DisplayInfo, feature: VCPFeature, value: UInt16) -> (VCPFeature?, String) {
        guard let service = service(for: display), let handle = DDCOpen(service.id) else { return (nil, "The display connection changed. Rescan before trying again.") }
        defer { DDCClose(handle) }
        let status = DDCSetVCP(handle, feature.code, value)
        guard status == DDC_OK else { return (nil, "Could not send \(feature.name): \(String(cString: DDCStatusName(status))).") }
        return verifyWrite(feature: feature, value: value) { self.feature(handle, feature.code) }
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
