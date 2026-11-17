import SwiftUI
import AVFoundation
import AppKit

// Native Core Audio DSP. The graph is an estimate; Apple's AU does the actual processing.
enum BandKind: String, Codable, CaseIterable, Identifiable {
    case peak = "Peak", lowShelf = "Low Shelf", highShelf = "High Shelf", highPass = "High Pass", lowPass = "Low Pass"
    var id: String { rawValue }
    var changesGain: Bool { self == .peak || self == .lowShelf || self == .highShelf }
    var auType: AVAudioUnitEQFilterType {
        switch self {
        case .peak: return .parametric
        case .lowShelf: return .lowShelf
        case .highShelf: return .highShelf
        case .highPass: return .highPass
        case .lowPass: return .lowPass
        }
    }
}

struct EQBand: Codable, Equatable, Identifiable {
    var id: Int
    var kind: BandKind = .peak
    var frequency: Double
    var gain: Double = 0
    var q: Double = 1
    var enabled: Bool = true
}

struct EQProfile: Codable, Equatable {
    var formatVersion: Int = 1
    var preamp: Double = -6
    var enabled: Bool = true
    var bands: [EQBand] = EQProfile.defaultBands()
    static func defaultBands() -> [EQBand] {
        [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000].enumerated().map {
            EQBand(id: $0.offset, frequency: Double($0.element))
        }
    }
    static func valid(_ p: EQProfile) -> Bool {
        p.formatVersion == 1 && p.preamp.isFinite && (-30...12).contains(p.preamp) && p.bands.count == 10 &&
        Set(p.bands.map(\.id)) == Set(0..<10) && p.bands.allSatisfy {
            $0.frequency.isFinite && (20...20000).contains($0.frequency) &&
            $0.gain.isFinite && (-18...18).contains($0.gain) &&
            $0.q.isFinite && (0.2...12).contains($0.q)
        }
    }
}

final class AudioModel: ObservableObject {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let equalizer = AVAudioUnitEQ(numberOfBands: 10)
    @Published private(set) var profile = EQProfile()
    @Published var isPlaying = false
    @Published var filename = "No audio file selected"
    @Published var errorMessage: String?
    @Published var presetName = "Flat"
    @Published var activeSlot = "A"
    private var slotA = EQProfile()
    private var slotB = EQProfile()
    private var file: AVAudioFile?
    private var generation: UInt64 = 0

    init() {
        engine.attach(player)
        engine.attach(equalizer)
        engine.connect(player, to: equalizer, format: nil)
        engine.connect(equalizer, to: engine.mainMixerNode, format: nil)
        applyToEngine()
        do { try engine.start() }
        catch { errorMessage = "Audio engine failed: \(error.localizedDescription)" }
    }

    private func applyToEngine() {
        equalizer.bypass = !profile.enabled
        equalizer.globalGain = Float(profile.preamp)
        for band in profile.bands {
            let au = equalizer.bands[band.id]
            au.filterType = band.kind.auType
            au.frequency = Float(band.frequency)
            // Core Audio uses octaves, while the UI exposes conventional Q.
            let octaves = 2 * asinh(1 / (2 * band.q)) / log(2)
            au.bandwidth = Float(min(4, max(0.05, octaves)))
            au.gain = Float(band.gain)
            au.bypass = !band.enabled
        }
    }

