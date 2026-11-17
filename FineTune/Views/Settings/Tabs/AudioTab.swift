// FineTune/Views/Settings/Tabs/AudioTab.swift
import SwiftUI

@MainActor
struct AudioTab: View {
    @Bindable var settings: SettingsManager
    @Bindable var audioEngine: AudioEngine
    @Bindable var deviceVolumeMonitor: DeviceVolumeMonitor

    /// Memoized sorted output devices for the system-sounds picker.
    @State private var sortedOutputDevices: [AudioDevice] = []

    private var unifiedLoudnessToggleBinding: Binding<Bool> {
        Binding(
            get: {
                settings.appSettings.loudnessCompensationEnabled
                    && settings.appSettings.loudnessEqualizationEnabled
            },
            set: { isEnabled in
                settings.appSettings.setUnifiedLoudnessEnabled(isEnabled)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                volumeSection
                microphoneSection
                devicesSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .onAppear { updateSortedDevices() }
        .onChange(of: audioEngine.outputDevices) { _, _ in updateSortedDevices() }
        .onChange(of: settings.appSettings.lockInputDevice) { oldValue, newValue in
            if !oldValue && newValue {
                audioEngine.handleInputLockEnabled()
            }
        }
        .onChange(of: settings.appSettings.loudnessCompensationEnabled) { _, newValue in
            audioEngine.setLoudnessCompensationEnabled(newValue)
        }
        .onChange(of: settings.appSettings.loudnessEqualizationEnabled) { _, newValue in
            audioEngine.setLoudnessEqualizationEnabled(newValue)
        }
    }

    // MARK: - Volume

    private var volumeSection: some View {
        SettingsSection("Volume") {
            SettingsRow(
                "Default Volume",
                description: "Initial volume for new apps"
            ) {
                VolumeSlider(
                    $settings.appSettings.defaultNewAppVolume,
                    range: 0.1...1.0,
                    width: 280
                )
            }
            SettingsRowDivider()
            SettingsRow(
                "Master Volume for FineTune Audio",
                description: "Control all FineTune-managed audio with one slider. Enable media key control to use the volume keys."
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.appSettings.masterVolumeEnabled },
                    set: { audioEngine.setMasterVolumeEnabled($0) }
                ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            SettingsRowDivider()
            SettingsRow(
                "Loudness Compensation",
                description: "Boost low frequencies at low volume"
            ) {
                Toggle("", isOn: unifiedLoudnessToggleBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Devices

    private var microphoneSection: some View {
        SettingsSection("Microphone") {
            SettingsRow(
                "Lock Input Device",
                description: "Keep your selected microphone or switch automatically between your preferred microphones."
            ) {
                Toggle("", isOn: $settings.appSettings.lockInputDevice)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            if settings.appSettings.lockInputDevice {
                SettingsRowDivider()
                SettingsRow(
                    "Preferred Microphones",
                    description: "FineTune uses the first connected microphone in this list, then the built-in mic. Connect each microphone once to add it."
                ) {
                    let available = audioEngine.inputDevices.filter { device in
                        !settings.preferredMicrophones.contains { $0.uid == device.uid }
                    }
                    Menu("Add Microphone") {
                        ForEach(available) { device in
                            Button(device.name) {
                                audioEngine.setPreferredMicrophones(
                                    settings.preferredMicrophones + [PreferredMicrophone(uid: device.uid, name: device.name)]
                                )
                            }
                        }
                    }
                    .fixedSize()
                    .disabled(available.isEmpty)
                }
                ForEach(settings.preferredMicrophones) { microphone in
                    let connected = audioEngine.inputDevices.contains { $0.uid == microphone.uid }
                    SettingsRowDivider()
                    SettingsRow(microphone.name, description: connected ? nil : "Disconnected") {
                        microphoneOrderControls(microphone)
                    }
                }
            }
        }
    }

    private func microphoneOrderControls(_ microphone: PreferredMicrophone) -> some View {
        HStack(spacing: 8) {
            Button {
                movePreferredMicrophone(microphone, by: -1)
            } label: {
                Label("Move \(microphone.name) up", systemImage: "chevron.up").labelStyle(.iconOnly)
            }
            .disabled(settings.preferredMicrophones.first == microphone)
            Button {
                movePreferredMicrophone(microphone, by: 1)
            } label: {
                Label("Move \(microphone.name) down", systemImage: "chevron.down").labelStyle(.iconOnly)
            }
            .disabled(settings.preferredMicrophones.last == microphone)
            Button {
                audioEngine.setPreferredMicrophones(settings.preferredMicrophones.filter { $0 != microphone })
            } label: {
                Label("Remove \(microphone.name)", systemImage: "minus.circle").labelStyle(.iconOnly)
            }
        }
        .controlSize(.small)
    }

    private func movePreferredMicrophone(_ microphone: PreferredMicrophone, by offset: Int) {
        var microphones = settings.preferredMicrophones
        guard let index = microphones.firstIndex(of: microphone), microphones.indices.contains(index + offset) else { return }
        microphones.swapAt(index, index + offset)
        audioEngine.setPreferredMicrophones(microphones)
    }

    private var devicesSection: some View {
        SettingsSection("Devices") {
            SettingsRow(
                "System Sounds",
                description: "Where alerts and effects play"
            ) {
                SystemSoundsDevicePicker(
                    devices: sortedOutputDevices,
                    deviceIconOverrides: audioEngine.settingsManager.deviceIconOverrides,
                    selectedDeviceUID: deviceVolumeMonitor.systemDeviceUID,
                    defaultDeviceUID: deviceVolumeMonitor.defaultDeviceUID,
                    isFollowingDefault: deviceVolumeMonitor.isSystemFollowingDefault,
                    onDeviceSelected: { deviceUID in
                        if let device = sortedOutputDevices.first(where: { $0.uid == deviceUID }) {
                            deviceVolumeMonitor.setSystemDeviceExplicit(device.id)
                        }
                    },
                    onSelectFollowDefault: {
                        deviceVolumeMonitor.setSystemFollowDefault()
                    }
                )
            }
            SettingsRowDivider()
            SettingsRow(
                "Alert Volume",
                description: "Volume for alerts and notifications"
            ) {
                VolumeSlider(
                    Binding(
                        get: { deviceVolumeMonitor.alertVolume },
                        set: { deviceVolumeMonitor.setAlertVolume($0) }
                    ),
                    range: 0...1,
                    width: 280
                )
            }
            .task {
                // No CoreAudio listener for alert volume — must poll via AppleScript.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    deviceVolumeMonitor.refreshAlertVolume()
                }
            }
        }
    }

    private func updateSortedDevices() {
        sortedOutputDevices = audioEngine.prioritySortedOutputDevices
    }
}
