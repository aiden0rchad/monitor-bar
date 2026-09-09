import Foundation

private final class Transport {
    var replies: [DDCValue] = []
    var reads: [UInt8] = []
    var writes: [(UInt8, UInt16)] = []
    var waits = 0
    var paused = false
    var reasons: [String] = []
    var sendStatus = DDC_OK
    var pauseOnWait = false
    var pauseOnSend = false
    lazy var session = Hardware.SamsungSession(read: { [unowned self] code in
        reads.append(code)
        return replies.isEmpty ? Self.reply(25) : replies.removeFirst()
    }, send: { [unowned self] code, value in
        writes.append((code, value))
        if pauseOnSend { paused = true }
        return sendStatus
    }, isPaused: { [unowned self] in paused }, pause: { [unowned self] reason in
        paused = true
        reasons.append(reason)
    }, wait: { [unowned self] in
        waits += 1
        if pauseOnWait { paused = true }
    })

    static func reply(_ current: UInt16, maximum: UInt16 = 50, status: DDCStatus = DDC_OK, type: UInt8 = 0) -> DDCValue {
        DDCValue(status: status, ioReturn: status == DDC_TRANSPORT ? -1 : 0,
                 type: type, maximum: maximum, current: current)
    }
}

@main struct SamsungHardwareTests {
    static func feature(_ code: UInt8 = 0x10, current: UInt16 = 25) -> VCPFeature {
        VCPFeature(code: code, current: current, maximum: 50, type: 0, status: "ok")
    }

    static func main() {
        let suite = "MonitorBar.SamsungHardwareTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let display = DisplayInfo(id: 42, name: "Test Samsung", vendor: 0x4C2D, product: 0x778D,
                                  serial: 1234, builtIn: false, widthMM: 1000, heightMM: 300,
                                  rotation: 0, currentModeID: 0, modes: [])
        let key = Hardware.samsungEnableKey(display)
        precondition(!Hardware.canUseSamsungControls(display, preferences: preferences))
        for invalid: Any in ["true", 1, false] {
            preferences.set(invalid, forKey: key)
            precondition(!Hardware.canUseSamsungControls(display, preferences: preferences))
        }
        preferences.set(true, forKey: key)
        precondition(Hardware.canUseSamsungControls(display, preferences: preferences))
        Hardware.pauseAfterFault("Synthetic connection fault", preferences: preferences)
        precondition(Hardware.commandsPaused(in: preferences))
        precondition(Hardware.pauseReason(in: preferences) == "Synthetic connection fault")
        CFPreferencesSetAppValue(Hardware.pauseKey as CFString, kCFBooleanFalse, suite as CFString)
        CFPreferencesSetAppValue(Hardware.pauseReasonKey as CFString, "Updated through Core Foundation" as CFString, suite as CFString)
        precondition(CFPreferencesAppSynchronize(suite as CFString))
        precondition(!Hardware.commandsPaused(in: preferences))
        precondition(Hardware.pauseReason(in: preferences) == "Updated through Core Foundation")

        var connection = DDCHDMIConnection()
        connection.display.registryID = 1
        connection.portRegistryID = 2
        connection.connectionCount = 3
        var changed = connection
        changed.connectionCount += 1
        var connectionFaults = 0
        let pauseConnection: (String) -> Void = { _ in connectionFaults += 1 }
        precondition(Hardware.validateSamsungConnection(previous: nil, current: connection, pause: pauseConnection))
        precondition(Hardware.validateSamsungConnection(previous: connection, current: connection, pause: pauseConnection))
        precondition(!Hardware.validateSamsungConnection(previous: connection, current: changed, pause: pauseConnection))
        precondition(!Hardware.validateSamsungConnection(previous: connection, current: nil, pause: pauseConnection))
        precondition(!Hardware.validateSamsungConnection(previous: nil, current: nil, pause: pauseConnection))
        precondition(connectionFaults == 2)
        // Explicit resume clears the previous identity, permitting a fresh validation.
        precondition(Hardware.validateSamsungConnection(previous: nil, current: changed, pause: pauseConnection))

