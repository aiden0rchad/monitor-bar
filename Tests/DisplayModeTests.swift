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
        ] + optionChecks()
        for (name, passed) in checks { assert(passed, name) }
        let decoded = try JSONDecoder().decode(DisplayModeInfo.self, from: JSONEncoder().encode(native))
        assert(decoded == native, "Mode metadata survives JSON export")
        print("Display mode tests passed (\(checks.count + 1) checks).")
    }

    static func optionChecks() -> [(String, Bool)] {
        let active = mode(id: 210, rate: 59.94)
        let duplicate = mode(id: 211, rate: 59.94)
        let nativeVariant = mode(id: 212, rate: 59.94, flags: 0x02000003)
        let standard = mode(id: 213, pixels: (1260, 840))
        let triple = mode(id: 214, pixels: (3780, 2520))
        let fractionalScale = mode(id: 215, pixels: (1890, 1260), rate: 75)
        let sixty = mode(id: 216)
        let unspecified = mode(id: 217, rate: 0)
        let other = mode(id: 230, size: (1280, 800), pixels: (2560, 1600), rate: 59.94)
        let otherSixty = mode(id: 231, size: (1280, 800), pixels: (2560, 1600))
        let otherStandard = mode(id: 232, size: (1280, 800), pixels: (1280, 800), rate: 59.94)
        let unsafe = mode(id: 290, size: (1110, 740), pixels: (2220, 1480), rate: 75, flags: 1)
        let invalid = [mode(id: 291, rate: -.infinity), mode(id: 292, rate: .infinity),
                       mode(id: 293, rate: .nan), mode(id: 294, rate: -1)]
        // Deliberately place flag variants and duplicates before the current mode.
        let modes = [nativeVariant, duplicate, active, standard, triple, fractionalScale,
                     sixty, unspecified, other, otherSixty, otherStandard, unsafe] + invalid
        let options = DisplayModeOptions(display: display(modes, current: active.id))
        let unsafeOptions = DisplayModeOptions(display: display(modes, current: unsafe.id))
        let rates = options.refreshModes(for: active)
        let currentRepresentative = options.preferredMode(resolution: active.resolution,
            rendering: active.renderingSize, rate: active.refreshRate, near: other)
        let draftRepresentative = options.preferredMode(resolution: active.resolution,
            rendering: active.renderingSize, rate: active.refreshRate, near: duplicate)
        let moved = options.preferredMode(resolution: other.resolution, near: active)
        let safeFallback = unsafeOptions.preferredMode(resolution: active.resolution, near: unsafe)
        let withoutFractional = DisplayModeOptions(display: display([otherStandard, otherSixty,
            mode(id: 233, size: (1280, 800), pixels: (2560, 1600), rate: 0)], current: otherStandard.id))
        let nearest = withoutFractional.preferredMode(resolution: other.resolution, near: active)
        let noCurrent = DisplayModeOptions(display: display([duplicate, nativeVariant, active], current: 999))
        let reversed = DisplayModeOptions(display: display(Array(modes.reversed()), current: active.id))
        let absent = DisplaySize(width: 999, height: 777)
        let duplicateDisplay = display([mode(id: 9), mode(id: 4), other], current: other.id)
        let chosenDuplicate = DisplayModeOptions(display: duplicateDisplay)
            .preferredMode(resolution: active.resolution, near: other)
        let closeRates = [mode(id: 301), mode(id: 302, rate: 60.0001)]
        let rateOptions = DisplayModeOptions(display: display(closeRates, current: 301))
        let closeScales = [mode(id: 303, size: (1000, 1000), pixels: (2000, 2000)),
                           mode(id: 304, size: (1000, 1000), pixels: (2001, 2001))]
        let scaleOptions = DisplayModeOptions(display: display(closeScales, current: 303))
        return [
            ("resolution groups ignore duplicate IDs and flags", options.resolutions == [other.resolution, active.resolution]),
            ("all render dimensions retained", options.renderingSizes(for: active.resolution) ==
                [standard.renderingSize, fractionalScale.renderingSize, active.renderingSize, triple.renderingSize]),
            ("HiDPI scale variants remain distinct", [fractionalScale, active, triple].allSatisfy(\.isHiDPI) &&
                Set([fractionalScale, active, triple].map(\.scalingChoiceLabel)).count == 3),
            ("standard scaling label", standard.scalingChoiceLabel == "Standard"),
            ("nonuniform scaling reports rendering dimensions", mode(pixels: (2520, 1800)).scalingChoiceLabel == "2520 × 1800 pixels"),
            ("refresh variants group flags but preserve fractional and unspecified", rates.map(\.refreshRate) == [60, 59.94, 0]),
            ("active representative retains exact current ID", currentRepresentative?.id == active.id &&
                rates.first { $0.refreshRate == active.refreshRate }?.id == active.id),
            ("staged representative retains its existing ID", draftRepresentative?.id == duplicate.id),
            ("unselected flag variant resolves deterministically", noCurrent.preferredMode(resolution: active.resolution,
                rendering: active.renderingSize, rate: active.refreshRate, near: other)?.id == nativeVariant.id),
            ("mode order does not alter groups or representative", reversed.resolutions == options.resolutions &&
                reversed.refreshModes(for: active).map(\.id) == rates.map(\.id)),
            ("resolution change preserves scale and exact refresh", moved?.id == other.id),
            ("scaling change selects an existing timing", options.preferredMode(resolution: active.resolution,
                rendering: standard.renderingSize, near: active)?.id == standard.id),
            ("closest known rate wins over unspecified", nearest?.id == otherSixty.id),
            ("unspecified preserved when explicitly selected", options.preferredMode(resolution: active.resolution,
                rendering: active.renderingSize, rate: 0, near: active)?.id == unspecified.id),
            ("unspecified label is not zero Hz", unspecified.refreshLabel == "Unspecified"),
            ("fractional refresh label differs from integer", active.refreshLabel != sixty.refreshLabel),
            ("invalid refresh rates excluded", invalid.allSatisfy { !$0.isSelectable } &&
                !options.availableModes.contains { invalid.map(\.id).contains($0.id) }),
            ("unavailable resolution has no synthetic timing", options.preferredMode(resolution: absent, near: active) == nil),
            ("unavailable rendering has no synthetic timing", options.preferredMode(resolution: active.resolution,
                rendering: absent, near: active) == nil),
            ("unavailable refresh has no synthetic timing", options.preferredMode(resolution: active.resolution,
                rendering: active.renderingSize, rate: 144, near: active) == nil),
            ("individually available fields cannot invent a combination", options.preferredMode(resolution: active.resolution,
                rendering: standard.renderingSize, rate: 59.94, near: active) == nil),
            ("unsafe current resolution stays visible", unsafeOptions.resolutions.contains(unsafe.resolution)),
            ("unsafe current rendering stays visible", unsafeOptions.renderingSizes(for: unsafe.resolution) == [unsafe.renderingSize]),
            ("unsafe current rate stays visible", unsafeOptions.refreshModes(for: unsafe).map(\.id) == [unsafe.id]),
            ("unsafe current cannot be selected as fallback", unsafeOptions.preferredMode(resolution: unsafe.resolution,
                near: unsafe) == nil && !unsafeOptions.availableModes.contains { $0.id == unsafe.id }),
            ("fallback is always an actual safe candidate", safeFallback?.isSelectable == true &&
                modes.contains { $0.id == safeFallback?.id }),
            ("unsafe inactive resolution is hidden", !options.resolutions.contains(unsafe.resolution)),
            ("chosen duplicate exists in raw modes despite legacy deduplication", chosenDuplicate?.id == 4 &&
                duplicateDisplay.modes.contains { $0.id == 4 } &&
                duplicateDisplay.selectableModes.filter { $0.resolution == active.resolution }.map(\.id) == [9]),
            ("close refresh rates remain separate choices", rateOptions.refreshModes(for: closeRates[0]).map(\.refreshRate) == [60.0001, 60]),
            ("colliding refresh labels are disambiguated", closeRates[0].refreshLabel == closeRates[1].refreshLabel &&
                Set(closeRates.map { rateOptions.refreshLabel(for: $0) }).count == 2),
            ("close render sizes remain separate choices", scaleOptions.renderingSizes(for: closeScales[0].resolution).count == 2),
            ("colliding scale labels include distinct rendering dimensions", closeScales[0].scalingChoiceLabel == closeScales[1].scalingChoiceLabel &&
                Set(closeScales.map { scaleOptions.scalingLabel(for: $0) }).count == 2 &&
                closeScales.allSatisfy { scaleOptions.scalingLabel(for: $0).contains($0.renderingSize.label) }),
            ("unambiguous labels stay concise", options.refreshLabel(for: active) == active.refreshLabel &&
                options.scalingLabel(for: active) == active.scalingChoiceLabel)
        ]
    }
}
