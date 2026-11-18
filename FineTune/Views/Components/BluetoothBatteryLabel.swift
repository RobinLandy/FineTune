import SwiftUI

struct BluetoothBatteryLabel: View {
    let reading: BluetoothBatteryReading

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: batterySymbol)
                .accessibilityHidden(true)
            if let level = reading.combined {
                let hasComponents = reading.left != nil || reading.right != nil || reading.chargingCase != nil
                Text(hasComponents ? "Overall \(level)%" : "\(level)%")
                    .accessibilityLabel("Overall battery \(level) percent")
            }
            if let level = reading.left { Text("L \(level)%").accessibilityLabel("Left \(level) percent") }
            if let level = reading.right { Text("R \(level)%").accessibilityLabel("Right \(level) percent") }
            if let level = reading.chargingCase { Text("Case \(level)%").accessibilityLabel("Case \(level) percent") }
        }
        .font(.system(size: 10))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var batterySymbol: String {
        let level = reading.combined ?? [reading.left, reading.right, reading.chargingCase].compactMap { $0 }.min() ?? 0
        let step = min(100, ((level + 12) / 25) * 25)
        return "battery.\(step)percent"
    }
}
