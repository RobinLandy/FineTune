import AudioToolbox
import Foundation
import os

enum MultiOutputUSBRecovery {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FineTune", category: "MultiOutputUSBRecovery")

    static func repairGroups() -> Set<String> {
        guard let ids = try? AudioDeviceID.readDeviceList() else { return [] }
        let devices = ids.compactMap { id in (try? id.readDeviceUID()).map { (uid: $0, id: id) } }
        let connectedUIDs = Set(devices.map(\.uid))
        let usbOutputUIDs = Set(devices.filter {
            USBAudioDeviceUID.locationIndependentUID(for: $0.uid) != nil
                && $0.id.hasOutputStreams() && $0.id.isDeviceAlive()
        }.map(\.uid))
        var repaired = Set<String>()
        for (uid, id) in devices where id.isAggregateDevice() && !id.hasInputStreams() {
            guard let composition = id.aggregateComposition(),
                  let updated = repairedComposition(composition, connectedUIDs: connectedUIDs, usbOutputUIDs: usbOutputUIDs)
            else { continue }
            let status = id.setAggregateComposition(updated)
            if status == noErr {
                repaired.insert(uid)
                logger.info("Restored USB output membership in \(uid)")
            } else {
                logger.error("Could not restore USB output membership in \(uid): \(status)")
            }
        }
        return repaired
    }

    static func repairedComposition(
        _ composition: [String: Any], connectedUIDs: Set<String>, usbOutputUIDs: Set<String>
    ) -> [String: Any]? {
        guard (composition[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue != true,
              composition[kAudioAggregateDeviceTapListKey] == nil,
              var members = composition[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]],
              members.count > 1,
              members.allSatisfy({ (($0["channels-in"] as? NSNumber)?.intValue ?? 0) == 0 }) else { return nil }
        let memberUIDs = members.compactMap { $0[kAudioSubDeviceUIDKey] as? String }
        guard memberUIDs.count == members.count else { return nil }

        let savedByIdentity = Dictionary(grouping: memberUIDs) { USBAudioDeviceUID.locationIndependentUID(for: $0) }
        let connectedByIdentity = Dictionary(grouping: usbOutputUIDs) { USBAudioDeviceUID.locationIndependentUID(for: $0) }
        var replacements: [String: String] = [:]
        for (index, uid) in memberUIDs.enumerated() where !connectedUIDs.contains(uid) {
            guard let identity = USBAudioDeviceUID.locationIndependentUID(for: uid),
                  savedByIdentity[identity]?.count == 1,
                  let matches = connectedByIdentity[identity], matches.count == 1,
                  let replacement = matches.first else { continue }
            members[index][kAudioSubDeviceUIDKey] = replacement
            replacements[uid] = replacement
        }
        guard !replacements.isEmpty else { return nil }

        var updated = composition
        updated[kAudioAggregateDeviceSubDeviceListKey] = members
        for key in [kAudioAggregateDeviceMainSubDeviceKey, kAudioAggregateDeviceClockDeviceKey] {
            if let uid = composition[key] as? String, let replacement = replacements[uid] {
                updated[key] = replacement
            }
        }
        return updated
    }
}
