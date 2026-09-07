import Foundation

/// Advertised monitor data, not a guarantee that macOS or the cable can use it.
struct EDIDInfo: Codable {
    let vendor: UInt32
    let product: UInt32
    let serial: UInt32
    var name: String
    let manufacturer: String
    let manufactureYear: Int
    let manufactureWeek: Int
    let isModelYear: Bool
    let version: String
    let widthCM: Int
    let heightCM: Int
    let aspectRatio: Double?
    let gamma: Double?
    let digital: Bool
    let interface: String
    let bitsPerColor: Int?
    let extensionCount: Int
    let checksumValid: Bool
    let hex: String
    let chromaticity: [String: Double]
    var serialText = ""
    var descriptorText: [String] = []
    var preferredTiming: String?
    var preferredWidth: Int?
    var preferredHeight: Int?
    var detailedTimings: [String] = []
    var standardTimings: [String] = []
    var rangeLimits: String?
    var colorFormats: [String] = []
    var audio: [String] = []
    var hdr = "Not advertised in parsed CTA blocks"
    var extensions: [String] = []
    var warnings: [String] = []

    var summary: String {
        ["\(manufacturer) · EDID \(version)", preferredTiming,
         widthCM > 0 && heightCM > 0 ? "\(widthCM) × \(heightCM) cm" : nil,
         bitsPerColor.map { "\($0)-bit advertised" }].compactMap { $0 }.joined(separator: " · ")
    }

