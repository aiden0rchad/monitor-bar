import Foundation

struct HardwarePreset: Identifiable, Codable, Equatable {
    static let orderedCodes: [UInt8] = [0x2D, 0x14, 0x10, 0x12, 0x87, 0x16, 0x18, 0x1A, 0x62, 0x2F]
    let id: UUID
    let name: String
    let displayIdentity: String
    let values: [UInt8: UInt16]
    let maxima: [UInt8: UInt16]
    var orderedCodes: [UInt8] { Self.orderedCodes.filter { values[$0] != nil } }

    enum ValidationError: LocalizedError {
        case invalidName, invalidControls, invalidIdentity, invalidLibrary, duplicateName, saveFailed
        var errorDescription: String? {
            switch self {
            case .invalidName: return "Use a preset name with 1–64 characters on one line."
            case .invalidControls: return "The preset contains missing, duplicate, or unsupported hardware settings."
            case .invalidIdentity: return "The preset does not identify its monitor."
            case .invalidLibrary: return "Saved presets could not be read. The existing data has been left unchanged."
            case .duplicateName: return "A preset with that name already exists for this monitor."
            case .saveFailed: return "The presets could not be saved."
            }
        }
    }

    static func normalizedName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 64, name.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return name
    }

    init(id: UUID = UUID(), name: String, displayIdentity: String,
         values: [UInt8: UInt16], maxima: [UInt8: UInt16]) throws {
        guard let name = Self.normalizedName(name) else { throw ValidationError.invalidName }
        guard !displayIdentity.isEmpty, displayIdentity == displayIdentity.trimmingCharacters(in: .whitespacesAndNewlines),
              displayIdentity.count <= 256,
              displayIdentity.rangeOfCharacter(from: .controlCharacters) == nil else { throw ValidationError.invalidIdentity }
        guard !values.isEmpty, values.count <= Self.orderedCodes.count,
              Set(values.keys) == Set(maxima.keys), Set(values.keys).isSubset(of: Set(Self.orderedCodes)),
              values.allSatisfy({ code, value in maxima[code]! > 0 && value <= maxima[code]! }),
              values[0x2D].map({ $0 <= 9 && maxima[0x2D] == 10 }) ?? true,
              values[0x14].map({ $0 <= 4 && maxima[0x14] == 4 }) ?? true,
              values[0x2F].map({ $0 <= 10 && maxima[0x2F] == 10 }) ?? true else { throw ValidationError.invalidControls }
        self.id = id
        self.name = name
        self.displayIdentity = displayIdentity
        self.values = values
        self.maxima = maxima
    }

    func renamed(to name: String) throws -> Self {
        try Self(id: id, name: name, displayIdentity: displayIdentity, values: values, maxima: maxima)
    }

    // An array lets decoding reject duplicate control codes instead of silently
    // taking the final value of a repeated dictionary key.
    private struct Control: Codable {
        let code: UInt8
        let value: UInt16
        let maximum: UInt16
    }
    private enum CodingKeys: String, CodingKey { case id, name, displayIdentity, controls }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let controls = try container.decode([Control].self, forKey: .controls)
        guard controls.count <= Self.orderedCodes.count,
              Set(controls.map(\.code)).count == controls.count else { throw ValidationError.invalidControls }
        try self.init(id: container.decode(UUID.self, forKey: .id), name: container.decode(String.self, forKey: .name),
                      displayIdentity: container.decode(String.self, forKey: .displayIdentity),
                      values: Dictionary(uniqueKeysWithValues: controls.map { ($0.code, $0.value) }),
                      maxima: Dictionary(uniqueKeysWithValues: controls.map { ($0.code, $0.maximum) }))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayIdentity, forKey: .displayIdentity)
        try container.encode(orderedCodes.map { Control(code: $0, value: values[$0]!, maximum: maxima[$0]!) }, forKey: .controls)
    }
}

enum HardwarePresetLibrary {
    static let storageKey = "hardwarePresets.v1"

    private static func validate(_ presets: [HardwarePreset]) throws {
        guard Set(presets.map(\.id)).count == presets.count else { throw HardwarePreset.ValidationError.invalidLibrary }
        let names = presets.map { $0.displayIdentity + "\u{0}" + $0.name.lowercased() }
        guard Set(names).count == names.count else { throw HardwarePreset.ValidationError.duplicateName }
    }

    static func load(from preferences: UserDefaults) throws -> [HardwarePreset] {
        guard let object = preferences.object(forKey: storageKey) else { return [] }
        guard let data = object as? Data,
              let presets = try? JSONDecoder().decode([HardwarePreset].self, from: data) else { throw HardwarePreset.ValidationError.invalidLibrary }
        try validate(presets)
        return presets
    }

    static func save(_ presets: [HardwarePreset], to preferences: UserDefaults) throws {
        _ = try load(from: preferences)
        try validate(presets)
        let data = try JSONEncoder().encode(presets)
        let previous = preferences.object(forKey: storageKey)
        preferences.set(data, forKey: storageKey)
        guard preferences.synchronize(), preferences.data(forKey: storageKey) == data else {
            if let previous { preferences.set(previous, forKey: storageKey) }
            else { preferences.removeObject(forKey: storageKey) }
            preferences.synchronize()
            throw HardwarePreset.ValidationError.saveFailed
        }
    }
}
