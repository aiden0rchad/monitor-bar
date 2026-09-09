import AppKit
import Foundation

@main struct Probe {
    @MainActor static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let once = args.first == "--read-once"
        let contrast = args.first == "--step-contrast"
        let control = args.first == "--step-control"
        let step = args.first == "--step-brightness" || contrast || control
        let write = step || args.first == "--set-brightness"
        guard args.isEmpty || args == ["--modes"] || args == ["--full"] || ((once || write) && args.count == (control ? 6 : 5)) else {
            fputs("Usage: monitor-probe [--modes | --full | --read-once DISPLAY_ID REGISTRY_ID HEX_CODE PROFILE | --step-brightness DISPLAY_ID REGISTRY_ID EXPECTED NEW | --step-contrast DISPLAY_ID REGISTRY_ID EXPECTED NEW | --set-brightness DISPLAY_ID REGISTRY_ID EXPECTED NEW | --step-control DISPLAY_ID REGISTRY_ID HEX_CODE EXPECTED NEW]\n", stderr)
            exit(64)
        }
        var request: (display: UInt32, registry: UInt64, code: UInt8, profile: Int32, expected: UInt16?, newValue: UInt16?)?
        if once || write {
            guard let display = UInt32(args[1]), display > 0,
                  let registry = UInt64(args[2]), registry > 0 else {
                fputs("Invalid diagnostic request. IDs must be positive decimal integers.\n", stderr)
                exit(64)
            }
            if write {
                let code: UInt8? = control ? UInt8(args[3], radix: 16) : (contrast ? 0x12 : 0x10)
                guard let code, [0x10, 0x12, 0x16, 0x18, 0x1a, 0x62, 0x87, 0x8a].contains(code),
                      let expected = UInt16(args[control ? 4 : 3]), let newValue = UInt16(args[control ? 5 : 4]),
                      !step || abs(Int(newValue) - Int(expected)) == 1 else {
                    fputs("Control codes must be hexadecimal 10, 12, 16, 18, 1A, 62, 87 or 8A. Values must be decimal 0–65535; step commands require values exactly one apart.\n", stderr)
                    exit(64)
                }
                request = (display, registry, code, 0, expected, newValue)
            } else {
                guard let code = UInt8(args[3], radix: 16),
                      let profile = Int32(args[4]), (0...3).contains(profile) else {
                    fputs("Invalid read-once request. Profile is decimal 0–3; feature code is hexadecimal.\n", stderr)
                    exit(64)
                }
                request = (display, registry, code, profile, nil, nil)
            }
        }
        let displays = Hardware.displays()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let request {
            guard !Hardware.hardwareCommandsPaused else {
                fputs("Hardware commands are paused; no DDC request sent.\n", stderr)
                exit(2)
            }
            guard displays.count == 1, displays[0].id == request.display else {
                fputs("Diagnostic requests require exactly one external display matching DISPLAY_ID.\n", stderr)
                exit(2)
            }
            // The operator must match REGISTRY_ID using cached IORegistry data.
            // Avoid service enumeration/EDID access and the normal probe's retries.
            guard let handle = DDCOpen(request.registry) else {
                fputs("Could not open the specified external DDC service.\n", stderr)
                exit(2)
            }
            let value = DDCGetVCPOnce(handle, request.code, request.profile)
            var writeStatus: DDCStatus?
            if let expected = request.expected, let newValue = request.newValue,
               value.status == DDC_OK, value.type == 0, value.maximum > 0,
               value.current == expected, value.current <= value.maximum, newValue <= value.maximum {
                writeStatus = DDCSetVCP(handle, request.code, newValue)
            }
            DDCClose(handle)
            var output: [String: Any] = [
                "displayID": request.display, "registryID": request.registry,
                "code": String(format: "0x%02X", request.code), "profile": request.profile,
                "status": String(cString: DDCStatusName(value.status)), "ioReturn": value.ioReturn,
                "current": value.current, "maximum": value.maximum, "type": value.type,
                "scannedAt": ISO8601DateFormatter().string(from: Date())
            ]
            if let newValue = request.newValue {
                output["requestedValue"] = newValue
                output["writeStatus"] = writeStatus.map { String(cString: DDCStatusName($0)) } ?? "not sent: initial value or range did not match"
                output["writeConfirmed"] = false
            }
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]))
            FileHandle.standardOutput.write(Data("\n".utf8))
            if value.status != DDC_OK || (write && writeStatus != DDC_OK) { exit(2) }
            return
        }
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
