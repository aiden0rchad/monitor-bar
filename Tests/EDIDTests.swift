import Foundation

@main
struct EDIDTests {
    static func checksum(_ bytes: inout [UInt8], block: Int = 0) {
        let start = block * 128
        bytes[start + 127] = 0
        bytes[start + 127] = UInt8((256 - bytes[start..<(start + 127)].reduce(0) { ($0 + Int($1)) & 255 }) & 255)
    }

    static func base() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes.replaceSubrange(0..<8, with: [0, 255, 255, 255, 255, 255, 255, 0])
        bytes[8] = 0x09; bytes[9] = 0xE5 // Example BOE vendor; identity and timing below are synthetic.
        bytes[10] = 0x34; bytes[11] = 0x12
        bytes.replaceSubrange(12..<16, with: [0x78, 0x56, 0x34, 0x12])
        bytes[16] = 10; bytes[17] = 34; bytes[18] = 1; bytes[19] = 4
        bytes[20] = 0xA5; bytes[21] = 34; bytes[22] = 19; bytes[23] = 120; bytes[24] = 2
        bytes.replaceSubrange(38..<54, with: [UInt8](repeating: 1, count: 16))
        // 1920x1080p60: 148.5 MHz / (2200 * 1125).
        bytes.replaceSubrange(54..<72, with: [0x02, 0x3A, 0x80, 0x18, 0x71, 0x38, 0x2D, 0x40, 0x58, 0x2C, 0x45, 0, 0, 0, 0, 0, 0, 0x1E])
        bytes[75] = 0xFC
        bytes.replaceSubrange(77..<85, with: Array("Display\n".utf8))
        checksum(&bytes)
        return bytes
    }

    static func main() throws {
        assert(EDIDInfo(bytes: []) == nil)
        assert(EDIDInfo(bytes: [UInt8](repeating: 0, count: 128)) == nil)
        var bytes = base()
        let info = EDIDInfo(bytes: bytes)!
        assert(info.manufacturer == "BOE" && info.vendor == 0x09E5)
        assert(info.product == 0x1234 && info.serial == 0x12345678 && info.name == "Display")
        assert(info.checksumValid && info.version == "1.4" && info.gamma == 2.2)
        assert(info.interface == "DisplayPort" && info.bitsPerColor == 8)
        assert(info.preferredTiming == "1920 × 1080 @ 60.00 Hz · 148.50 MHz")
        assert(info.preferredWidth == 1920 && info.preferredHeight == 1080)
        assert(info.standardTimings.isEmpty && info.audio.isEmpty)
        let decoded = try JSONDecoder().decode(EDIDInfo.self, from: JSONEncoder().encode(info))
        assert(decoded.hex == info.hex && decoded.summary == info.summary)

        bytes[16] = 255; bytes[22] = 0; bytes[21] = 79
        let ratio = EDIDInfo(bytes: bytes)!
        assert(ratio.isModelYear && ratio.widthCM == 0 && ratio.heightCM == 0 && ratio.aspectRatio == 1.78)
        bytes = base(); bytes[19] = 3
        assert(EDIDInfo(bytes: bytes)!.bitsPerColor == nil && EDIDInfo(bytes: bytes)!.interface == "Digital, interface unspecified")
        bytes = base(); bytes[54] = 0x01; bytes[55] = 0x1D
        bytes[59] = 0x1C; bytes[60] = 0x16; bytes[61] = 0x20; bytes[71] |= 0x80
        assert(EDIDInfo(bytes: bytes)!.preferredTiming == "1920 × 1080 @ 60.00 Hz interlaced (field rate) · 74.25 MHz")
        assert(EDIDInfo(bytes: bytes)!.preferredWidth == 1920 && EDIDInfo(bytes: bytes)!.preferredHeight == 1080)
        bytes[24] &= 0xFD
        assert(EDIDInfo(bytes: bytes)!.preferredTiming == nil)
        assert(EDIDInfo(bytes: bytes)!.preferredWidth == nil && EDIDInfo(bytes: bytes)!.preferredHeight == nil)

        bytes = base()
        bytes[23] = 255
        assert(EDIDInfo(bytes: bytes)!.gamma == nil && !EDIDInfo(bytes: bytes)!.checksumValid)
        bytes = base(); bytes[126] = 2; checksum(&bytes)
        assert(!EDIDInfo(bytes: bytes)!.checksumValid && EDIDInfo(bytes: bytes)!.warnings.count == 1)

        bytes = base(); bytes[126] = 1
        bytes += [UInt8](repeating: 0, count: 128)
        bytes.replaceSubrange(128..<143, with: [2, 3, 15, 0x70, 0xE3, 6, 0x0D, 1, 0x23, 0x09, 7, 7, 0, 0, 0])
        checksum(&bytes); checksum(&bytes, block: 1)
        let cta = EDIDInfo(bytes: bytes)!
        assert(cta.checksumValid && cta.hdr.contains("PQ") && cta.hdr.contains("HLG"))
        assert(cta.audio.count == 2 && cta.audio.contains { $0.contains("LPCM, up to 2 channels") })
        assert(cta.colorFormats == ["RGB", "YCbCr 4:2:2", "YCbCr 4:4:4"])

        bytes[130] = 5; checksum(&bytes, block: 1)
        let truncated = EDIDInfo(bytes: bytes)!
        assert(truncated.warnings.contains { $0.contains("Truncated CTA") })
        assert(!truncated.hdr.contains("PQ"))
        bytes[130] = 255; checksum(&bytes, block: 1)
        assert(EDIDInfo(bytes: bytes)!.warnings.contains { $0.contains("Invalid CTA data offset") })
        bytes[130] = 0; checksum(&bytes, block: 1)
        assert(EDIDInfo(bytes: bytes)!.hdr == "Not advertised in parsed CTA blocks")

        // Every truncation and arbitrary CTA length must stay within supplied bytes.
        for count in 0...bytes.count { _ = EDIDInfo(bytes: Array(bytes.prefix(count))) }
        for offset in 0...255 {
            bytes[130] = UInt8(offset)
            for length in 0...31 { bytes[132] = 0xE0 | UInt8(length); _ = EDIDInfo(bytes: bytes) }
        }
        print("EDID tests passed (identity, timing, checksums, JSON, CTA HDR/audio, 8,192 offset/length cases).")
    }
}
