import AppKit
import SwiftUI

@main
struct RenderPanel {
    @MainActor static func main() throws {
        let report = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Tests/Fixtures/demo-monitor.json")
        let data = try Data(contentsOf: report)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot: MonitorProbe
        if let single = try? decoder.decode(MonitorProbe.self, from: data) {
            snapshot = single
        } else {
            guard let first = try decoder.decode([MonitorProbe].self, from: data).first else {
                throw NSError(domain: "MonitorPanelPreview", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "The monitor report contains no displays."])
            }
            snapshot = first
        }
        let settings = CommandLine.arguments.dropFirst(2).first == "settings"
        let selection: DisplayModeInfo?
        if CommandLine.arguments.count > 2 && !settings {
            guard let id = Int32(CommandLine.arguments[2]),
                  let mode = snapshot.display.modes.first(where: { $0.id == id && $0.isSelectable }) else {
                throw NSError(domain: "MonitorPanelPreview", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "The preview mode is not selectable in this report."])
            }
            selection = mode
        } else {
            selection = nil
        }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let outputDirectory = URL(fileURLWithPath: ".build/preview", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let suite = "MonitorBar.Preview.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        if snapshot.display.isSamsungG91SD {
            preferences.set(true, forKey: Hardware.samsungEnableKey(snapshot.display))
            preferences.set(true, forKey: Hardware.samsungPictureModeEnableKey(snapshot.display))
            // Eye Saver is read as a prerequisite, but its write timing is not yet verified.
            for feature in snapshot.features where [0x14, 0x2F].contains(feature.code) {
                preferences.set(true, forKey: Hardware.samsungAdvancedEnableKey(snapshot.display, code: feature.code))
            }
        }
        let size = settings ? NSSize(width: 760, height: 620) : NSSize(width: 420, height: 560)
        for (name, scheme, appearance) in [
            ("light", ColorScheme.light, NSAppearance.Name.aqua),
            ("dark", ColorScheme.dark, NSAppearance.Name.darkAqua)
        ] {
            let store = MonitorStore(snapshot: snapshot, preferences: preferences)
            store.launchAtLogin = false
            let view = ZStack {
                Color(nsColor: .windowBackgroundColor)
                if settings { MonitorSettingsView(store: store) }
                else { MonitorPanel(store: store, previewSelection: selection) }
            }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)

            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isExcludedFromWindowsMenu = true
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            host.layoutSubtreeIfNeeded()

            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                pixelsWide: Int(size.width * 2),
                                                pixelsHigh: Int(size.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0) else {
                throw NSError(domain: "MonitorPanelPreview", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Could not allocate the preview bitmap."])
            }
            bitmap.size = size
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "MonitorPanelPreview", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Could not encode the preview PNG."])
            }
            let output = outputDirectory.appendingPathComponent("monitor-\(settings ? "settings" : "panel")-\(name).png")
            try png.write(to: output, options: .atomic)
            print(output.path)
            window.close()
        }
    }
}
