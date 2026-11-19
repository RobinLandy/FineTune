import AudioToolbox
import AppKit
import Foundation
import Testing
@testable import FineTune

@Suite("Optional master volume")
@MainActor
struct OptionalMasterVolumeTests {
    @Test("Existing installations default to unchanged media-key behaviour")
    func backwardCompatibleDefaults() throws {
        let old = try JSONDecoder().decode(SettingsManager.Settings.self, from: Data("{}".utf8))
        #expect(!old.appSettings.masterVolumeEnabled)
        #expect(old.masterVolume == 1)
        #expect(!old.masterMuted)
    }

    @Test("Master level and opt-in flag survive JSON encoding and decoding")
    func persistence() throws {
        var settings = SettingsManager.Settings()
        settings.appSettings.masterVolumeEnabled = true
        settings.masterVolume = 0.36
        settings.masterMuted = true
        let decoded = try JSONDecoder().decode(SettingsManager.Settings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.appSettings.masterVolumeEnabled)
        #expect(decoded.masterVolume == 0.36)
        #expect(decoded.masterMuted)
    }

    @Test("Media keys, HUD and mute affect only the shared master state")
    func controlsAndPersistence() throws {
        let fixture = MasterVolumeFixture()
        let engine = fixture.engine
        let settings = fixture.settings
        let app = fixture.app
        let output = fixture.speakers
        fixture.volume.volumes[output.id] = 0.65
        fixture.volume.muteStates[output.id] = true
        settings.setSoftwareDeviceVolume(for: output.uid, to: 0.47)
        settings.setSoftwareDeviceMuteState(for: output.uid, to: true)
        settings.setDDCVolume(for: fixture.airPods.uid, to: 42)
        engine.setLockedInputDevice(fixture.dji)
        engine.setMasterVolume(0.36)
        engine.setMasterVolumeEnabled(true)
        engine.setVolume(for: app, to: 0.7)
        engine.setMute(for: app, to: true)
        engine.setDevice(for: app, deviceUID: nil)
        let tap = try #require(fixture.tap)
        #expect(tap.masterGainAtActivation == 0.36)
        let appGain = tap.volume

        let monitor = fixture.makeMediaKeyMonitor()
        monitor.handle(.volumeUp(isRepeat: false))
        #expect(engine.masterVolume > 0.36)
        #expect(tap.masterGain == engine.masterVolume)
        monitor.writeHUDVolume(0.5)
        #expect(tap.masterGain == 0.25)
        monitor.handle(.muteToggle)
        #expect(tap.masterGain == 0)
        #expect(engine.masterVolume == 0.25)
        monitor.handle(.muteToggle)
        #expect(tap.masterGain == 0.25)
        engine.setMasterVolume(.nan)
        #expect(tap.masterGain == 0.25)
        monitor.writeHUDVolume(0)
        #expect(engine.isMasterMuted)
        engine.toggleMasterMute()
        #expect(tap.masterGain == 0.25)
        engine.setMasterMuted(true)
        engine.setMasterVolumeEnabled(false)
        #expect(tap.masterGain == 1)
        engine.setMasterVolumeEnabled(true)
        #expect(tap.masterGain == 0)

        #expect(tap.volume == appGain)
        #expect(tap.isMuted)
        #expect(tap.currentDeviceVolume == 0.65)
        #expect(tap.isDeviceMuted)
        #expect(fixture.volume.volumes[output.id] == 0.65)
        #expect(fixture.volume.muteStates[output.id] == true)
        #expect(fixture.volume.setVolumeCalls.isEmpty)
        #expect(fixture.volume.setMuteCalls.isEmpty)
        #expect(fixture.volume.setDefaultInputCalls == [fixture.dji.id])

        settings.flushSync()
        let reloaded = SettingsManager(directory: fixture.directory)
        #expect(reloaded.appSettings.masterVolumeEnabled)
        #expect(reloaded.masterVolume == 0.25)
        #expect(reloaded.masterMuted)
        #expect(reloaded.getVolume(for: app.persistenceIdentifier) == 0.7)
        #expect(reloaded.getMute(for: app.persistenceIdentifier) == true)
        #expect(reloaded.getSoftwareDeviceVolume(for: output.uid) == 0.47)
        #expect(reloaded.getSoftwareDeviceMuteState(for: output.uid))
        #expect(reloaded.getDDCVolume(for: fixture.airPods.uid) == 42)
        #expect(reloaded.preferredInputDeviceUID == fixture.dji.uid)
    }

