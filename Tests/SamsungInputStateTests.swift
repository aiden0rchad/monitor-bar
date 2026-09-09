@main
enum SamsungInputStateTests {
    static func main() {
        precondition(SamsungInputSource(rawValue: 5) == nil)
        precondition(SamsungInputSource(rawValue: 0x11) == .hdmi1)
        precondition(SamsungInputSource(pipValue: 0x11) == nil)
        precondition(SamsungInputSource(pipValue: 0x10) == .displayPort)
        precondition(SamsungPIPChannel.main.sourceCommand(.displayPort) == 0x0010)
        precondition(SamsungPIPChannel.sub.sourceCommand(.hdmi2) == 0x0101)

        let pip = SamsungPIPState(rawValue: 0x359F)!
        precondition(pip.isOn && pip.supportsPBP && pip.supportsPIP)
        precondition(pip.layout == .pip && pip.pbpSizeSupport == 1)
        precondition(pip.pipSizeCount == 2 && pip.pipSize == 1 && pip.pipPosition == 2)
        precondition(pip.supports(layout: .pbpOneToTwo))
        precondition(SamsungPIPLayout.pip.command == 0x10)
        precondition(SamsungPIPLayout.pbpEqual.command == 3)
        precondition(SamsungPIPState(rawValue: 0)?.supports(layout: .pbpEqual) == false)
        precondition(SamsungPIPState(rawValue: 0x2001)?.supports(layout: .pbpTwoToOne) == false)
        for invalid: UInt16 in [0x8000, 0x4000, 0x3C00, 0x3300, 0x3030, 0x3006, 0x0001, 0x102F] {
            precondition(SamsungPIPState(rawValue: invalid) == nil)
        }

        let sources = SamsungPIPSources(rawValue: 0x1001)!
        precondition(sources.main == .displayPort && sources.sub == .hdmi2)
        precondition(SamsungPIPSources(rawValue: 0x0010)?.sub == .displayPort)
        precondition(SamsungPIPSources(rawValue: 0x8001) == nil)
        precondition(SamsungPIPSources(rawValue: 0x1110) == nil)
        precondition(SamsungSoundSource(rawValue: 0) == .main)
        precondition(SamsungSoundSource(rawValue: 1) == .sub)
        precondition(SamsungSoundSource(rawValue: 2) == nil)
        precondition(SamsungSoundSource(rawValue: 0x100) == nil)

        // Every accepted source pair must preserve both bytes; no unknown source
        // may silently become HDMI 1, as the vendor decoder's fallback would do.
        for raw in UInt16.min...UInt16.max {
            if let pair = SamsungPIPSources(rawValue: raw) {
                precondition((pair.main.pipValue << 8) | pair.sub.pipValue == raw)
            }
        }
        print("Samsung input codecs: passed (offline)")
    }
}