    func updateBand(_ index: Int, _ change: (inout EQBand) -> Void) {
        guard profile.bands.indices.contains(index) else { return }
        change(&profile.bands[index])
        applyToEngine()
        presetName = "Custom"
        rememberSlot()
    }
    func setPreamp(_ value: Double) {
        profile.preamp = value
        applyToEngine()
        rememberSlot()
    }
    func setEnabled(_ enabled: Bool) {
        profile.enabled = enabled
        applyToEngine()
        rememberSlot()
    }
    private func rememberSlot() { if activeSlot == "A" { slotA = profile } else { slotB = profile } }
    func switchSlot(_ name: String) {
        guard name == "A" || name == "B" else { return }
        rememberSlot()
        activeSlot = name
        profile = (name == "A" ? slotA : slotB)
        applyToEngine()
    }
    func copyToOtherSlot() {
        if activeSlot == "A" { slotB = profile } else { slotA = profile }
    }
    func setProfile(_ incoming: EQProfile, name: String) {
        guard EQProfile.valid(incoming) else { errorMessage = "Invalid EQ profile."; return }
        profile = incoming
        applyToEngine()
        presetName = name
        rememberSlot()
        errorMessage = nil
    }
    func applyPreset(_ name: String) {
        guard name != "Custom" else { return }
        var p = EQProfile()
        switch name {
        case "Warm": p.bands[1].gain = 2.5; p.bands[3].gain = 1.5; p.bands[7].gain = -1.0
        case "Presence": p.bands[3].gain = -1; p.bands[6].gain = 2; p.bands[7].gain = 2.5
        case "Bass": p.bands[0].kind = .lowShelf; p.bands[0].frequency = 100; p.bands[0].gain = 4
        case "Vocal": p.bands[1].kind = .highPass; p.bands[1].frequency = 80; p.bands[4].gain = -2; p.bands[6].gain = 2
        default: break
        }
        setProfile(p, name: name)
    }
    func saveProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TROLLfx-EQ-\(presetName).json"
        panel.allowedFileTypes = ["json"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try JSONEncoder.pretty.encode(profile).write(to: url, options: .atomic); errorMessage = nil }
        catch { errorMessage = "Save failed: \(error.localizedDescription)" }
    }
    func loadProfile() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(EQProfile.self, from: data)
            setProfile(decoded, name: url.deletingPathExtension().lastPathComponent)
        } catch { errorMessage = "Load failed: \(error.localizedDescription)" }
    }
    func openAudio() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["wav", "aif", "aiff", "caf", "m4a", "mp3"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            stop()
            file = try AVAudioFile(forReading: url)
            filename = url.lastPathComponent
            errorMessage = nil
            play()
        } catch { errorMessage = "Cannot open audio: \(error.localizedDescription)" }
    }
    func play() {
        guard let file = file else { return }
        if !engine.isRunning {
            do { try engine.start() }
            catch { errorMessage = "Cannot start audio: \(error.localizedDescription)"; return }
        }
        if player.isPlaying { return }
        generation &+= 1
        let current = generation
        // Reopen to guarantee a fresh read position when restarting a finished track.
        do {
            let replayFile = try AVAudioFile(forReading: file.url)
            self.file = replayFile
            player.scheduleFile(replayFile, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self, self.generation == current else { return }
                    self.player.stop()
                    self.isPlaying = false
                }
            }
            player.play()
            isPlaying = true
        } catch { errorMessage = "Playback failed: \(error.localizedDescription)" }
    }
    func stop() {
        generation &+= 1
        player.stop()
        isPlaying = false
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
}

struct ResponseGraph: View {
    let profile: EQProfile
    private func estimatedGain(at hz: Double) -> Double {
        guard profile.enabled else { return 0 }
        var db = profile.preamp
        for b in profile.bands where b.enabled {
            let ratio = log2(hz / b.frequency)
            switch b.kind {
            case .peak:
                let width = 2 * asinh(1 / (2 * b.q)) / log(2)
                db += b.gain * exp(-0.5 * pow(ratio / max(width / 2, 0.03), 2))
            case .lowShelf: db += b.gain / (1 + exp(min(40, max(-40, ratio * 5))))
            case .highShelf: db += b.gain / (1 + exp(min(40, max(-40, -ratio * 5))))
            case .highPass: db += -10 * log10(1 + pow(b.frequency / hz, 4))
            case .lowPass: db += -10 * log10(1 + pow(hz / b.frequency, 4))
            }
        }
        return db
    }
    var body: some View {
        Canvas { context, size in
            let width = max(1, size.width)
            for db in stride(from: -24.0, through: 24.0, by: 6) {
                let y = size.height * CGFloat((24 - db) / 48)
                var path = Path(); path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: width, y: y))
                context.stroke(path, with: .color(db == 0 ? .gray : .gray.opacity(0.25)), lineWidth: 1)
            }
            for freq in [20.0, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000] {
                let x = width * CGFloat(log10(freq / 20) / 3)
                var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.gray.opacity(0.18)), lineWidth: 1)
            }
            var curve = Path()
            for pixel in 0...Int(width) {
                let x = CGFloat(pixel)
                let hz = 20 * pow(1000, Double(x / width))
                let db = min(24, max(-24, estimatedGain(at: hz)))
                let y = size.height * CGFloat((24 - db) / 48)
                if pixel == 0 { curve.move(to: CGPoint(x: x, y: y)) }
                else { curve.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(curve, with: .color(.green), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .overlay(alignment: .topLeading) { Text("+24 dB").padding(5).font(.caption2).foregroundColor(.gray) }
        .overlay(alignment: .bottomLeading) { Text("−24 dB    20 Hz").padding(5).font(.caption2).foregroundColor(.gray) }
        .overlay(alignment: .bottomTrailing) { Text("20 kHz").padding(5).font(.caption2).foregroundColor(.gray) }
        .background(Color.black).cornerRadius(9)
    }
}

struct BandEditor: View {
    let band: EQBand
    let update: (@escaping (inout EQBand) -> Void) -> Void
    private var freqLog: Binding<Double> {
        Binding(get: { log2(band.frequency) }, set: { value in update { $0.frequency = min(20000, max(20, pow(2, value))) } })
    }
    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { band.enabled }, set: { v in update { $0.enabled = v } }))
                .labelsHidden().frame(width: 30)
            Text(String(format: "%02d", band.id + 1)).font(.system(.body, design: .monospaced)).frame(width: 28)
            Picker("Type", selection: Binding(get: { band.kind }, set: { v in update { $0.kind = v } })) {
                ForEach(BandKind.allCases) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(width: 124)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "%.0f Hz", band.frequency)).font(.system(.caption, design: .monospaced))
                Slider(value: freqLog, in: log2(20)...log2(20000))
            }.frame(minWidth: 160)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "%+.1f dB", band.gain)).font(.system(.caption, design: .monospaced))
                Slider(value: Binding(get: { band.gain }, set: { v in update { $0.gain = v } }), in: -18...18)
                    .disabled(!band.kind.changesGain)
            }.frame(width: 145)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "Q %.2f", band.q)).font(.system(.caption, design: .monospaced))
                Slider(value: Binding(get: { log2(band.q) }, set: { v in update { $0.q = pow(2, v) } }), in: log2(0.2)...log2(12))
            }.frame(width: 135)
        }
        .opacity(band.enabled ? 1 : 0.45)
        .padding(.vertical, 2)
    }
}