    @Test("In default mode both media keys and the HUD still control the device")
    func disabledMediaKeysAndHUD() {
        let fixture = MasterVolumeFixture()
        let monitor = fixture.makeMediaKeyMonitor()
        monitor.handle(.volumeDown(isRepeat: false))
        monitor.writeHUDVolume(0.4)
        #expect(fixture.volume.setVolumeCalls.map(\.deviceID) == [fixture.speakers.id, fixture.speakers.id])
        #expect(fixture.engine.masterVolume == 1)
    }

    @Test("An unconfigured input lock adopts the current microphone")
    func inputLockAdoptsCurrentDefault() {
        let fixture = MasterVolumeFixture()
        fixture.engine.setMasterVolumeEnabled(true)
        fixture.volume.defaultInputDeviceUID = fixture.dji.uid
        fixture.devices.addInputDevice(fixture.airPodsMic)
        fixture.devices.onInputDeviceConnected?(fixture.airPodsMic.uid, fixture.airPodsMic.name)
        #expect(fixture.settings.lockedInputDeviceUID == fixture.dji.uid)
        #expect(fixture.settings.preferredInputDeviceUID == fixture.dji.uid)
        #expect(fixture.volume.setDefaultInputCalls.isEmpty)
    }

    @Test("Input lock restores an already connected preferred receiver at startup")
    func inputLockRestoresPreferredReceiverAtStartup() {
        let fixture = MasterVolumeFixture()
        let builtIn = AudioDevice(id: 916, uid: "built-in-mic", name: "Built-in Microphone", icon: nil, supportsAutoEQ: false)
        fixture.devices.addInputDevice(builtIn)
        fixture.volume.defaultInputDeviceUID = builtIn.uid
        fixture.settings.setLockedInputDeviceUID(builtIn.uid)
        fixture.settings.setPreferredInputDeviceUID(fixture.dji.uid)

        let engine = fixture.engine
        engine.start()
        defer { engine.stop() }

        #expect(fixture.settings.lockedInputDeviceUID == fixture.dji.uid)
        #expect(fixture.settings.preferredInputDeviceUID == fixture.dji.uid)
        #expect(fixture.volume.defaultInputDeviceUID == fixture.dji.uid)
        #expect(fixture.volume.setDefaultInputCalls == [fixture.dji.id])
    }

    @Test("Preferred microphones switch between office and home and ignore AirPods input")
    func preferredMicrophoneReconnects() async {
        let fixture = MasterVolumeFixture()
        let engine = fixture.engine
        fixture.connectInput(fixture.builtInMic)
        fixture.connectInput(fixture.airPodsMic)
        fixture.volume.defaultInputDeviceUID = fixture.builtInMic.uid
        let preferences = [fixture.dji, fixture.webcam].map { PreferredMicrophone(uid: $0.uid, name: $0.name) }
        engine.setPreferredMicrophones(preferences)
        defer { engine.stop() }
        #expect(fixture.volume.defaultInputDeviceUID == fixture.dji.uid)

        for _ in 0..<3 {
            fixture.disconnectInput(fixture.dji)
            #expect(fixture.volume.defaultInputDeviceUID == fixture.builtInMic.uid)

            fixture.connectInput(fixture.webcam)
            #expect(fixture.volume.defaultInputDeviceUID == fixture.webcam.uid)
            fixture.volume.defaultInputDeviceUID = fixture.airPodsMic.uid
            fixture.volume.onDefaultInputDeviceChanged?(fixture.airPodsMic.uid)
            await waitFor { fixture.volume.defaultInputDeviceUID == fixture.webcam.uid }
            #expect(fixture.volume.defaultInputDeviceUID == fixture.webcam.uid)

            fixture.disconnectInput(fixture.webcam)
            fixture.connectInput(fixture.dji)
            #expect(fixture.volume.defaultInputDeviceUID == fixture.dji.uid)
        }

        #expect(fixture.settings.preferredMicrophones == preferences)
        #expect(!fixture.volume.setDefaultInputCalls.contains(fixture.airPodsMic.id))
    }

