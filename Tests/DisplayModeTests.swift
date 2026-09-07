import Foundation

@main
struct DisplayModeTests {
    static func mode(id: Int32 = 9, size: (Int, Int) = (1260, 840), pixels: (Int, Int) = (2520, 1680), rate: Double = 60, flags: UInt32 = 3, desktop: Bool = true) -> DisplayModeInfo {
        DisplayModeInfo(id: id, width: size.0, height: size.1, pixelWidth: pixels.0, pixelHeight: pixels.1, refreshRate: rate, ioFlags: flags, isDesktopUsable: desktop)
    }

    static func display(_ modes: [DisplayModeInfo], current: Int32) -> DisplayInfo {
        DisplayInfo(id: 4, name: "Display", vendor: 0x09E5, product: 100, serial: 1234, builtIn: false, widthMM: 350, heightMM: 210, rotation: 0, currentModeID: current, modes: modes)
    }

    static func main() throws {
        let hidpi = mode()
        let standard = mode(id: 22, size: (1920, 1200), pixels: (1920, 1200))
        let native = mode(id: 24, size: (2520, 1680), flags: 0x02000003, desktop: false)
        let unsafe = mode(id: 90, flags: 1, desktop: false)
        let flagVariant = mode(id: 91, flags: 0x02000003)
        let duplicate = mode(id: 92)
        let all = display([hidpi, duplicate, flagVariant, unsafe], current: unsafe.id)
        let checks: [(String, Bool)] = [
            ("exact 2x HiDPI", hidpi.isHiDPI && hidpi.scaleLabel == "2× HiDPI"),
            ("native 3:2 aspect", hidpi.aspectLabel == "3:2" && hidpi.pixelLabel == "2520 × 1680 pixels"),
            ("standard 16:10", !standard.isHiDPI && standard.aspectLabel == "16:10" && standard.scaleLabel == "Standard 1×"),
            ("horizontal scaling alone", !mode(pixels: (2520, 840)).isHiDPI),
            ("vertical scaling alone", !mode(pixels: (1260, 1680)).isHiDPI),
            ("inconsistent scale", !mode(pixels: (2520, 1800)).isHiDPI),
            ("zero dimensions", !mode(size: (0, 840)).isHiDPI && !mode(size: (0, 840)).isSelectable),
            ("fractional refresh labels", mode(rate: 59.94).label != mode(rate: 60).label && mode(rate: 59.94).label.contains("59.94 Hz")),
            ("safe native without desktop flag", native.isNative && native.isSelectable),
            ("unsafe mode", !unsafe.isSelectable),
            ("non-native without desktop flag", !mode(desktop: false).isSelectable),
            ("interlaced mode", !mode(flags: 3 | 0x40).isSelectable),
            ("stretched mode", !mode(flags: 3 | 0x800).isSelectable),
            ("hidden mode", !mode(flags: 3 | 0x80).isSelectable),
            ("poor graphics mode", !mode(flags: 3 | 0x1000).isSelectable),
            ("unsafe current retained", all.currentMode?.id == unsafe.id && all.selectableModes.contains { $0.id == unsafe.id }),
            ("semantic duplicate collapsed", all.selectableModes.filter { $0.ioFlags == 3 }.count == 1),
            ("different flags retained", all.selectableModes.contains { $0.id == flagVariant.id }),
            ("unsafe inactive excluded", !display([hidpi, unsafe], current: hidpi.id).selectableModes.contains { $0.id == unsafe.id })
        ]
        for (name, passed) in checks { assert(passed, name) }
        let decoded = try JSONDecoder().decode(DisplayModeInfo.self, from: JSONEncoder().encode(native))
        assert(decoded == native, "Mode metadata survives JSON export")
        print("Display mode tests passed (\(checks.count + 1) checks).")
    }
}