        let pipKey = Hardware.samsungPIPReadEnableKey(display)
        precondition(!Hardware.canUseSamsungPIPRead(display, preferences: preferences))
        for invalid: Any in ["true", 1, false] {
            preferences.set(invalid, forKey: pipKey)
            precondition(!Hardware.canUseSamsungPIPRead(display, preferences: preferences))
        }
        preferences.set(true, forKey: pipKey)
        precondition(Hardware.canUseSamsungPIPRead(display, preferences: preferences))
        preferences.set(false, forKey: key)
        precondition(!Hardware.canUseSamsungPIPRead(display, preferences: preferences))
        preferences.set(true, forKey: key)
        let pipOff = Transport.reply(13568, maximum: 127)
        let pipOn = Transport.reply(13569, maximum: 127)
        let pipReader = Transport()
        pipReader.replies = [pipOff]
        let pipFeature = pipReader.session.pipFeature()
        precondition(Hardware.isValidSamsungPIPFeature(pipFeature) && pipFeature.current > pipFeature.maximum)
        precondition(SamsungPIPState(rawValue: pipFeature.current)?.isOn == false && !pipFeature.isSlider)
        precondition(pipReader.reads == [0xE2] && pipReader.writes.isEmpty)
        let pipScan = Transport()
        pipScan.replies = [pipOff]
        precondition(pipScan.session.scan(requirePIPOff: true).count == 8)
        precondition(pipScan.reads == [0xE2] + Hardware.samsungControlCodes && pipScan.writes.isEmpty)
        for reply in [pipOn, Transport.reply(0x8000, maximum: 127),
                      Transport.reply(13568, maximum: 100), Transport.reply(13568, maximum: 127, type: 1),
                      Transport.reply(0, maximum: 127, status: DDC_UNSUPPORTED)] {
            let stopped = Transport()
            stopped.replies = [reply]
            let result = stopped.session.scan(includePictureMode: true, requirePIPOff: true, advancedCodes: [0x14, 0x2F])
            precondition(result.count == 1 && result[0].code == 0xE2)
            precondition(stopped.reads == [0xE2] && stopped.writes.isEmpty && !stopped.paused)
            let brightness = Transport()
            brightness.replies = [reply]
            precondition(brightness.session.write(feature: feature(), value: 26, guardPIP: true).1.contains("PIP/PBP"))
            precondition(brightness.reads == [0xE2] && brightness.writes.isEmpty)
            let picture = Transport()
            picture.replies = [reply]
            _ = picture.session.writePictureMode(feature: VCPFeature(code: 0x2D, current: 2, maximum: 10, type: 0, status: "ok"),
                                                 value: 8, guardPIP: true)
            precondition(picture.reads == [0xE2] && picture.writes.isEmpty)
            let tone = Transport()
            tone.replies = [reply]
            _ = tone.session.writeAdvanced(feature: VCPFeature(code: 0x14, current: 2, maximum: 4, type: 0, status: "ok"),
                                           value: 3, guardPIP: true)
            precondition(tone.reads == [0xE2] && tone.writes.isEmpty)
        }
        let pipWrite = Transport()
        pipWrite.replies = [pipOff, Transport.reply(25), Transport.reply(26)]
        precondition(pipWrite.session.write(feature: feature(), value: 26, guardPIP: true).0?.current == 26)
        precondition(pipWrite.reads == [0xE2, 0x10, 0x10] && pipWrite.writes.count == 1)
        let pipFault = Transport()
        pipFault.replies = [Transport.reply(0, status: DDC_TRANSPORT)]
        _ = pipFault.session.write(feature: feature(), value: 26, guardPIP: true)
        precondition(pipFault.reads == [0xE2] && pipFault.writes.isEmpty && pipFault.paused)
        let pipPaused = Transport()
        pipPaused.paused = true
        precondition(pipPaused.session.scan(requirePIPOff: true).isEmpty)
        _ = pipPaused.session.write(feature: feature(), value: 26, guardPIP: true)
        precondition(pipPaused.reads.isEmpty && pipPaused.writes.isEmpty)
        print("Samsung PIP/PBP opt-in, encoded state, Off prerequisite, and request budgets passed")

        let scan = Transport()
        precondition(scan.session.scan().count == 7)
        precondition(scan.reads == [0x10, 0x12, 0x87, 0x16, 0x18, 0x1A, 0x62])
        precondition(scan.writes.isEmpty && scan.waits == 7)

        let unavailable = Transport()
        unavailable.replies = [Transport.reply(253), Transport.reply(0, status: DDC_UNSUPPORTED)]
        let features = unavailable.session.scan()
        precondition(features.count == 7 && unavailable.reads.count == 7 && !unavailable.paused)
        precondition(features[0].current == 253 && features[0].maximum == 50 && !features[0].isReadable)
        precondition(features[1].status == "unsupported")

        let valid = Transport()
        valid.replies = [Transport.reply(25), Transport.reply(26)]
        let confirmed = valid.session.write(feature: feature(), value: 26)
        precondition(confirmed.0?.current == 26 && confirmed.1.contains("confirmed"))
        precondition(valid.reads == [0x10, 0x10] && valid.writes.count == 1 && valid.writes[0].1 == 26)
        precondition(valid.waits == 3 && !valid.paused)

        let unchanged = Transport()
        precondition(unchanged.session.write(feature: feature(), value: 25).0?.current == 25)
        precondition(unchanged.reads.count == 1 && unchanged.writes.isEmpty)
        for reply in [Transport.reply(24), Transport.reply(25, maximum: 100)] {
            let stale = Transport()
            stale.replies = [reply]
            let refreshed = stale.session.write(feature: feature(), value: 26)
            precondition(refreshed.0?.current == reply.current && refreshed.0?.maximum == reply.maximum)
            precondition(refreshed.1.contains("nothing was written"))
            precondition(stale.reads.count == 1 && stale.writes.isEmpty && !stale.paused)
        }
        let alreadyApplied = Transport()
        alreadyApplied.replies = [Transport.reply(26, maximum: 100)]
        precondition(alreadyApplied.session.write(feature: feature(), value: 26).0?.current == 26)
        precondition(alreadyApplied.reads.count == 1 && alreadyApplied.writes.isEmpty)

