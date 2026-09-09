import AppKit
import SwiftUI

struct DisplayModeInfo: Identifiable, Codable, Hashable {
    let id: Int32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    var ioFlags: UInt32 = 3
    var isDesktopUsable: Bool = true
    var isHiDPI: Bool {
        width > 0 && height > 0 && pixelWidth > width && pixelHeight > height &&
        abs(Double(pixelWidth) / Double(width) - Double(pixelHeight) / Double(height)) < 0.01
    }
    var isNative: Bool { ioFlags & 0x02000000 != 0 }
    var isSelectable: Bool {
        width > 0 && height > 0 && pixelWidth > 0 && pixelHeight > 0 &&
        refreshRate.isFinite && refreshRate >= 0 &&
        ioFlags & 3 == 3 && ioFlags & (0x80 | 0x800 | 0x1000 | 0x40) == 0 &&
        (isDesktopUsable || isNative)
    }
    var aspectLabel: String { Self.aspect(width: width, height: height) }
    var pixelLabel: String { "\(pixelWidth) × \(pixelHeight) pixels" }
    var scaleLabel: String { isHiDPI ? String(format: "%.3g× HiDPI", Double(pixelWidth) / Double(width)) : "Standard 1×" }
    var resolution: DisplaySize { DisplaySize(width: width, height: height) }
    var renderingSize: DisplaySize { DisplaySize(width: pixelWidth, height: pixelHeight) }
    var scalingChoiceLabel: String {
        renderingSize == resolution ? "Standard" : (isHiDPI ? scaleLabel : renderingSize.label + " pixels")
    }
    var refreshLabel: String {
        guard refreshRate.isFinite, refreshRate > 0 else { return "Unspecified" }
        return refreshRate.formatted(.number.precision(.fractionLength(0...3))) + " Hz"
    }
    static func aspect(width: Int, height: Int) -> String {
        guard width > 0 && height > 0 else { return "Unknown aspect" }
        if abs(Double(width) / Double(height) - 1.6) < 0.002 { return "16:10" }
        var a = width, b = height
        while b != 0 { (a, b) = (b, a % b) }
        return "\(width / a):\(height / a)"
    }
    var label: String {
        "\(width) × \(height) · \(scaleLabel)" +
        (refreshRate > 0 ? String(format: " · %.2f Hz", refreshRate) : "")
    }
}

struct DisplaySize: Hashable {
    let width: Int
    let height: Int
    var label: String { "\(width) × \(height)" }
}

/// Menus describe existing modes; choosing a field never constructs a new timing.
struct DisplayModeOptions {
    let display: DisplayInfo
    var availableModes: [DisplayModeInfo] { display.modes.filter(\.isSelectable) }
    private var visibleModes: [DisplayModeInfo] {
        display.modes.filter { $0.isSelectable || $0.id == display.currentModeID }
    }
    var resolutions: [DisplaySize] {
        Set(visibleModes.map(\.resolution)).sorted {
            $0.width == $1.width ? $0.height > $1.height : $0.width > $1.width
        }
    }
    func renderingSizes(for resolution: DisplaySize) -> [DisplaySize] {
        Set(visibleModes.filter { $0.resolution == resolution }.map(\.renderingSize)).sorted {
            $0.width == $1.width ? $0.height < $1.height : $0.width < $1.width
        }
    }
    func refreshModes(for mode: DisplayModeInfo) -> [DisplayModeInfo] {
        let matches = visibleModes.filter {
            $0.resolution == mode.resolution && $0.renderingSize == mode.renderingSize &&
            $0.refreshRate.isFinite && $0.refreshRate >= 0
        }
        return Set(matches.map(\.refreshRate)).sorted(by: >).compactMap { rate in
            preferredMode(resolution: mode.resolution, rendering: mode.renderingSize, rate: rate, near: mode)
                ?? matches.first { $0.id == display.currentModeID && $0.refreshRate == rate }
        }
    }
    func refreshLabel(for mode: DisplayModeInfo) -> String {
        let sameLabel = refreshModes(for: mode).filter { $0.refreshLabel == mode.refreshLabel }
        return sameLabel.count > 1 ? "\(mode.refreshRate) Hz" : mode.refreshLabel
    }
    func scalingLabel(for mode: DisplayModeInfo) -> String {
        let sameLabel = visibleModes.filter {
            $0.resolution == mode.resolution && $0.scalingChoiceLabel == mode.scalingChoiceLabel
        }
        return Set(sameLabel.map(\.renderingSize)).count > 1
            ? "\(mode.scalingChoiceLabel) · \(mode.renderingSize.label)" : mode.scalingChoiceLabel
    }
    func preferredMode(resolution: DisplaySize, rendering: DisplaySize? = nil,
                       rate: Double? = nil, near reference: DisplayModeInfo) -> DisplayModeInfo? {
        let candidates = availableModes.filter {
            $0.resolution == resolution && (rendering == nil || $0.renderingSize == rendering) &&
            (rate == nil || $0.refreshRate == rate)
        }
        // Preserve scaling and refresh rate where possible. Keep the selected or
        // active ID when macOS returns several flag variants of the same mode.
        return candidates.min { lhs, rhs in
            let leftScale = scaleDistance(lhs, reference), rightScale = scaleDistance(rhs, reference)
            if leftScale != rightScale { return leftScale < rightScale }
            let leftRate = rateDistance(lhs.refreshRate, reference.refreshRate)
            let rightRate = rateDistance(rhs.refreshRate, reference.refreshRate)
            if leftRate != rightRate { return leftRate < rightRate }
            if (lhs.id == reference.id) != (rhs.id == reference.id) { return lhs.id == reference.id }
            if (lhs.id == display.currentModeID) != (rhs.id == display.currentModeID) { return lhs.id == display.currentModeID }
            if lhs.isNative != rhs.isNative { return lhs.isNative }
            if lhs.refreshRate != rhs.refreshRate { return lhs.refreshRate > rhs.refreshRate }
            return lhs.id < rhs.id
        }
    }
    private func scaleDistance(_ mode: DisplayModeInfo, _ reference: DisplayModeInfo) -> Double {
        guard reference.width > 0, reference.height > 0 else { return 0 }
        return abs(Double(mode.pixelWidth) / Double(mode.width) - Double(reference.pixelWidth) / Double(reference.width)) +
            abs(Double(mode.pixelHeight) / Double(mode.height) - Double(reference.pixelHeight) / Double(reference.height))
    }
    private func rateDistance(_ rate: Double, _ reference: Double) -> Double {
        if rate == reference { return 0 }
        // A missing rate is not 0 Hz and should not win a closest-rate comparison.
        guard rate > 0, reference.isFinite, reference > 0 else { return .infinity }
        return abs(rate - reference)
    }
}