    @Test("Preferred microphones persist and take precedence over a saved fallback at startup")
    func preferredMicrophoneStartup() {
        let fixture = MasterVolumeFixture()
        fixture.settings.setLockedInputDeviceUID(fixture.builtInMic.uid)
        fixture.settings.setPreferredInputDeviceUID(fixture.dji.uid)
        let preferences = [fixture.dji, fixture.webcam].map { PreferredMicrophone(uid: $0.uid, name: $0.name) }
        fixture.settings.setPreferredMicrophones(preferences)
        fixture.settings.flushSync()
        fixture.settings = SettingsManager(directory: fixture.directory)
        #expect(fixture.settings.preferredMicrophones == preferences)

        fixture.disconnectInput(fixture.dji)
        fixture.connectInput(fixture.builtInMic)
        fixture.connectInput(fixture.webcam)
        fixture.volume.defaultInputDeviceUID = fixture.builtInMic.uid
        fixture.engine.start()
        defer { fixture.engine.stop() }
        #expect(fixture.volume.defaultInputDeviceUID == fixture.webcam.uid)
        #expect(fixture.volume.setDefaultInputCalls == [fixture.webcam.id])
        #expect(fixture.settings.preferredInputDeviceUID == fixture.dji.uid)
    }

    @Test("A preferred USB microphone works at startup and after its USB location changes")
    func preferredMicrophoneChangesUSBLocation() {
        let fixture = MasterVolumeFixture()
        let original = usbWebcam(id: 918, location: "22100000")
        let moved = usbWebcam(id: 919, location: "21100000")
        let preference = PreferredMicrophone(uid: original.uid, name: original.name)
        fixture.devices.addInputDevice(fixture.builtInMic)
        fixture.devices.addInputDevice(moved)
        fixture.volume.defaultInputDeviceUID = fixture.builtInMic.uid
        fixture.settings.setPreferredMicrophones([preference])

        let engine = fixture.engine
        engine.start()
        defer { engine.stop() }
        #expect(fixture.volume.defaultInputDeviceUID == moved.uid)
        #expect(engine.connectedPreferredMicrophone(preference)?.id == moved.id)

        engine.setLockedInputDevice(fixture.builtInMic)
        fixture.disconnectInput(moved)
        fixture.connectInput(original)
        #expect(fixture.volume.defaultInputDeviceUID == original.uid)

        fixture.disconnectInput(original)
        fixture.connectInput(moved)
        #expect(fixture.volume.defaultInputDeviceUID == moved.uid)
        #expect(fixture.settings.preferredMicrophones == [preference])
    }

    @Test("Exact USB IDs win and ambiguous or unrelated devices cannot replace a preferred microphone")
    func preferredUSBMicrophoneRequiresUniqueMatch() {
        let fixture = MasterVolumeFixture()
        let original = usbWebcam(id: 918, location: "22100000")
        let moved = usbWebcam(id: 919, location: "21100000")
        let other = usbWebcam(id: 920, location: "23100000")
        let serial = usbWebcam(id: 921, location: "ABCD1234")
        let preference = PreferredMicrophone(uid: original.uid, name: original.name)
        let otherPreference = PreferredMicrophone(uid: other.uid, name: other.name)
        fixture.settings.setPreferredMicrophones([preference])
        fixture.devices.addInputDevice(moved)
        fixture.devices.addInputDevice(other)
        fixture.devices.addInputDevice(serial)
        fixture.devices.addInputDevice(fixture.webcam)
        let engine = fixture.engine
        #expect(engine.connectedPreferredMicrophone(preference) == nil)

        fixture.devices.addInputDevice(original)
        #expect(engine.connectedPreferredMicrophone(preference)?.id == original.id)
        fixture.devices.inputDevices.removeAll { $0.id == original.id || $0.id == other.id }
        #expect(engine.connectedPreferredMicrophone(preference)?.id == moved.id)

        fixture.settings.setPreferredMicrophones([preference, otherPreference])
        #expect(engine.connectedPreferredMicrophone(preference) == nil)
        fixture.settings.setPreferredMicrophones([preference])
        fixture.devices.inputDevices.removeAll { $0.id == moved.id }
        #expect(engine.connectedPreferredMicrophone(preference) == nil)
    }