        for code: UInt8 in [0x04, 0x60, 0x8A, 0xD6] {
            let denied = Transport()
            precondition(denied.session.write(feature: feature(code), value: 26).0 == nil)
            precondition(denied.session.feature(code).status == "unsupported")
            precondition(denied.reads.isEmpty && denied.writes.isEmpty)
        }
        let outOfRange = Transport()
        precondition(outOfRange.session.write(feature: feature(), value: 51).0 == nil)
        precondition(outOfRange.reads.isEmpty && outOfRange.writes.isEmpty)
        outOfRange.replies = [Transport.reply(253)]
        precondition(outOfRange.session.write(feature: feature(), value: 26).0?.current == 253)
        precondition(outOfRange.reads.count == 1 && outOfRange.writes.isEmpty && !outOfRange.paused)

        for status in [DDC_TRANSPORT, DDC_MALFORMED, DDC_NO_REPLY, DDC_UNAVAILABLE] {
            let failed = Transport()
            failed.replies = [Transport.reply(0, status: status)]
            precondition(failed.session.scan().isEmpty)
            precondition(failed.reads.count == 1 && failed.writes.isEmpty && failed.paused && failed.reasons.count == 1)
            _ = failed.session.write(feature: feature(), value: 26)
            precondition(failed.reads.count == 1 && failed.writes.isEmpty)
        }

        for reply in [Transport.reply(24), Transport.reply(253), Transport.reply(0, status: DDC_UNSUPPORTED), Transport.reply(26, maximum: 100)] {
            let mismatch = Transport()
            mismatch.replies = [Transport.reply(25), reply]
            let actual = mismatch.session.write(feature: feature(), value: 26)
            precondition(actual.0?.current == reply.current && actual.1.contains("not confirmed"))
            precondition(mismatch.reads.count == 2 && mismatch.writes.count == 1 && mismatch.paused)
        }

        let sendFailure = Transport()
        sendFailure.sendStatus = DDC_TRANSPORT
        precondition(sendFailure.session.write(feature: feature(), value: 26).0 == nil)
        precondition(sendFailure.reads.count == 1 && sendFailure.writes.count == 1 && sendFailure.paused)

