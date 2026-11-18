import Foundation

nonisolated struct BluetoothBatteryReading: Equatable, Sendable {
    let combined: Int?
    let left: Int?
    let right: Int?
    let chargingCase: Int?
}

nonisolated struct BluetoothBatterySnapshot: Sendable {
    private struct Device: Sendable {
        let name: String
        let address: String?
        let reading: BluetoothBatteryReading?
    }

    private let devices: [Device]

    init() { devices = [] }

    init(data: Data) throws {
        struct Report: Decodable {
            let SPBluetoothDataType: [Controller]
        }
        struct Controller: Decodable {
            let device_connected: [[String: Properties]]?
        }
        struct Properties: Decodable {
            let device_address: String?
            let device_batteryLevelMain: Charge?
            let device_batteryLevelLeft: Charge?
            let device_batteryLevelRight: Charge?
            let device_batteryLevelCase: Charge?
        }

        let report = try JSONDecoder().decode(Report.self, from: data)
        devices = report.SPBluetoothDataType.flatMap { controller in
            (controller.device_connected ?? []).flatMap { entries in
                entries.map { name, properties in
                    let left = properties.device_batteryLevelLeft?.percent
                    let right = properties.device_batteryLevelRight?.percent
                    let chargingCase = properties.device_batteryLevelCase?.percent
                    let combined = properties.device_batteryLevelMain?.percent
                    let reading: BluetoothBatteryReading? = if combined != nil || left != nil || right != nil || chargingCase != nil {
                        BluetoothBatteryReading(combined: combined, left: left, right: right, chargingCase: chargingCase)
                    } else {
                        nil
                    }
                    return Device(name: name, address: properties.device_address.flatMap(Self.address), reading: reading)
                }
            }
        }
    }

    func reading(forUID uid: String, name: String, allowNameMatch: () -> Bool) -> BluetoothBatteryReading? {
        let addressPart = uid.components(separatedBy: ":").dropLast().joined(separator: ":")
        if let address = Self.address(uid) ?? Self.address(addressPart) {
            return devices.first { $0.address == address }?.reading
        }
        let matches = devices.filter { $0.name == name }
        guard matches.count == 1, let reading = matches.first?.reading, allowNameMatch() else { return nil }
        return reading
    }

    private static func address(_ value: String) -> String? {
        let address = value.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        guard address.count == 12, address.utf8.allSatisfy({ byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }) else { return nil }
        return address.lowercased()
    }

    private struct Charge: Decodable {
        let percent: Int?

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            let number: Int?
            if let string = try? value.decode(String.self) {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                number = Int(trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed)
            } else {
                number = try? value.decode(Int.self)
            }
            percent = number.flatMap { (0...100).contains($0) ? $0 : nil }
        }
    }
}