struct ContentView: View {
    @StateObject private var audio = AudioModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text("TROLLfx  /  PARAMETRIC EQ").font(.system(size: 25, weight: .bold, design: .monospaced)).foregroundColor(.green)
                    Text("INTEL MAC • MONTEREY 12 • CORE AUDIO").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("Open Audio…") { audio.openAudio() }
                Button(audio.isPlaying ? "Stop" : "Play") { audio.isPlaying ? audio.stop() : audio.play() }
            }
            Text(audio.filename).font(.caption).lineLimit(1).foregroundColor(.secondary)
            ResponseGraph(profile: audio.profile).frame(height: 210)
            HStack {
                Toggle("EQ enabled", isOn: Binding(get: { audio.profile.enabled }, set: { audio.setEnabled($0) }))
                Spacer()
                Text("PREAMP")
                Slider(value: Binding(get: { audio.profile.preamp }, set: { audio.setPreamp($0) }), in: -30...12).frame(width: 140)
                Text(String(format: "%+.1f dB", audio.profile.preamp)).monospacedDigit().frame(width: 80)
                Picker("Preset", selection: Binding(get: { audio.presetName }, set: { audio.applyPreset($0) })) {
                    ForEach(["Flat", "Warm", "Presence", "Bass", "Vocal", "Custom"], id: \.self) { Text($0) }
                }.frame(width: 175)
            }
            Divider()
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(audio.profile.bands) { band in
                        BandEditor(band: band) { change in audio.updateBand(band.id, change) }
                        if band.id < 9 { Divider() }
                    }
                }
            }.frame(minHeight: 250)
            Divider()
            HStack {
                Text("A/B")
                Picker("Slot", selection: Binding(get: { audio.activeSlot }, set: { audio.switchSlot($0) })) {
                    Text("A").tag("A"); Text("B").tag("B")
                }.pickerStyle(SegmentedPickerStyle()).frame(width: 105)
                Button("Copy to other") { audio.copyToOtherSlot() }
                Spacer()
                Button("Load EQ…") { audio.loadProfile() }
                Button("Save EQ…") { audio.saveProfile() }
            }
            if let error = audio.errorMessage { Text(error).foregroundColor(.red).font(.caption) }
            Text("Standalone local-file player • Q approximated via octave bandwidth • Graph is estimated, not measured • Reduce preamp to prevent clipping")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(20).frame(minWidth: 920, minHeight: 740)
    }
}

@main
struct TROLLfxMacEQApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