    private func usbWebcam(id: AudioDeviceID, location: String) -> AudioDevice {
        AudioDevice(id: id, uid: "AppleUSBAudioEngine:Insta360:Insta360 Link 2:\(location):3",
                    name: "Insta360 Link 2", icon: nil, supportsAutoEQ: false)
    }

    @Test("Microphone order resolves overlaps and manual selection lasts until a preferred microphone reconnects")
    func preferredMicrophoneOrderAndManualSelection() {
        let fixture = MasterVolumeFixture()
        let engine = fixture.engine
        fixture.connectInput(fixture.builtInMic)
        fixture.connectInput(fixture.webcam)
        let preferences = [fixture.dji, fixture.webcam].map { PreferredMicrophone(uid: $0.uid, name: $0.name) }
        engine.setPreferredMicrophones(preferences)
        defer { engine.stop() }
        #expect(fixture.volume.defaultInputDeviceUID == fixture.dji.uid)

        engine.setPreferredMicrophones(Array(preferences.reversed()))
        #expect(fixture.volume.defaultInputDeviceUID == fixture.webcam.uid)

        engine.setLockedInputDevice(fixture.builtInMic)
        fixture.connectInput(fixture.airPodsMic)
        #expect(fixture.volume.defaultInputDeviceUID == fixture.builtInMic.uid)
        fixture.disconnectInput(fixture.webcam)
        fixture.connectInput(fixture.webcam)
        #expect(fixture.volume.defaultInputDeviceUID == fixture.webcam.uid)

        fixture.settings.appSettings.lockInputDevice = false
        fixture.disconnectInput(fixture.webcam)
        #expect(fixture.volume.defaultInputDeviceUID == fixture.webcam.uid)

        fixture.settings.appSettings.lockInputDevice = true
        engine.handleInputLockEnabled()
        #expect(fixture.volume.defaultInputDeviceUID == fixture.dji.uid)
    }

    @Test("Repeating output reconnects preserves master state and restores the locked microphone")
    func repeatedReconnectWithInputLock() async throws {
        let fixture = MasterVolumeFixture()
        let engine = fixture.engine
        fixture.settings.setDevicePriorityOrder([fixture.airPods.uid, fixture.speakers.uid])
        engine.setLockedInputDevice(fixture.dji)
        engine.setMasterVolumeEnabled(true)
        engine.setMasterVolume(0.3)
        engine.setMasterMuted(true)
        engine.setDevice(for: fixture.app, deviceUID: nil)
        let tap = try #require(fixture.tap)
        #expect(tap.masterGainAtActivation == 0)

        for _ in 0..<3 {
            fixture.devices.addOutputDevice(fixture.airPods)
            // Simulate macOS changing the output before FineTune receives the device-list event.
            fixture.volume.setDefaultDevice(fixture.airPods.id)
            fixture.devices.onDeviceConnected?(fixture.airPods.uid, fixture.airPods.name)
            await waitFor { tap.currentDeviceUID == fixture.airPods.uid }
            #expect(tap.currentDeviceUID == fixture.airPods.uid)
            #expect(tap.masterGain == 0)

            fixture.devices.addInputDevice(fixture.airPodsMic)
            fixture.devices.onInputDeviceConnected?(fixture.airPodsMic.uid, fixture.airPodsMic.name)
            fixture.volume.defaultInputDeviceUID = fixture.airPodsMic.uid
            fixture.volume.onDefaultInputDeviceChanged?(fixture.airPodsMic.uid)
            await waitFor { fixture.volume.defaultInputDeviceUID == fixture.dji.uid }
            #expect(fixture.volume.defaultInputDeviceUID == fixture.dji.uid)
            fixture.volume.onDefaultInputDeviceChanged?(fixture.dji.uid)

            engine.setMasterMuted(false)
            #expect(tap.masterGain == 0.3)
            fixture.devices.removeOutputDevice(fixture.airPods)
            fixture.devices.onDeviceDisconnected?(fixture.airPods.uid, fixture.airPods.name)
            await waitFor { tap.currentDeviceUID == fixture.speakers.uid }
            #expect(tap.currentDeviceUID == fixture.speakers.uid)
            #expect(tap.masterGain == 0.3)
            #expect(fixture.volume.defaultInputDeviceUID == fixture.dji.uid)
            fixture.devices.inputDevices.removeAll { $0.id == fixture.airPodsMic.id }
            fixture.devices.onInputDeviceDisconnected?(fixture.airPodsMic.uid, fixture.airPodsMic.name)
            engine.setMasterMuted(true)
        }
        #expect(fixture.volume.setDefaultInputCalls == Array(repeating: fixture.dji.id, count: 4))
        #expect(fixture.settings.lockedInputDeviceUID == fixture.dji.uid)
        #expect(fixture.settings.preferredInputDeviceUID == fixture.dji.uid)
        #expect(fixture.volume.setVolumeCalls.isEmpty)
        #expect(fixture.volume.setMuteCalls.isEmpty)
    }

