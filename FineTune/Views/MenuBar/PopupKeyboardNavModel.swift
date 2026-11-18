// FineTune/Views/MenuBar/PopupKeyboardNavModel.swift
import Foundation

@MainActor
@Observable
final class PopupKeyboardNavModel {
    enum RowID: Hashable {
        case device(uid: String)
        case inputDevice(uid: String)
        case app(persistenceID: String)
    }

    private(set) var orderedRowIDs: [RowID] = []

    func syncOrder(
        activeDevices: [AudioDevice],
        inputDevices: [AudioDevice] = [],
        appPersistenceIDs: [String],
        isEditingPriority: Bool
    ) {
        guard !isEditingPriority else {
            orderedRowIDs = []
            return
        }
        var next: [RowID] = []
        next.reserveCapacity(activeDevices.count + inputDevices.count + appPersistenceIDs.count)
        for device in activeDevices {
            next.append(.device(uid: device.uid))
        }
        for device in inputDevices {
            next.append(.inputDevice(uid: device.uid))
        }
        for id in appPersistenceIDs {
            next.append(.app(persistenceID: id))
        }
        orderedRowIDs = next
    }

    func next(after current: RowID?) -> RowID? {
        guard !orderedRowIDs.isEmpty else { return nil }
        guard let current else { return orderedRowIDs.first }
        guard let index = orderedRowIDs.firstIndex(of: current) else {
            return orderedRowIDs.first
        }
        let nextIndex = index + 1
        return nextIndex < orderedRowIDs.count ? orderedRowIDs[nextIndex] : nil
    }

    func previous(before current: RowID?) -> RowID? {
        guard !orderedRowIDs.isEmpty else { return nil }
        guard let current else { return nil }
        guard let index = orderedRowIDs.firstIndex(of: current) else {
            return nil
        }
        return index > 0 ? orderedRowIDs[index - 1] : nil
    }

    func defaultFocus(defaultOutputUID: String?, defaultInputUID: String? = nil) -> RowID? {
        guard !orderedRowIDs.isEmpty else { return nil }
        if let uid = defaultOutputUID {
            let candidate = RowID.device(uid: uid)
            if orderedRowIDs.contains(candidate) {
                return candidate
            }
        }
        if let uid = defaultInputUID {
            let candidate = RowID.inputDevice(uid: uid)
            if orderedRowIDs.contains(candidate) {
                return candidate
            }
        }
        return orderedRowIDs.first
    }

    func deviceFocus(uid: String?, input: Bool) -> RowID? {
        if let uid {
            let preferred = input ? RowID.inputDevice(uid: uid) : RowID.device(uid: uid)
            if orderedRowIDs.contains(preferred) { return preferred }
        }
        return orderedRowIDs.first { row in
            switch row {
            case .inputDevice: return input
            case .device: return !input
            case .app: return false
            }
        }
    }
}