struct DisplayInfo: Identifiable, Codable {
    let id: UInt32
    let name: String
    let vendor: UInt32
    let product: UInt32
    let serial: UInt32
    let builtIn: Bool
    let widthMM: Double
    let heightMM: Double
    let rotation: Double
    let currentModeID: Int32
    let modes: [DisplayModeInfo]
    var identity: String { String(format: "%04X:%04X · Serial %u", vendor, product, serial) }
    var isSamsungG91SD: Bool { !builtIn && vendor == 0x4C2D && product == 0x778D }
    var currentMode: DisplayModeInfo? { modes.first { $0.id == currentModeID } }
    var selectableModes: [DisplayModeInfo] {
        var seen = Set<String>()
        return modes.filter { mode in
            guard mode.isSelectable || mode.id == currentModeID else { return false }
            let key = "\(mode.width):\(mode.height):\(mode.pixelWidth):\(mode.pixelHeight):\(mode.refreshRate):\(mode.ioFlags):\(mode.isDesktopUsable)"
            return seen.insert(key).inserted
        }
    }
}

struct VCPFeature: Identifiable, Codable {
    let code: UInt8
    var current: UInt16
    let maximum: UInt16
    let type: UInt8
    var status: String
    var id: UInt8 { code }
    var hex: String { String(format: "0x%02X", code) }
    var name: String { Self.names[code] ?? "Feature \(hex)" }
    var isReadable: Bool { status == "ok" }
    var isSlider: Bool { [0x0C, 0x10, 0x12, 0x16, 0x18, 0x1A, 0x62, 0x6C, 0x6E, 0x70, 0x87].contains(code) && isReadable && maximum > 0 && current <= maximum && type == 0 }
    var choices: [(UInt16, String)] {
        switch code {
        case 0x14: return [(1,"sRGB"),(2,"Native color"),(4,"5000 K"),(5,"6500 K"),(6,"7500 K"),(8,"9300 K"),(11,"User color")]
        case 0x60: return [(1,"VGA"),(3,"DVI 1"),(4,"DVI 2"),(15,"DisplayPort 1"),(16,"DisplayPort 2"),(17,"HDMI 1"),(18,"HDMI 2")]
        case 0x8D: return [(1,"Muted"),(2,"Unmuted")]
        case 0xCC: return [(1,"繁體中文"),(2,"English"),(3,"Français"),(4,"Deutsch"),(6,"日本語"),(10,"Español"),(13,"简体中文")]
        case 0xD6: return [(1,"On"),(4,"Off / standby")]
        default: return []
        }
    }
    static let names: [UInt8: String] = [
        0x02:"New control value", 0x04:"Restore defaults", 0x05:"Restore brightness / contrast", 0x06:"Restore geometry", 0x08:"Restore color defaults",
        0x0B:"Color temperature increment", 0x0C:"Color temperature", 0x10:"Brightness", 0x12:"Contrast", 0x14:"Color preset",
        0x16:"Red gain", 0x18:"Green gain", 0x1A:"Blue gain", 0x1E:"Auto setup", 0x20:"Horizontal position", 0x2D:"Picture Mode", 0x30:"Vertical position", 0x52:"Active control", 0x60:"Input source", 0x62:"Volume",
        0x6C:"Red black level", 0x6E:"Green black level", 0x70:"Blue black level", 0x87:"Sharpness", 0x8D:"Audio mute",
        0xAC:"Horizontal frequency", 0xAE:"Vertical frequency", 0xB2:"Subpixel layout", 0xB6:"Display technology",
        0xC0:"Usage time", 0xC6:"Application enable", 0xC8:"Controller type", 0xC9:"Firmware version", 0xCA:"OSD control",
        0xCC:"OSD language", 0xD6:"Power mode", 0xDC:"Display preset", 0xDF:"MCCS version"
    ]
}
