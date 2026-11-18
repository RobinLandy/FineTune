import Foundation
import Testing
@testable import FineTune

struct BluetoothBatterySnapshotTests {
    @Test func connectedDevicesPreserveEachReportedLevel() throws {
        let report = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"AirPods":{"device_address":"AA:BB:CC:DD:EE:FF","device_batteryLevelLeft":"95%",
            "device_batteryLevelRight":"0%","device_batteryLevelCase":33,"device_batteryLevelMain":"83%"}},
          {"Headset":{"device_address":"12:34:56:78:90:AB","device_batteryLevelMain":"72%"}},
          {"Partial":{"device_batteryLevelLeft":"72%","device_batteryLevelRight":255,"device_batteryLevelCase":"Unknown"}}
        ],"device_not_connected":[{"Offline":{"device_batteryLevelMain":"99%"}}]}]}
        """
        let snapshot = try BluetoothBatterySnapshot(data: Data(report.utf8))

        #expect(snapshot.reading(forUID: "AA-BB-CC-DD-EE-FF:input", name: "Different name", allowNameMatch: { false })
            == BluetoothBatteryReading(combined: 83, left: 95, right: 0, chargingCase: 33))
        #expect(snapshot.reading(forUID: "12:34:56:78:90:AB:output", name: "Headset", allowNameMatch: { false })
            == BluetoothBatteryReading(combined: 72, left: nil, right: nil, chargingCase: nil))
        #expect(snapshot.reading(forUID: "opaque", name: "Partial", allowNameMatch: { true })
            == BluetoothBatteryReading(combined: nil, left: 72, right: nil, chargingCase: nil))
        #expect(snapshot.reading(forUID: "opaque", name: "Partial", allowNameMatch: { false }) == nil)
        #expect(snapshot.reading(forUID: "opaque", name: "Offline", allowNameMatch: { true }) == nil)
        #expect(snapshot.reading(forUID: "11-22-33-44-55-66:output", name: "AirPods", allowNameMatch: { true }) == nil)
    }

    @Test func ambiguousNamesAreIgnoredEvenWhenOnlyOneDeviceHasBattery() throws {
        let report = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"Earbuds":{"device_address":"AA:BB:CC:DD:EE:FF","device_batteryLevelMain":"75%"}},
          {"Earbuds":{"device_address":"11:22:33:44:55:66"}}
        ]}]}
        """
        let snapshot = try BluetoothBatterySnapshot(data: Data(report.utf8))
        #expect(snapshot.reading(forUID: "opaque", name: "Earbuds", allowNameMatch: { true }) == nil)
        #expect(snapshot.reading(forUID: "AA-BB-CC-DD-EE-FF:output", name: "Earbuds", allowNameMatch: { true })?.combined == 75)
    }
}
