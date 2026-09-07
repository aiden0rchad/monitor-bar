import Foundation

@main struct CapabilityTests {
    static func main() {
        let parsed = Capabilities.features("(prot(monitor)vcp(10 12 60(0F 11) D6(01 04 05))mccs_ver(2.2))")
        assert(parsed.count == 4)
        assert(parsed[0x10] == [])
        assert(parsed[0x60] == [15, 17])
        assert(parsed[0xD6] == [1, 4, 5])
        assert(parsed[0x0F] == nil)
        for invalid in ["vcp(60(0F(11)))", "vcp(100)", "vcp(junk10)", "vcp(10 60(0F)", "vcp(10 10)", "notvcp(10)", "vcp(10 60(0x11))"] {
            assert(Capabilities.features(invalid).isEmpty, invalid)
        }
        assert(Capabilities.features("vcp(10\n 60(0f 0011))")[0x60] == [15, 17])
        assert(!VCPFeature(code: 0x04, current: 0, maximum: 1, type: 1, status: "ok").isSlider)
        assert(!VCPFeature(code: 0x10, current: 101, maximum: 100, type: 0, status: "ok").isSlider)
        assert(!VCPFeature(code: 0x10, current: 25, maximum: 100, type: 0, status: "unsupported").isSlider)
        print("Capability parsing and writable-control checks passed")
    }
}
