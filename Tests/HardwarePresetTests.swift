import Foundation

@main struct HardwarePresetTests {
    static var checks = 0
    static let identity = "4C2D:778D · Serial 1234"

    static func check(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        checks += 1
    }

    static func rejects(_ message: String, _ operation: () throws -> Void) {
        do { try operation(); preconditionFailure(message) }
        catch { checks += 1 }
    }

    static func preset(name: String = "Everyday", identity: String = identity,
                       values: [UInt8: UInt16] = [0x10: 25], maxima: [UInt8: UInt16] = [0x10: 50]) throws -> HardwarePreset {
        try HardwarePreset(name: name, displayIdentity: identity, values: values, maxima: maxima)
    }

    static func main() throws {
        let suite = "MonitorBar.HardwarePresetTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let original = try preset(name: "  Everyday  ")
        check(original.name == "Everyday", "Names are trimmed")
        check(try HardwarePresetLibrary.load(from: preferences).isEmpty, "Missing storage is empty")
        try HardwarePresetLibrary.save([original], to: preferences)
        check(try HardwarePresetLibrary.load(from: preferences) == [original], "Values and maxima survive persistence")
        let renamed = try original.renamed(to: "Work")
        check(renamed.id == original.id && renamed.values == original.values && renamed.maxima == original.maxima,
              "Renaming preserves identity and settings")
        try HardwarePresetLibrary.save([renamed], to: preferences)
        check(try HardwarePresetLibrary.load(from: preferences) == [renamed], "Renaming is persisted")
        try HardwarePresetLibrary.save([], to: preferences)
        check(try HardwarePresetLibrary.load(from: preferences).isEmpty, "Deletion is persisted")
        let ordered = try preset(values: [0x62: 75, 0x10: 25, 0x14: 2, 0x2D: 2, 0x2F: 5],
                                 maxima: [0x62: 100, 0x10: 50, 0x14: 4, 0x2D: 10, 0x2F: 10])
        check(ordered.orderedCodes == [0x2D, 0x14, 0x10, 0x62, 0x2F], "Picture presets precede numeric controls")
        check(!HardwarePreset.orderedCodes.contains(0x0A) && !HardwarePreset.orderedCodes.contains(0x60)
              && !HardwarePreset.orderedCodes.contains(0xD6), "Eye Saver, input, and power are excluded")
        for name in ["", " \n ", String(repeating: "x", count: 65), "two\nlines", "null\u{0}name"] {
            rejects("Invalid names must fail") { _ = try preset(name: name) }
        }
        for invalid in ["", " ", " id ", "monitor\n123", String(repeating: "x", count: 257)] {
            rejects("Invalid identities must fail") { _ = try preset(identity: invalid) }
        }
        for code: UInt8 in [0x0A, 0x60, 0xD6, 0xFF] {
            rejects("Unsafe control must fail") { _ = try preset(values: [code: 1], maxima: [code: 100]) }
        }
        rejects("Empty preset must fail") { _ = try preset(values: [:], maxima: [:]) }
        rejects("Missing maximum must fail") { _ = try preset(maxima: [:]) }
        rejects("Extra maximum must fail") { _ = try preset(maxima: [0x10: 50, 0x12: 50]) }
        rejects("Out-of-range value must fail") { _ = try preset(values: [0x10: 51]) }
        rejects("Zero maximum must fail") { _ = try preset(values: [0x10: 0], maxima: [0x10: 0]) }
        for (code, value, maximum): (UInt8, UInt16, UInt16) in [(0x2D, 10, 10), (0x14, 5, 5), (0x2F, 5, 11)] {
            rejects("Unverified choice/range must fail") { _ = try preset(values: [code: value], maxima: [code: maximum]) }
        }
        rejects("Duplicate preset IDs must fail") { try HardwarePresetLibrary.save([original, original], to: preferences) }
        rejects("Names must be unique per monitor ignoring case") {
            try HardwarePresetLibrary.save([original, try preset(name: "everyday")], to: preferences)
        }
        let other = try preset(identity: "4C2D:778D · Serial 5678")
        try HardwarePresetLibrary.save([original, other], to: preferences)
        check(try HardwarePresetLibrary.load(from: preferences).count == 2, "Different monitors may reuse names")

        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        let control = (object["controls"] as! [[String: Any]])[0]
        object["controls"] = [control, control]
        let duplicate = try JSONSerialization.data(withJSONObject: object)
        rejects("Duplicate control codes must fail decoding") { _ = try JSONDecoder().decode(HardwarePreset.self, from: duplicate) }
        object["controls"] = Array(repeating: control, count: HardwarePreset.orderedCodes.count + 1)
        rejects("Oversized controls must fail decoding") {
            _ = try JSONDecoder().decode(HardwarePreset.self, from: JSONSerialization.data(withJSONObject: object))
        }
        object["controls"] = [["code": 0x10, "value": 65536, "maximum": 50]]
        rejects("Integer overflow must fail decoding") {
            _ = try JSONDecoder().decode(HardwarePreset.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let corrupt = Data("not a preset library".utf8)
        preferences.set(corrupt, forKey: HardwarePresetLibrary.storageKey)
        rejects("Corrupt storage must be reported") { _ = try HardwarePresetLibrary.load(from: preferences) }
        rejects("Saving must not overwrite corrupt storage") { try HardwarePresetLibrary.save([original], to: preferences) }
        check(preferences.data(forKey: HardwarePresetLibrary.storageKey) == corrupt, "Corrupt data remains available for recovery")
        preferences.set("wrong type", forKey: HardwarePresetLibrary.storageKey)
        rejects("Wrong storage type must fail") { _ = try HardwarePresetLibrary.load(from: preferences) }
        print("Hardware preset tests passed (\(checks) checks).")
    }
}