    private func waitFor(_ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(1)
        while !condition() && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test("Crossfade ramps carry the same master gain through fade, mute and promotion")
    func crossfadeMasterRamp() {
        let source = MasterVolumeRamp(gain: 0.4, coefficient: 0.5)
        let destination = MasterVolumeRamp(gain: source.currentGain, coefficient: 0.5)
        var fade = CrossfadeState()
        fade.beginWarmup()
        fade.totalSamples = 8
        fade.beginCrossfading()
        _ = fade.updateProgress(samples: 4)
        let a = render([fade.primaryMultiplier], with: source, target: 0.4)[0]
        let b = render([fade.secondaryMultiplier], with: destination, target: 0.4)[0]
        #expect(abs(a * a + b * b - 0.16) < 0.00001)

        let silent = Array(repeating: Float(1), count: 32)
        #expect(render(silent, with: source, target: 0).last == 0)
        #expect(render(silent, with: destination, target: 0).last == 0)
        fade.complete()
        #expect(render([fade.primaryMultiplier, .nan], with: destination, target: 0) == [0, 0])
        #expect(render([fade.primaryMultiplier], with: destination, target: 0.4) == [0.2])
        #expect(render(silent, with: destination, target: 1).last == 1)
    }

    @Test("Planar streams apply identical per-frame gain and advance the ramp once")
    func planarStreamsShareEnvelope() {
        var left: [Float] = [1, 1, 1]
        var right: [Float] = [-1, -1, -1]
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { list.unsafeMutablePointer.deallocate() }
        left.withUnsafeMutableBufferPointer { leftSamples in
            right.withUnsafeMutableBufferPointer { rightSamples in
                for (index, samples) in [leftSamples, rightSamples].enumerated() {
                    list[index] = AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: UInt32(samples.count * MemoryLayout<Float>.size),
                        mData: samples.baseAddress
                    )
                }
                let ramp = MasterVolumeRamp(gain: 1, coefficient: 0.5)
                ramp.apply(to: list, targetGain: 0)
                #expect(ramp.currentGain == 0.125)
            }
        }
        #expect(left == [0.5, 0.25, 0.125])
        #expect(right == [-0.5, -0.25, -0.125])
    }

