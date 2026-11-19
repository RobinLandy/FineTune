import AudioToolbox
import Foundation
import Testing
@testable import FineTune

@MainActor
struct MultiOutputUSBRecoveryTests {
    private let pebble = "pebble"
    private let oldDock = "AppleUSBAudioEngine:CalDigit, Inc.:CalDigit Thunderbolt 3 Audio:21200000:1"
    private let currentDock = "AppleUSBAudioEngine:CalDigit, Inc.:CalDigit Thunderbolt 3 Audio:22200000:1"
    private let anotherDock = "AppleUSBAudioEngine:CalDigit, Inc.:CalDigit Thunderbolt 3 Audio:23200000:1"
    private let dockInput = "AppleUSBAudioEngine:CalDigit, Inc.:CalDigit Thunderbolt 3 Audio:22200000:2"

    private func group() -> [String: Any] {
        [
            kAudioAggregateDeviceUIDKey: "group-uid",
            kAudioAggregateDeviceNameKey: "Multi: Kef + Pebble",
            kAudioAggregateDeviceIsPrivateKey: false,
            kAudioAggregateDeviceIsStackedKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: pebble,
            kAudioAggregateDeviceClockDeviceKey: oldDock,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: pebble, kAudioSubDeviceDriftCompensationKey: 0],
                [kAudioSubDeviceUIDKey: oldDock, kAudioSubDeviceDriftCompensationKey: 1, "latency-out": 12]
            ]
        ]
    }

    @Test("A USB location change updates membership and clock references in place")
    func repairsMembership() throws {
        let connected: Set<String> = [pebble, currentDock, dockInput]
        let group = group()
        let updated = try #require(MultiOutputUSBRecovery.repairedComposition(group, connectedUIDs: connected, usbOutputUIDs: [currentDock]))
        let members = try #require(updated[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]])
        #expect(members.compactMap { $0[kAudioSubDeviceUIDKey] as? String } == [pebble, currentDock])
        #expect(members[1][kAudioSubDeviceDriftCompensationKey] as? Int == 1)
        #expect(members[1]["latency-out"] as? Int == 12)
        #expect(updated[kAudioAggregateDeviceUIDKey] as? String == "group-uid")
        #expect(updated[kAudioAggregateDeviceNameKey] as? String == "Multi: Kef + Pebble")
        #expect(updated[kAudioAggregateDeviceIsStackedKey] as? Int == 1)
        #expect(updated[kAudioAggregateDeviceMainSubDeviceKey] as? String == pebble)
        #expect(updated[kAudioAggregateDeviceClockDeviceKey] as? String == currentDock)
        #expect(MultiOutputUSBRecovery.repairedComposition(updated, connectedUIDs: connected, usbOutputUIDs: [currentDock]) == nil)

        let movedAgain = try #require(MultiOutputUSBRecovery.repairedComposition(
            updated, connectedUIDs: [pebble, oldDock], usbOutputUIDs: [oldDock]
        ))
        #expect(NSDictionary(dictionary: group) == NSDictionary(dictionary: movedAgain))
    }

    @Test("Recovery waits for a unique replacement and keeps existing members")
    func skipsUnsafeReplacements() {
        var group = group()
        #expect(MultiOutputUSBRecovery.repairedComposition(group, connectedUIDs: [pebble], usbOutputUIDs: []) == nil)
        #expect(MultiOutputUSBRecovery.repairedComposition(group, connectedUIDs: [pebble, dockInput], usbOutputUIDs: [dockInput]) == nil)
        #expect(MultiOutputUSBRecovery.repairedComposition(group, connectedUIDs: [pebble, currentDock, anotherDock], usbOutputUIDs: [currentDock, anotherDock]) == nil)
        #expect(MultiOutputUSBRecovery.repairedComposition(group, connectedUIDs: [pebble, oldDock, currentDock], usbOutputUIDs: [oldDock, currentDock]) == nil)
        group[kAudioAggregateDeviceSubDeviceListKey] = [
            [kAudioSubDeviceUIDKey: oldDock], [kAudioSubDeviceUIDKey: currentDock]
        ]
        #expect(MultiOutputUSBRecovery.repairedComposition(group, connectedUIDs: [currentDock], usbOutputUIDs: [currentDock]) == nil)
    }

    @Test("Recovery applies to public output-only groups")
    func skipsOtherAggregates() {
        var group = group()
        group[kAudioAggregateDeviceIsPrivateKey] = true
        #expect(MultiOutputUSBRecovery.repairedComposition(group, connectedUIDs: [pebble, currentDock], usbOutputUIDs: [currentDock]) == nil)
        group[kAudioAggregateDeviceIsPrivateKey] = false
        group[kAudioAggregateDeviceTapListKey] = [[kAudioSubTapUIDKey: "tap"]]
        #expect(MultiOutputUSBRecovery.repairedComposition(group, connectedUIDs: [pebble, currentDock], usbOutputUIDs: [currentDock]) == nil)
        group[kAudioAggregateDeviceTapListKey] = nil
        group[kAudioAggregateDeviceSubDeviceListKey] = [
            [kAudioSubDeviceUIDKey: pebble], [kAudioSubDeviceUIDKey: oldDock, "channels-in": 2]
        ]
        #expect(MultiOutputUSBRecovery.repairedComposition(group, connectedUIDs: [pebble, currentDock], usbOutputUIDs: [currentDock]) == nil)
    }
}