        let paused = Transport()
        paused.paused = true
        precondition(paused.session.scan().isEmpty)
        _ = paused.session.write(feature: feature(), value: 26)
        precondition(paused.reads.isEmpty && paused.writes.isEmpty && paused.waits == 0)
        let midWait = Transport()
        midWait.pauseOnWait = true
        _ = midWait.session.write(feature: feature(), value: 26)
        precondition(midWait.reads.isEmpty && midWait.writes.isEmpty)
        let midSend = Transport()
        midSend.pauseOnSend = true
        _ = midSend.session.write(feature: feature(), value: 26)
        precondition(midSend.reads.count == 1 && midSend.writes.count == 1)
        pictureModeTests(display: display, preferences: preferences)
        advancedControlTests(display: display, preferences: preferences)
        print("Samsung opt-in, pause, seven-control scan, single-write budget, unavailable values, and confirmation checks passed")
    }

    static func pictureModeTests(display: DisplayInfo, preferences: UserDefaults) {
        let baseKey = Hardware.samsungEnableKey(display)
        let modeKey = Hardware.samsungPictureModeEnableKey(display)
        precondition(modeKey != baseKey)
        precondition(!Hardware.canUseSamsungPictureMode(display, preferences: preferences))
        for invalid: Any in [false, "true", 1] {
            preferences.set(invalid, forKey: modeKey)
            precondition(!Hardware.canUseSamsungPictureMode(display, preferences: preferences))
        }
        // CFPreferences can retain numeric 1 when replacing it with equal Bool true.
        preferences.removeObject(forKey: modeKey)
        preferences.set(true, forKey: modeKey)
        precondition(Hardware.canUseSamsungPictureMode(display, preferences: preferences))
        for invalid: Any in [false, "true", 1] {
            preferences.set(invalid, forKey: baseKey)
            precondition(!Hardware.canUseSamsungPictureMode(display, preferences: preferences))
        }
        preferences.removeObject(forKey: baseKey)
        precondition(!Hardware.canUseSamsungPictureMode(display, preferences: preferences))
        preferences.set(true, forKey: baseKey)
        let anotherUnit = DisplayInfo(id: 43, name: "Another Samsung", vendor: display.vendor,
                                     product: display.product, serial: display.serial + 1, builtIn: false,
                                     widthMM: 1000, heightMM: 300, rotation: 0, currentModeID: 0, modes: [])
        precondition(Hardware.samsungPictureModeEnableKey(anotherUnit) != modeKey)
        preferences.set(true, forKey: Hardware.samsungEnableKey(anotherUnit))
        precondition(!Hardware.canUseSamsungPictureMode(anotherUnit, preferences: preferences))
        precondition(Hardware.samsungPictureModeChoices.map { $0.0 } == Array(UInt16(0)...9))
        precondition(Hardware.samsungPictureModeChoices.allSatisfy { !$0.1.isEmpty })

        let baseReplies = Array(repeating: Transport.reply(25), count: 7)
        let pc = Transport.reply(0, maximum: 0)
        let mode = VCPFeature(code: 0x2D, current: 0, maximum: 10, type: 0, status: "ok")
        let baseScan = Transport()
        precondition(baseScan.session.scan(includePictureMode: false).count == 7)
        precondition(baseScan.reads == Hardware.samsungControlCodes && baseScan.writes.isEmpty)

        let scan = Transport()
        scan.replies = baseReplies + [pc, Transport.reply(4, maximum: 10)]
        let scanned = scan.session.scan(includePictureMode: true)
        precondition(scanned.count == 8 && scanned.last?.code == 0x2D && scanned.last?.current == 4)
        precondition(scanned.last?.isReadable == true && !scanned.contains { $0.code == 0xE4 })
        precondition(scan.reads == Hardware.samsungControlCodes + [0xE4, 0x2D])
        precondition(scan.waits == 9 && scan.writes.isEmpty && !scan.paused)

        for reply in [Transport.reply(1, maximum: 1), Transport.reply(0, status: DDC_UNSUPPORTED),
                      Transport.reply(1, maximum: 0), Transport.reply(0, maximum: 1, type: 1)] {
            let nonPC = Transport()
            nonPC.replies = baseReplies + [reply]
            let actual = nonPC.session.scan(includePictureMode: true)
            precondition(actual.count == 8 && actual.prefix(7).allSatisfy(\.isReadable))
            precondition(actual.last?.code == 0x2D && actual.last?.isReadable == false)
            precondition(nonPC.reads == Hardware.samsungControlCodes + [0xE4])
            precondition(nonPC.writes.isEmpty && !nonPC.paused)
        }

        for reply in [Transport.reply(10, maximum: 10), Transport.reply(253, maximum: 10),
                      Transport.reply(0, maximum: 9), Transport.reply(0, maximum: 10, type: 1),
                      Transport.reply(0, maximum: 10, status: DDC_UNSUPPORTED)] {
            let unavailable = Transport()
            unavailable.replies = baseReplies + [pc, reply]
            let actual = unavailable.session.scan(includePictureMode: true)
            precondition(actual.count == 8 && actual.prefix(7).allSatisfy(\.isReadable))
            precondition(actual.last?.current == reply.current && actual.last?.maximum == reply.maximum)
            precondition(actual.last?.isReadable == false && unavailable.reads.count == 9)
            precondition(unavailable.writes.isEmpty && !unavailable.paused)
        }

        for status in [DDC_TRANSPORT, DDC_MALFORMED, DDC_NO_REPLY] {
            for prefix in [baseReplies, baseReplies + [pc]] {
                let failed = Transport()
                failed.replies = prefix + [Transport.reply(0, status: status)]
                precondition(failed.session.scan(includePictureMode: true).isEmpty)
                precondition(failed.reads.count == prefix.count + 1 && failed.writes.isEmpty)
                precondition(failed.paused && failed.reasons.count == 1)
            }
        }

        let valid = Transport()
        valid.replies = [pc, Transport.reply(0, maximum: 10), Transport.reply(1, maximum: 10)]
        let confirmed = valid.session.writePictureMode(feature: mode, value: 1)
        precondition(confirmed.0?.current == 1 && confirmed.1.contains("confirmed"))
        precondition(valid.reads == [0xE4, 0x2D, 0x2D] && valid.writes.count == 1)
        precondition(valid.writes[0].0 == 0x2D && valid.writes[0].1 == 1)
        precondition(valid.waits == 4 && !valid.paused)

        let unchanged = Transport()
        unchanged.replies = [pc, Transport.reply(0, maximum: 10)]
        precondition(unchanged.session.writePictureMode(feature: mode, value: 0).0?.current == 0)
        precondition(unchanged.reads == [0xE4, 0x2D] && unchanged.writes.isEmpty && !unchanged.paused)
        for reply in [Transport.reply(1, maximum: 10), Transport.reply(0, maximum: 11)] {
            let stale = Transport()
            stale.replies = [pc, reply]
            let refreshed = stale.session.writePictureMode(feature: mode, value: 2)
            precondition(refreshed.0?.current == reply.current && refreshed.0?.maximum == reply.maximum)
            precondition(stale.reads == [0xE4, 0x2D] && stale.writes.isEmpty && !stale.paused)
        }

        for original in [feature(), VCPFeature(code: 0x2D, current: 10, maximum: 10, type: 0, status: "ok"),
                         VCPFeature(code: 0x2D, current: 0, maximum: 11, type: 0, status: "ok"),
                         VCPFeature(code: 0x2D, current: 0, maximum: 10, type: 1, status: "ok"),
                         VCPFeature(code: 0x2D, current: 0, maximum: 10, type: 0, status: "unsupported")] {
            let denied = Transport()
            precondition(denied.session.writePictureMode(feature: original, value: 1).0 == nil)
            precondition(denied.reads.isEmpty && denied.writes.isEmpty && denied.waits == 0)
        }
        for target: UInt16 in [10, 253, .max] {
            let denied = Transport()
            precondition(denied.session.writePictureMode(feature: mode, value: target).0 == nil)
            precondition(denied.reads.isEmpty && denied.writes.isEmpty && denied.waits == 0)
        }
        let regularWrite = Transport()
        precondition(regularWrite.session.write(feature: mode, value: 1).0 == nil)
        precondition(regularWrite.reads.isEmpty && regularWrite.writes.isEmpty)

        for reply in [Transport.reply(1, maximum: 1), Transport.reply(0, status: DDC_UNSUPPORTED)] {
            let nonPC = Transport()
            nonPC.replies = [reply]
            _ = nonPC.session.writePictureMode(feature: mode, value: 1)
            precondition(nonPC.reads == [0xE4] && nonPC.writes.isEmpty && !nonPC.paused)
        }
        for status in [DDC_TRANSPORT, DDC_MALFORMED, DDC_NO_REPLY] {
            for prefix in [[], [pc]] {
                let failed = Transport()
                failed.replies = prefix + [Transport.reply(0, status: status)]
                _ = failed.session.writePictureMode(feature: mode, value: 1)
                precondition(failed.reads.count == prefix.count + 1 && failed.writes.isEmpty && failed.paused)
            }
        }
        for reply in [Transport.reply(0, maximum: 10), Transport.reply(10, maximum: 10),
                      Transport.reply(1, maximum: 11), Transport.reply(1, maximum: 10, type: 1),
                      Transport.reply(0, maximum: 10, status: DDC_UNSUPPORTED)] {
            let mismatch = Transport()
            mismatch.replies = [pc, Transport.reply(0, maximum: 10), reply]
            let actual = mismatch.session.writePictureMode(feature: mode, value: 1)
            precondition(actual.0?.current == reply.current && actual.0?.maximum == reply.maximum)
            precondition(mismatch.reads == [0xE4, 0x2D, 0x2D] && mismatch.writes.count == 1)
            precondition(mismatch.paused && mismatch.reasons.count == 1)
        }
        let sendFailure = Transport()
        sendFailure.replies = [pc, Transport.reply(0, maximum: 10)]
        sendFailure.sendStatus = DDC_TRANSPORT
        _ = sendFailure.session.writePictureMode(feature: mode, value: 1)
        precondition(sendFailure.reads == [0xE4, 0x2D] && sendFailure.writes.count == 1 && sendFailure.paused)

        let paused = Transport()
        paused.paused = true
        precondition(paused.session.scan(includePictureMode: true).isEmpty)
        _ = paused.session.writePictureMode(feature: mode, value: 1)
        precondition(paused.reads.isEmpty && paused.writes.isEmpty && paused.waits == 0)
        let midWait = Transport()
        midWait.pauseOnWait = true
        _ = midWait.session.writePictureMode(feature: mode, value: 1)
        precondition(midWait.reads.isEmpty && midWait.writes.isEmpty)
        let midSend = Transport()
        midSend.replies = [pc, Transport.reply(0, maximum: 10)]
        midSend.pauseOnSend = true
        _ = midSend.session.writePictureMode(feature: mode, value: 1)
        precondition(midSend.reads == [0xE4, 0x2D] && midSend.writes.count == 1)
        print("Samsung Picture Mode opt-in, PC gating, bounded requests, range validation, and pause checks passed")
    }

    static func advancedControlTests(display: DisplayInfo, preferences: UserDefaults) {
        let codes: [UInt8] = [0x0A, 0x14, 0x2F]
        precondition(Hardware.samsungAdvancedControlCodes == codes)
        let baseKey = Hardware.samsungEnableKey(display)
        let keys = codes.map { Hardware.samsungAdvancedEnableKey(display, code: $0) }
        precondition(Set(keys).count == codes.count)
        precondition(!keys.contains(baseKey) && !keys.contains(Hardware.samsungPictureModeEnableKey(display)))
        for code in codes {
            precondition(!Hardware.canUseSamsungAdvancedControl(display, code: code, preferences: preferences))
        }
        for code in codes {
            let key = Hardware.samsungAdvancedEnableKey(display, code: code)
            for invalid: Any in [false, "true", 1] {
                preferences.set(invalid, forKey: key)
                precondition(!Hardware.canUseSamsungAdvancedControl(display, code: code, preferences: preferences))
            }
            preferences.removeObject(forKey: key)
            preferences.set(true, forKey: key)
            for other in codes {
                precondition(Hardware.canUseSamsungAdvancedControl(display, code: other, preferences: preferences) == (other == code))
            }
            for invalid: Any in [false, "true", 1] {
                preferences.set(invalid, forKey: baseKey)
                precondition(!Hardware.canUseSamsungAdvancedControl(display, code: code, preferences: preferences))
            }
            preferences.removeObject(forKey: baseKey)
            precondition(!Hardware.canUseSamsungAdvancedControl(display, code: code, preferences: preferences))
            preferences.set(true, forKey: baseKey)
            preferences.removeObject(forKey: key)
        }
        let anotherUnit = DisplayInfo(id: 43, name: "Another Samsung", vendor: display.vendor,
                                     product: display.product, serial: display.serial + 1, builtIn: false,
                                     widthMM: 1000, heightMM: 300, rotation: 0, currentModeID: 0, modes: [])
        preferences.set(true, forKey: Hardware.samsungEnableKey(anotherUnit))
        for code in codes {
            preferences.set(true, forKey: Hardware.samsungAdvancedEnableKey(display, code: code))
            precondition(Hardware.samsungAdvancedEnableKey(anotherUnit, code: code) != Hardware.samsungAdvancedEnableKey(display, code: code))
            precondition(!Hardware.canUseSamsungAdvancedControl(anotherUnit, code: code, preferences: preferences))
        }
        for code: UInt8 in [0x04, 0x10, 0x2D, 0x60, 0xD6, 0xE4, 0xFF] {
            preferences.set(true, forKey: Hardware.samsungAdvancedEnableKey(display, code: code))
            precondition(!Hardware.canUseSamsungAdvancedControl(display, code: code, preferences: preferences))
            precondition(Hardware.samsungAdvancedChoices(for: code).isEmpty)
            let denied = Transport()
            precondition(denied.session.advancedFeature(code).status == "unsupported")
            precondition(denied.session.writeAdvanced(feature: feature(code), value: 1).0 == nil)
            precondition(denied.reads.isEmpty && denied.writes.isEmpty && denied.waits == 0)
        }
        precondition(Hardware.samsungAdvancedChoices(for: 0x0A).map { $0.0 } == [0, 1, 2])
        precondition(Hardware.samsungAdvancedChoices(for: 0x14).map { $0.0 } == [0, 1, 2, 3, 4])

        func advanced(_ code: UInt8, current: UInt16 = 0, maximum: UInt16) -> VCPFeature {
            VCPFeature(code: code, current: current, maximum: maximum, type: 0, status: "ok")
        }
        for key in keys { preferences.removeObject(forKey: key) }
        let baseReplies = Array(repeating: Transport.reply(25), count: 7)
        let eyeOff = Transport.reply(0, maximum: 2)
        let defaultScan = Transport()
        let enabled = codes.filter { Hardware.canUseSamsungAdvancedControl(display, code: $0, preferences: preferences) }
        precondition(enabled.isEmpty && defaultScan.session.scan(advancedCodes: enabled).map(\.code) == Hardware.samsungControlCodes)
        precondition(defaultScan.reads == Hardware.samsungControlCodes && defaultScan.writes.isEmpty)
        let unknownScan = Transport()
        precondition(unknownScan.session.scan(advancedCodes: [0x10, 0x60, 0xE4, 0xFF]).count == 7)
        precondition(unknownScan.reads == Hardware.samsungControlCodes)
        let eyeScan = Transport()
        eyeScan.replies = [eyeOff] + baseReplies
        precondition(eyeScan.session.scan(advancedCodes: [0x0A]).count == 8)
        precondition(eyeScan.reads == [0x0A] + Hardware.samsungControlCodes && eyeScan.waits == 8)
        for (code, current, maximum): (UInt8, UInt16, UInt16) in [(0x14, 2, 4), (0x2F, 5, 10)] {
            let key = Hardware.samsungAdvancedEnableKey(display, code: code)
            preferences.set(true, forKey: key)
            let scopedScan = Transport()
            scopedScan.replies = [eyeOff] + baseReplies + [Transport.reply(current, maximum: maximum)]
            let enabled = codes.filter { Hardware.canUseSamsungAdvancedControl(display, code: $0, preferences: preferences) }
            precondition(enabled == [code])
            let scoped = scopedScan.session.scan(advancedCodes: enabled)
            let prerequisite = scoped.filter { $0.code == 0x0A }
            precondition(scoped.count == 9 && prerequisite.count == 1)
            precondition(prerequisite[0].current == 0 && Hardware.isValidSamsungAdvancedControl(prerequisite[0]))
            precondition(scoped.first { $0.code == code }?.current == current)
            precondition(scopedScan.reads == [0x0A] + Hardware.samsungControlCodes + [code])
            precondition(!Hardware.canUseSamsungAdvancedControl(display, code: 0x0A, preferences: preferences))
            preferences.removeObject(forKey: key)
        }
        let fullScan = Transport()
        fullScan.replies = [eyeOff] + baseReplies + [Transport.reply(0, maximum: 0), Transport.reply(0, maximum: 10),
                                                    Transport.reply(2, maximum: 4), Transport.reply(5, maximum: 10)]
        let full = fullScan.session.scan(includePictureMode: true, advancedCodes: [0x2F, 0x14, 0x0A, 0x14, 0xFF])
        precondition(full.count == 11 && full.allSatisfy(\.isReadable))
        precondition(Set(full.map(\.code)) == Set(Hardware.samsungControlCodes + [0x2D, 0x0A, 0x14, 0x2F]))
        precondition(fullScan.reads == [0x0A] + Hardware.samsungControlCodes + [0xE4, 0x2D, 0x14, 0x2F])
        precondition(fullScan.waits == 12 && fullScan.writes.isEmpty && !fullScan.paused)

        for eye in [Transport.reply(1, maximum: 2), Transport.reply(2, maximum: 2),
                    Transport.reply(253, maximum: 2), Transport.reply(0, maximum: 50),
                    Transport.reply(0, maximum: 2, type: 1), Transport.reply(0, status: DDC_UNSUPPORTED)] {
            let gated = Transport()
            gated.replies = [eye] + Array(repeating: Transport.reply(25), count: 3)
            let actual = gated.session.scan(includePictureMode: true, advancedCodes: codes)
            precondition(actual.count == 11 && gated.reads == [0x0A, 0x12, 0x87, 0x62])
            precondition(gated.writes.isEmpty && !gated.paused)
            for code: UInt8 in [0x10, 0x16, 0x18, 0x1A, 0x2D, 0x14, 0x2F] {
                precondition(actual.first { $0.code == code }?.isReadable == false)
            }
            for code: UInt8 in [0x12, 0x87, 0x62] {
                precondition(actual.first { $0.code == code }?.isReadable == true)
            }
            for code: UInt8 in [0x14, 0x2F] {
                let write = Transport()
                write.replies = [eye]
                let maximum: UInt16 = code == 0x14 ? 4 : 10
                _ = write.session.writeAdvanced(feature: advanced(code, maximum: maximum), value: 1)
                precondition(write.reads == [0x0A] && write.writes.isEmpty && !write.paused)
            }
        }
        for status in [DDC_TRANSPORT, DDC_MALFORMED, DDC_NO_REPLY, DDC_UNAVAILABLE] {
            for prefix in [[], [eyeOff] + baseReplies] {
                let failed = Transport()
                failed.replies = prefix + [Transport.reply(0, status: status)]
                precondition(failed.session.scan(advancedCodes: [0x14, 0x2F]).isEmpty)
                precondition(failed.reads.count == prefix.count + 1 && failed.writes.isEmpty && failed.paused)
            }
            let failedGate = Transport()
            failedGate.replies = [Transport.reply(0, status: status)]
            _ = failedGate.session.writeAdvanced(feature: advanced(0x14, maximum: 4), value: 1)
            precondition(failedGate.reads == [0x0A] && failedGate.writes.isEmpty && failedGate.paused)
        }
        let pausedScan = Transport()
        pausedScan.paused = true
        precondition(pausedScan.session.scan(includePictureMode: true, advancedCodes: codes).isEmpty)
        precondition(pausedScan.reads.isEmpty && pausedScan.writes.isEmpty && pausedScan.waits == 0)
        for status in [DDC_UNSUPPORTED, DDC_OK] {
            let contradictory = Transport()
            var reply = Transport.reply(0, maximum: 2, status: status)
            reply.ioReturn = -1
            contradictory.replies = [reply]
            _ = contradictory.session.advancedFeature(0x0A)
            precondition(contradictory.reads == [0x0A] && contradictory.writes.isEmpty && contradictory.paused)
        }

        for code: UInt8 in [0x10, 0x16, 0x18, 0x1A] {
            let blocked = Transport()
            blocked.replies = [Transport.reply(1, maximum: 2)]
            _ = blocked.session.write(feature: feature(code), value: 26, guardEyeSaver: true)
            precondition(blocked.reads == [0x0A] && blocked.writes.isEmpty && !blocked.paused)
            let permitted = Transport()
            permitted.replies = [eyeOff, Transport.reply(25), Transport.reply(26)]
            precondition(permitted.session.write(feature: feature(code), value: 26, guardEyeSaver: true).0?.current == 26)
            precondition(permitted.reads == [0x0A, code, code] && permitted.writes.count == 1 && !permitted.paused)
        }
        for code: UInt8 in [0x12, 0x87, 0x62] {
            let unaffected = Transport()
            unaffected.replies = [Transport.reply(25), Transport.reply(26)]
            precondition(unaffected.session.write(feature: feature(code), value: 26, guardEyeSaver: true).0?.current == 26)
            precondition(unaffected.reads == [code, code] && unaffected.writes.count == 1 && !unaffected.paused)
        }
        let picture = VCPFeature(code: 0x2D, current: 0, maximum: 10, type: 0, status: "ok")
        let blockedPicture = Transport()
        blockedPicture.replies = [Transport.reply(1, maximum: 2)]
        _ = blockedPicture.session.writePictureMode(feature: picture, value: 1, guardEyeSaver: true)
        precondition(blockedPicture.reads == [0x0A] && blockedPicture.writes.isEmpty && !blockedPicture.paused)
        let profiles: [(UInt8, UInt16, [UInt16])] = [(0x0A, 2, [2]), (0x14, 4, [4]), (0x2F, 10, [10])]
        for (code, largest, maximums) in profiles {
            let gateReplies = code == 0x0A ? [] : [Transport.reply(0, maximum: 2)]
            let gateCodes: [UInt8] = code == 0x0A ? [] : [0x0A]
            for maximum in maximums {
                for current in UInt16(0)...largest {
                    precondition(Hardware.isValidSamsungAdvancedControl(advanced(code, current: current, maximum: maximum)))
                }
                let readable = Transport()
                readable.replies = [Transport.reply(largest, maximum: maximum)]
                let actual = readable.session.advancedFeature(code)
                precondition(Hardware.isValidSamsungAdvancedControl(actual))
                precondition(readable.reads == [code] && readable.writes.isEmpty && !readable.paused)
            }
            for maximum: UInt16 in [0, 1, maximums[0] + 1, 6, 50, .max] {
                precondition(!Hardware.isValidSamsungAdvancedControl(advanced(code, maximum: maximum)))
            }
            let original = advanced(code, maximum: maximums[0])
            for reply in [Transport.reply(largest + 1, maximum: maximums[0]), Transport.reply(253, maximum: maximums[0]),
                          Transport.reply(0, maximum: 50), Transport.reply(0, maximum: maximums[0], type: 1),
                          Transport.reply(0, maximum: maximums[0], status: DDC_UNSUPPORTED)] {
                let invalid = Transport()
                invalid.replies = [reply]
                let actual = invalid.session.advancedFeature(code)
                precondition(!actual.isReadable && !Hardware.isValidSamsungAdvancedControl(actual))
                precondition(actual.current == reply.current && actual.maximum == reply.maximum)
                precondition(invalid.reads == [code] && invalid.writes.isEmpty && !invalid.paused)
                precondition(invalid.session.writeAdvanced(feature: actual, value: 1).0 == nil)
                precondition(invalid.reads == [code] && invalid.writes.isEmpty)
            }
            for target in [largest + 1, 253, UInt16.max] {
                let invalid = Transport()
                precondition(invalid.session.writeAdvanced(feature: original, value: target).0 == nil)
                precondition(invalid.reads.isEmpty && invalid.writes.isEmpty && invalid.waits == 0)
            }

            let valid = Transport()
            valid.replies = gateReplies + [Transport.reply(0, maximum: maximums[0]), Transport.reply(1, maximum: maximums[0])]
            let confirmed = valid.session.writeAdvanced(feature: original, value: 1)
            precondition(confirmed.0?.current == 1 && confirmed.1.contains("confirmed"))
            precondition(valid.reads == gateCodes + [code, code] && valid.writes.count == 1)
            precondition(valid.writes[0].0 == code && valid.writes[0].1 == 1 && valid.waits == gateCodes.count + 3 && !valid.paused)
            let unchanged = Transport()
            unchanged.replies = gateReplies + [Transport.reply(0, maximum: maximums[0])]
            precondition(unchanged.session.writeAdvanced(feature: original, value: 0).0?.current == 0)
            precondition(unchanged.reads == gateCodes + [code] && unchanged.writes.isEmpty && !unchanged.paused)
            for reply in [Transport.reply(2, maximum: maximums[0]), Transport.reply(0, maximum: maximums[0] + 1),
                          Transport.reply(253, maximum: maximums[0])] {
                let stale = Transport()
                stale.replies = gateReplies + [reply]
                let actual = stale.session.writeAdvanced(feature: original, value: 1)
                precondition(actual.0?.current == reply.current && actual.0?.maximum == reply.maximum)
                precondition(stale.reads == gateCodes + [code] && stale.writes.isEmpty && !stale.paused)
            }
            for reply in [Transport.reply(0, maximum: maximums[0]), Transport.reply(253, maximum: maximums[0]),
                          Transport.reply(1, maximum: maximums[0] + 1), Transport.reply(1, maximum: maximums[0], type: 1),
                          Transport.reply(0, maximum: maximums[0], status: DDC_UNSUPPORTED)] {
                let mismatch = Transport()
                mismatch.replies = gateReplies + [Transport.reply(0, maximum: maximums[0]), reply]
                let actual = mismatch.session.writeAdvanced(feature: original, value: 1)
                precondition(actual.0?.current == reply.current && actual.0?.maximum == reply.maximum)
                precondition(mismatch.reads == gateCodes + [code, code] && mismatch.writes.count == 1)
                precondition(mismatch.paused && mismatch.reasons.count == 1)
            }
            for status in [DDC_TRANSPORT, DDC_MALFORMED, DDC_NO_REPLY, DDC_UNAVAILABLE] {
                for prefix in [[], [Transport.reply(0, maximum: maximums[0])]] {
                    let failed = Transport()
                    failed.replies = gateReplies + prefix + [Transport.reply(0, status: status)]
                    _ = failed.session.writeAdvanced(feature: original, value: 1)
                    precondition(failed.reads.count == gateCodes.count + prefix.count + 1 && failed.writes.count == prefix.count)
                    precondition(failed.paused && failed.reasons.count == 1)
                }
            }
            let sendFailure = Transport()
            sendFailure.replies = gateReplies + [Transport.reply(0, maximum: maximums[0])]
            sendFailure.sendStatus = DDC_TRANSPORT
            _ = sendFailure.session.writeAdvanced(feature: original, value: 1)
            precondition(sendFailure.reads == gateCodes + [code] && sendFailure.writes.count == 1 && sendFailure.paused)
            let paused = Transport()
            paused.paused = true
            precondition(!paused.session.advancedFeature(code).isReadable)
            _ = paused.session.writeAdvanced(feature: original, value: 1)
            precondition(paused.reads.isEmpty && paused.writes.isEmpty && paused.waits == 0)
            let midWait = Transport()
            midWait.pauseOnWait = true
            _ = midWait.session.writeAdvanced(feature: original, value: 1)
            precondition(midWait.reads.isEmpty && midWait.writes.isEmpty)
            let midSend = Transport()
            midSend.replies = gateReplies + [Transport.reply(0, maximum: maximums[0])]
            midSend.pauseOnSend = true
            _ = midSend.session.writeAdvanced(feature: original, value: 1)
            precondition(midSend.reads == gateCodes + [code] && midSend.writes.count == 1)
        }
        print("Samsung advanced control opt-in, categorical ranges, bounded writes, and pause checks passed")
    }

}