    private func render(_ samples: [Float], with ramp: MasterVolumeRamp, target: Float) -> [Float] {
        var result = samples
        result.withUnsafeMutableBufferPointer { storage in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(storage.count * MemoryLayout<Float>.size),
                mData: storage.baseAddress
            ))
            withUnsafeMutablePointer(to: &list) {
                ramp.apply(to: UnsafeMutableAudioBufferListPointer($0), targetGain: target)
            }
        }
        return result
    }

    @Test("Master attenuation preserves left-right channel proportions")
    func channelGain() {
        var samples: [Float] = [1, -0.5, 0.25, -1]
        samples.withUnsafeMutableBufferPointer { sampleBuffer in
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(sampleBuffer.count * MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer(sampleBuffer.baseAddress!)
                )
            )
            withUnsafeMutablePointer(to: &bufferList) { listPointer in
                let buffers = UnsafeMutableAudioBufferListPointer(listPointer)
                let after = MasterVolumeProcessor.process(
                    buffers, targetGain: 0.25, currentGain: 0.25, rampCoefficient: 1
                )
                #expect(after == 0.25)
            }
        }
        #expect(samples == [0.25, -0.125, 0.0625, -0.25])
    }
}

@MainActor
private final class MasterVolumeFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let devices = MockAudioDeviceMonitor()
    let speakers = AudioDevice(id: 912, uid: "speakers", name: "Speakers", icon: nil, supportsAutoEQ: false)
    let airPods = AudioDevice(id: 913, uid: "airpods", name: "AirPods", icon: nil, supportsAutoEQ: false)
    let dji = AudioDevice(id: 914, uid: "dji", name: "DJI Mic Mini 2", icon: nil, supportsAutoEQ: false)
    let airPodsMic = AudioDevice(id: 915, uid: "airpods-mic", name: "AirPods Mic", icon: nil, supportsAutoEQ: false)
    let builtInMic = AudioDevice(id: 916, uid: "built-in-mic", name: "Built-in Microphone", icon: nil, supportsAutoEQ: false)
    let webcam = AudioDevice(id: 917, uid: "webcam", name: "Insta360 Link 2", icon: nil, supportsAutoEQ: false)
    let app = AudioApp(id: 91234, processObjectIDs: [], name: "Player", icon: NSImage(), bundleID: "test.master-player")
    lazy var settings = SettingsManager(directory: directory)
    lazy var volume = MockDeviceVolumeProviding(deviceMonitor: devices)
    private(set) var tap: RecordingProcessTapController?
    lazy var engine: AudioEngine = {
        let permission = AudioRecordingPermission()
        permission.status = .authorized
        let processMonitor = StubProcessMonitor()
        processMonitor.activeApps = [app]
        return AudioEngine(
            permission: permission, settingsManager: settings, autoEQProfileManager: AutoEQProfileManager(),
            deviceProvider: devices, processMonitor: processMonitor, deviceVolumeMonitor: volume,
            tapFactory: { [weak self] app, uids, _ in
                let tap = RecordingProcessTapController(app: app, deviceUIDs: uids)
                self?.tap = tap
                return tap
            },
            isAlive: { _ in true },
            inputTransport: { [builtInMic] in $0 == builtInMic.id ? .builtIn : .unknown },
            startMonitorsAutomatically: false
        )
    }()

    init() {
        devices.addOutputDevice(speakers)
        devices.addInputDevice(dji)
        volume.setDefaultDevice(speakers.id)
        settings.appSettings.showDeviceDisconnectAlerts = false
    }

    func connectInput(_ device: AudioDevice) {
        devices.addInputDevice(device)
        devices.onInputDeviceConnected?(device.uid, device.name)
    }

    func disconnectInput(_ device: AudioDevice) {
        devices.inputDevices.removeAll { $0.uid == device.uid }
        devices.onInputDeviceDisconnected?(device.uid, device.name)
    }

    func makeMediaKeyMonitor() -> MediaKeyMonitor {
        let status = MediaKeyStatus()
        let popup = PopupVisibilityService()
        popup.isVisible = true
        let hud = HUDWindowController(settingsManager: settings, mediaKeyStatus: status, popupVisibility: popup)
        return MediaKeyMonitor(
            decoder: StubMediaKeyDecoder(), audioEngine: engine, settingsManager: settings,
            accessibility: MockAccessibilityTrustProviding(isTrusted: true),
            hudController: hud, popupVisibility: popup, mediaKeyStatus: status
        )
    }
}
