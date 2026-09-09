// Pure codecs for the G91SD subset of Samsung Display Manager's input protocol.
// Successful decoding does not establish hardware support or authorize a write.
enum SamsungInputSource: UInt16, CaseIterable {
    case displayPort = 0x0F, hdmi1 = 0x11, hdmi2 = 0x12

    var pipValue: UInt16 {
        switch self {
        case .hdmi1: return 0
        case .hdmi2: return 1
        case .displayPort: return 0x10
        }
    }

    init?(pipValue: UInt16) {
        switch pipValue {
        case 0: self = .hdmi1
        case 1: self = .hdmi2
        case 0x10: self = .displayPort
        default: return nil
        }
    }
}

enum SamsungPIPLayout: UInt16, CaseIterable {
    case pbpEqual = 0, pbpTwoToOne = 1, pbpOneToTwo = 2, pip = 7

    var command: UInt16 { self == .pip ? 0x10 : rawValue + 3 }
}

struct SamsungPIPState: Equatable {
    let isOn: Bool
    let supportsPBP: Bool
    let supportsPIP: Bool
    let pbpSizeSupport: UInt16
    let pipSizeCount: UInt16
    let pipPosition: UInt16
    let pipSize: UInt16
    let layout: SamsungPIPLayout

    init?(rawValue: UInt16) {
        let pbpSizes = (rawValue >> 10) & 3
        let pipSizes = (rawValue >> 8) & 3
        let size = (rawValue >> 4) & 3
        guard rawValue & 0xC000 == 0, pbpSizes < 3, pipSizes < 3, size < 3,
              let layout = SamsungPIPLayout(rawValue: (rawValue >> 1) & 7) else { return nil }
        isOn = rawValue & 1 != 0
        supportsPBP = rawValue & 0x2000 != 0
        supportsPIP = rawValue & 0x1000 != 0
        pbpSizeSupport = pbpSizes
        pipSizeCount = pipSizes + 1
        pipPosition = (rawValue >> 6) & 3
        pipSize = size
        self.layout = layout
        guard !isOn || supports(layout: layout),
              !isOn || layout != .pip || size < pipSizeCount else { return nil }
    }

    func supports(layout: SamsungPIPLayout) -> Bool {
        switch layout {
        case .pip: return supportsPIP
        case .pbpEqual: return supportsPBP
        case .pbpTwoToOne, .pbpOneToTwo: return supportsPBP && pbpSizeSupport > 0
        }
    }
}

enum SamsungPIPChannel: UInt16 {
    case main = 0, sub = 1

    func sourceCommand(_ source: SamsungInputSource) -> UInt16 {
        (rawValue << 8) | source.pipValue
    }
}

struct SamsungPIPSources: Equatable {
    let main: SamsungInputSource
    let sub: SamsungInputSource

    init?(rawValue: UInt16) {
        // Bit 15 selects a different three-source format, outside the G91SD path.
        guard rawValue & 0x8000 == 0,
              let main = SamsungInputSource(pipValue: rawValue >> 8),
              let sub = SamsungInputSource(pipValue: rawValue & 0xFF) else { return nil }
        self.main = main
        self.sub = sub
    }
}

enum SamsungSoundSource: UInt16 {
    case main = 0, sub = 1
    // SDM also defines channel 2 and reserved; neither is offered for two sources.
}