    init?(bytes b: [UInt8]) {
        guard b.count >= 128, Array(b.prefix(8)) == [0, 255, 255, 255, 255, 255, 255, 0] else { return nil }
        let vendorCode = UInt32(b[8]) << 8 | UInt32(b[9])
        vendor = vendorCode
        product = UInt32(b[10]) | UInt32(b[11]) << 8
        serial = (0..<4).reduce(0) { $0 | UInt32(b[12 + $1]) << (8 * $1) }
        manufacturer = [10, 5, 0].map { shift in
            let n = Int((vendorCode >> shift) & 31)
            return n >= 1 && n <= 26 ? String(UnicodeScalar(n + 64)!) : "?"
        }.joined()
        name = manufacturer + " Display"
        manufactureWeek = Int(b[16])
        manufactureYear = 1990 + Int(b[17])
        isModelYear = b[16] == 255 && b[18] == 1 && b[19] >= 4
        version = "\(b[18]).\(b[19])"
        widthCM = b[22] == 0 ? 0 : Int(b[21])
        heightCM = b[21] == 0 ? 0 : Int(b[22])
        gamma = b[23] == 255 ? nil : (Double(b[23]) + 100) / 100
        digital = b[20] & 0x80 != 0
        let modern = b[18] == 1 && b[19] >= 4
        aspectRatio = widthCM > 0 && heightCM > 0 ? Double(widthCM) / Double(heightCM)
            : modern && b[21] > 0 ? (Double(b[21]) + 99) / 100
            : modern && b[22] > 0 ? 100 / (Double(b[22]) + 99) : nil
        interface = !digital ? "Analog" : modern
            ? ([0: "Digital, unspecified", 1: "DVI", 2: "HDMI-A", 3: "HDMI-B", 4: "MDDI", 5: "DisplayPort"][Int(b[20] & 15)] ?? "Digital, reserved interface")
            : "Digital, interface unspecified"
        let depthCode = Int((b[20] >> 4) & 7)
        bitsPerColor = digital && modern && (1...6).contains(depthCode) ? depthCode * 2 + 4 : nil
        extensionCount = Int(b[126])
        let presentBlocks = min(b.count / 128, extensionCount + 1)
        let validBlocks = (0..<presentBlocks).map { block in
            b[(block * 128)..<((block + 1) * 128)].reduce(0) { ($0 + Int($1)) & 255 } == 0
        }
        checksumValid = presentBlocks == extensionCount + 1 && validBlocks.allSatisfy { $0 }
        hex = b.map { String(format: "%02X", $0) }.joined()
        chromaticity = Dictionary(uniqueKeysWithValues: ["redX", "redY", "greenX", "greenY", "blueX", "blueY", "whiteX", "whiteY"].enumerated().map { i, key in
            let low = Int(b[25 + i / 4] >> (6 - (i % 4) * 2)) & 3
            return (key, Double(Int(b[27 + i]) * 4 + low) / 1024)
        })
        for (block, valid) in validBlocks.enumerated() where !valid { warnings.append("Invalid checksum in EDID block \(block); its decoded values may be unreliable.") }
        if presentBlocks < extensionCount + 1 { warnings.append("EDID declares \(extensionCount) extension(s), but only \(presentBlocks - 1) complete extension(s) were supplied.") }
        if b.count % 128 != 0 { warnings.append("Trailing partial EDID block ignored during decoding; retained in hex.") }
        if b.count / 128 > extensionCount + 1 { warnings.append("Undeclared extra blocks retained in hex, not decoded.") }
        if digital {
            colorFormats = ["RGB"]
            if modern && b[24] & 0x08 != 0 { colorFormats.append("YCbCr 4:4:4") }
            if modern && b[24] & 0x10 != 0 { colorFormats.append("YCbCr 4:2:2") }
        }
        for offset in stride(from: 38, to: 54, by: 2) where b[offset] != 0 && !(b[offset] == 1 && b[offset + 1] == 1) {
            let width = (Int(b[offset]) + 31) * 8
            let aspect = Int(b[offset + 1] >> 6)
            let height = aspect == 0 ? (b[18] == 1 && b[19] < 3 ? width : width * 10 / 16)
                : aspect == 1 ? width * 3 / 4 : aspect == 2 ? width * 4 / 5 : width * 9 / 16
            standardTimings.append("\(width) × \(height) @ \(Int(b[offset + 1] & 63) + 60) Hz")
        }
        for offset in stride(from: 54, to: 126, by: 18) {
            let d = Array(b[offset..<(offset + 18)])
            if let timing = Self.timing(d) {
                detailedTimings.append(timing)
                if offset == 54 && b[24] & 2 != 0 {
                    preferredTiming = timing
                    preferredWidth = Int(d[2]) | Int(d[4] & 0xF0) << 4
                    preferredHeight = (Int(d[5]) | Int(d[7] & 0xF0) << 4) * (d[17] & 0x80 != 0 ? 2 : 1)
                }
            } else if d[0] == 0 && d[1] == 0 && d[2] == 0 {
                let textBytes = d[5..<18].prefix { $0 != 10 && $0 != 0 }.filter { $0 >= 32 && $0 < 127 }
                let text = String(bytes: textBytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
                switch d[3] {
                case 0xFC: if !text.isEmpty { name = text }
                case 0xFF: serialText = text
                case 0xFE: if !text.isEmpty { descriptorText.append(text) }
                case 0xFD:
                    let offsets = modern ? Int(d[4]) : 0
                    let limits = (0..<4).map { Int(d[5 + $0]) + (offsets & (1 << $0) == 0 ? 0 : 255) }
                    rangeLimits = "\(limits[0])–\(limits[1]) Hz vertical; \(limits[2])–\(limits[3]) kHz horizontal"
                    if d[9] != 0 { rangeLimits! += "; \(Int(d[9]) * 10) MHz maximum pixel clock (rounded)" }
                default: break
                }
            }
        }
        var hdrModes: [String] = []
        for index in 1..<presentBlocks {
            let block = Array(b[(index * 128)..<((index + 1) * 128)])
            let tag = block[0]
            extensions.append(tag == 2 ? "CTA-861 revision \(block[1])" : tag == 0x70 ? "DisplayID (retained, not decoded)" : String(format: "Extension 0x%02X (retained, not decoded)", tag))
            guard tag == 2 else { continue }
            if block[3] & 0x40 != 0 { audio.append("Basic audio: two-channel LPCM, 32/44.1/48 kHz") }
            if block[3] & 0x20 != 0 { colorFormats.append("YCbCr 4:4:4") }
            if block[3] & 0x10 != 0 { colorFormats.append("YCbCr 4:2:2") }
            let end = Int(block[2])
            guard end != 0 else { continue }
            guard end >= 4 && end <= 127 else { warnings.append("Invalid CTA data offset in block \(index).") ; continue }
            var offset = 4
            while offset < end {
                let length = Int(block[offset] & 31)
                let kind = block[offset] >> 5
                guard offset + 1 + length <= end else { warnings.append("Truncated CTA data record in block \(index).") ; break }
                let data = Array(block[(offset + 1)..<(offset + 1 + length)])
                if kind == 1 {
                    if length % 3 != 0 { warnings.append("Incomplete CTA audio descriptor in block \(index).") }
                    for start in stride(from: 0, to: length - length % 3, by: 3) {
                        let code = Int((data[start] >> 3) & 15)
                        let format = [1: "LPCM", 2: "AC-3", 3: "MPEG-1", 4: "MP3", 5: "MPEG-2", 6: "AAC LC", 7: "DTS", 8: "ATRAC", 9: "DSD", 10: "E-AC-3", 11: "DTS-HD", 12: "MLP", 13: "DST", 14: "WMA Pro"][code] ?? "Audio format \(code)"
                        let rates = ["32", "44.1", "48", "88.2", "96", "176.4", "192"].enumerated().filter { data[start + 1] & (1 << $0.offset) != 0 }.map { $0.element }
                        audio.append("\(format), up to \(Int(data[start] & 7) + 1) channels, \(rates.joined(separator: "/")) kHz")
                    }
                } else if kind == 7 && data.first == 6 {
                    if length >= 3 {
                        for (bit, label) in ["Traditional SDR", "Traditional HDR", "PQ (ST 2084)", "HLG"].enumerated() where data[1] & (1 << bit) != 0 { hdrModes.append(label) }
                        if data[2] & 1 != 0 { hdrModes.append("Static metadata type 1") }
                    } else { warnings.append("Truncated CTA HDR descriptor in block \(index).") }
                }
                offset += length + 1
            }
            if end <= 109 {
                for offset in stride(from: end, through: 109, by: 18) {
                    if let timing = Self.timing(Array(block[offset..<(offset + 18)])) { detailedTimings.append(timing) }
                }
            }
        }
        colorFormats = Array(Set(colorFormats)).sorted()
        audio = Array(Set(audio)).sorted()
        if !hdrModes.isEmpty { hdr = Array(Set(hdrModes)).sorted().joined(separator: ", ") + " (advertised)" }
    }

    private static func timing(_ d: [UInt8]) -> String? {
        let clock = (Int(d[0]) | Int(d[1]) << 8) * 10_000
        guard clock > 0 else { return nil }
        let width = Int(d[2]) | Int(d[4] & 0xF0) << 4
        let hblank = Int(d[3]) | Int(d[4] & 15) << 8
        let height = Int(d[5]) | Int(d[7] & 0xF0) << 4
        let vblank = Int(d[6]) | Int(d[7] & 15) << 8
        guard width > 0, height > 0, hblank > 0, vblank > 0 else { return nil }
        let interlaced = d[17] & 0x80 != 0
        let refresh = Double(clock) / (Double(width + hblank) * (Double(height + vblank) + (interlaced ? 0.5 : 0)))
        return String(format: "%d × %d @ %.2f Hz%@ · %.2f MHz", width, interlaced ? height * 2 : height, refresh, interlaced ? " interlaced (field rate)" : "", Double(clock) / 1_000_000)
    }
}
