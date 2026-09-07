import AppKit
import Foundation

@main struct Probe {
    @MainActor static func main() throws {
        let displays = Hardware.displays()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if CommandLine.arguments.contains("--modes") {
            FileHandle.standardOutput.write(try encoder.encode(displays))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }
        let results = displays.map { display in
            fputs("Reading \(display.name) (\(display.identity))…\n", stderr)
            return Hardware.probe(display, deep: CommandLine.arguments.contains("--full")) { count in
                if count % 16 == 0 { fputs("Read \(count) feature addresses\n", stderr) }
            }
        }
        FileHandle.standardOutput.write(try encoder.encode(results))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
