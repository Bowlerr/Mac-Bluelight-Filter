import SwiftUI

@main
struct RedshiftMenuBarApp: App {
    @StateObject private var controller = RedshiftController()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(controller: controller)
        } label: {
            Image(systemName: controller.isRunning ? "sun.max.fill" : "sun.max")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuPanelView: View {
    @ObservedObject var controller: RedshiftController
    @State private var showingHelp = false
    @State private var enabledToggle = false
    @State private var timingMode: TimingMode = .sunriseSunset
    @State private var showTimingSection = false
    @State private var showTemperatureSection = false
    @State private var showGammaSection = false
    @State private var showBrightnessSection = false
    @State private var showAdvancedSection = false

    private var isManualSchedule: Bool {
        timingMode == .manualSchedule
    }

    private var expandedSectionCount: Int {
        [
            showTimingSection,
            showTemperatureSection,
            showGammaSection,
            showBrightnessSection,
            showAdvancedSection
        ]
            .filter { $0 }
            .count
    }

    private var contentHeight: CGFloat {
        if showingHelp { return 420 }
        switch expandedSectionCount {
        case 0:
            return 220
        case 1:
            return 330
        case 2:
            return 430
        case 3:
            return 500
        default:
            return 580
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enabled", isOn: $enabledToggle)
            .toggleStyle(.switch)
            .onChange(of: enabledToggle) { newValue in
                if newValue != controller.isEnabled {
                    controller.setEnabled(newValue)
                }
            }

            Divider()

            ScrollView {
                if showingHelp {
                    HelpPanelView()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ExpandableSection("Timing", isExpanded: $showTimingSection) {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("Mode", selection: $timingMode) {
                                    Text("Sunrise/Sunset").tag(TimingMode.sunriseSunset)
                                    Text("Manual Schedule").tag(TimingMode.manualSchedule)
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: timingMode) { newMode in
                                    let useSchedule = (newMode == .manualSchedule)
                                    DispatchQueue.main.async {
                                        controller.settings.useSchedule = useSchedule
                                    }
                                }

                                Text(isManualSchedule
                                    ? "Manual Schedule ignores location and runs a fixed warm temperature when enabled."
                                    : "Sunrise/Sunset mode uses location to calculate day/night color transitions.")
                                .font(.footnote)
                                .foregroundColor(.secondary)

                                Divider()

                                if isManualSchedule {
                                    TimeSelectorRow(
                                        title: "Start",
                                        hour: $controller.settings.scheduleStartHour,
                                        minute: $controller.settings.scheduleStartMinute
                                    )
                                    TimeSelectorRow(
                                        title: "End",
                                        hour: $controller.settings.scheduleEndHour,
                                        minute: $controller.settings.scheduleEndMinute
                                    )
                                } else {
                                    HStack(alignment: .top, spacing: 8) {
                                        LabeledFieldRow(
                                            title: "Latitude",
                                            prompt: "0.0000",
                                            text: $controller.settings.latitude,
                                            monospaced: true
                                        )
                                        LabeledFieldRow(
                                            title: "Longitude",
                                            prompt: "0.0000",
                                            text: $controller.settings.longitude,
                                            monospaced: true
                                        )
                                    }

                                    Button(controller.isLocating ? "Locating..." : "Use Current Location") {
                                        controller.useCurrentLocation()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(controller.isLocating)
                                }
                            }
                        }

                        ExpandableSection("Color Temperature", isExpanded: $showTemperatureSection) {
                            VStack(alignment: .leading, spacing: 8) {
                                if !isManualSchedule {
                                    TemperatureSelectorRow(
                                        title: "Day",
                                        value: $controller.settings.dayTemp,
                                        range: 1000...6500,
                                        step: 100
                                    )
                                }

                                TemperatureSelectorRow(
                                    title: "Night",
                                    value: $controller.settings.nightTemp,
                                    range: 1000...4500,
                                    step: 100
                                )

                                if isManualSchedule {
                                    Text("Manual Schedule uses Night temperature while active.")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        ExpandableSection("Gamma", isExpanded: $showGammaSection) {
                            GammaEditorRow(gammaText: $controller.settings.gamma)
                        }

                        ExpandableSection("Brightness", isExpanded: $showBrightnessSection) {
                            BrightnessEditorRow(brightnessText: $controller.settings.brightness)
                        }

                        ExpandableSection("Advanced", isExpanded: $showAdvancedSection) {
                            VStack(alignment: .leading, spacing: 8) {
                                LabeledFieldRow(
                                    title: "Binary Path",
                                    prompt: "/opt/homebrew/bin/redshift",
                                    text: $controller.settings.binaryPath,
                                    monospaced: true
                                )
                                Toggle("Start at Login", isOn: $controller.settings.startAtLogin)
                                    .toggleStyle(.switch)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: contentHeight, maxHeight: contentHeight, alignment: .top)

            if !showingHelp {
                Divider()
                TemperaturePreviewRow(
                    dayTemp: controller.settings.dayTemp,
                    nightTemp: controller.settings.nightTemp,
                    gammaText: controller.settings.gamma,
                    brightnessText: controller.settings.brightness,
                    showDay: !isManualSchedule
                )
            }

            if !controller.statusMessage.isEmpty {
                Text(controller.statusMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            Divider()

            HStack {
                Button(showingHelp ? "Back" : "Help") {
                    showingHelp.toggle()
                }

                if !showingHelp {
                    Button("Reset Color") {
                        controller.resetColor()
                    }
                }

                Spacer()

                if !showingHelp {
                    Button("Apply") {
                        controller.applySettings()
                    }
                    .keyboardShortcut(.defaultAction)
                }

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .onAppear {
            enabledToggle = controller.isEnabled
            timingMode = controller.settings.useSchedule ? .manualSchedule : .sunriseSunset
        }
        .onChange(of: controller.isEnabled) { newValue in
            if enabledToggle != newValue {
                enabledToggle = newValue
            }
        }
        .onChange(of: controller.settings.useSchedule) { useSchedule in
            let newMode: TimingMode = useSchedule ? .manualSchedule : .sunriseSunset
            if timingMode != newMode {
                timingMode = newMode
            }
        }
        .padding(12)
        .frame(width: 360, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: contentHeight)
    }
}

private enum TimingMode: Hashable {
    case sunriseSunset
    case manualSchedule
}

private struct ExpandableSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    init(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 12)
                    Text(title)
                        .font(.headline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.leading, 4)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.35))
        )
    }
}

private struct LabeledFieldRow: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var monospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TimeSelectorRow: View {
    let title: String
    @Binding var hour: Int
    @Binding var minute: Int

    private var hourLabel: String {
        String(format: "%02d", hour)
    }

    private var minuteLabel: String {
        String(format: "%02d", minute)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 42, alignment: .leading)

            Picker("Hour", selection: $hour) {
                ForEach(0..<24, id: \.self) { value in
                    Text(String(format: "%02d", value)).tag(value)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 66)

            Text(":")
                .foregroundColor(.secondary)

            Picker("Minute", selection: $minute) {
                ForEach(0..<60, id: \.self) { value in
                    Text(String(format: "%02d", value)).tag(value)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 66)

            Spacer(minLength: 2)

            ControlGroup {
                Button("-15m") {
                    shift(by: -15)
                }

                Button("+15m") {
                    shift(by: 15)
                }
            }
            .controlSize(.small)
            .fixedSize()
        }
        .font(.body.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) time")
        .accessibilityValue("\(hourLabel):\(minuteLabel)")
    }

    private func shift(by minutes: Int) {
        let dayMinutes = 24 * 60
        let current = (hour * 60) + minute
        let shifted = (current + minutes + dayMinutes) % dayMinutes
        hour = shifted / 60
        minute = shifted % 60
    }
}

private struct TemperatureSelectorRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .frame(width: 50, alignment: .leading)

                Spacer(minLength: 6)

                Text("\(value)K")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.quaternary.opacity(0.45))
                    )
            }

            HStack(spacing: 8) {
                Button("-\(step)") {
                    adjust(by: -step)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minWidth: 56)
                .disabled(value <= range.lowerBound)

                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { newValue in
                            value = snapped(newValue)
                        }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: Double(step)
                )
                .controlSize(.small)

                Button("+\(step)") {
                    adjust(by: step)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minWidth: 56)
                .disabled(value >= range.upperBound)
            }

            HStack(spacing: 6) {
                quickPresetButton("Warm", value: warmPreset)
                quickPresetButton("Neutral", value: neutralPreset)
                quickPresetButton("Cool", value: coolPreset)

                Spacer(minLength: 6)

                Text("\(range.lowerBound)K-\(range.upperBound)K")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.2))
        )
    }

    @ViewBuilder
    private func quickPresetButton(_ label: String, value preset: Int) -> some View {
        Button(label) {
            value = preset
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(value == preset)
    }

    private var warmPreset: Int {
        rangedPreset(0.2)
    }

    private var neutralPreset: Int {
        rangedPreset(0.55)
    }

    private var coolPreset: Int {
        rangedPreset(0.9)
    }

    private func rangedPreset(_ position: Double) -> Int {
        let lower = Double(range.lowerBound)
        let upper = Double(range.upperBound)
        let p = min(max(position, 0.0), 1.0)
        return snapped(lower + (upper - lower) * p)
    }

    private func adjust(by delta: Int) {
        let nextValue = value + delta
        value = min(max(nextValue, range.lowerBound), range.upperBound)
    }

    private func snapped(_ rawValue: Double) -> Int {
        let quantized = Int((rawValue / Double(step)).rounded()) * step
        return min(max(quantized, range.lowerBound), range.upperBound)
    }
}

private struct TemperaturePreviewRow: View {
    let dayTemp: Int
    let nightTemp: Int
    let gammaText: String
    let brightnessText: String
    let showDay: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label("Preview", systemImage: "eyedropper.halffull")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("Approx")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
            }

            previewSection(title: "Color Temperature", symbol: "thermometer.medium") {
                HStack(spacing: 8) {
                    if showDay {
                        TemperatureSwatch(
                            title: "Day",
                            mode: .temperature(kelvin: dayTemp),
                            gamma: gammaChannels,
                            brightness: brightnessLevels.0
                        )
                    }

                    TemperatureSwatch(
                        title: "Night",
                        mode: .temperature(kelvin: nightTemp),
                        gamma: gammaChannels,
                        brightness: brightnessLevels.1
                    )
                }
            }

            previewSection(title: "Gamma", symbol: "dial.medium") {
                HStack(spacing: 8) {
                    if showDay {
                        TemperatureSwatch(
                            title: "Day",
                            mode: .gamma,
                            gamma: gammaChannels,
                            brightness: brightnessLevels.0
                        )
                    }

                    TemperatureSwatch(
                        title: "Night",
                        mode: .gamma,
                        gamma: gammaChannels,
                        brightness: brightnessLevels.1
                    )
                }
            }

        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary.opacity(0.22))
        )
    }

    @ViewBuilder
    private func previewSection<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            content()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.2))
        )
    }

    private var gammaChannels: [Double] {
        let trimmed = gammaText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return [1.0, 1.0, 1.0]
        }

        let parts = trimmed.split(separator: ":")
        guard parts.count == 3 else {
            return [1.0, 1.0, 1.0]
        }

        return parts.map { min(max(Double($0) ?? 1.0, 0.5), 2.0) }
    }

    private var brightnessLevels: (Double, Double) {
        let trimmed = brightnessText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (1.0, 1.0)
        }

        let parts = trimmed.split(separator: ":")
        if parts.count == 1 {
            let level = clampBrightness(Double(parts[0]) ?? 1.0)
            return (level, level)
        }

        let day = clampBrightness(Double(parts[0]) ?? 1.0)
        let night = clampBrightness(Double(parts[1]) ?? day)
        return (day, night)
    }

    private func clampBrightness(_ value: Double) -> Double {
        min(max(value, 0.1), 1.0)
    }
}

private struct TemperatureSwatch: View {
    enum Mode {
        case temperature(kelvin: Int)
        case gamma
    }

    let title: String
    let mode: Mode
    let gamma: [Double]
    let brightness: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)

                Spacer(minLength: 4)

                Text(detailLabel)
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(.quaternary.opacity(0.45))
                    )
            }

            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(previewColor)

                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.26), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.plusLighter)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .frame(height: 28)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.2))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailLabel: String {
        switch mode {
        case .temperature(let kelvin):
            return "\(kelvin)K  b\(formattedBrightness)"
        case .gamma:
            return "\(formattedGamma)  b\(formattedBrightness)"
        }
    }

    private var previewColor: Color {
        let corrected: RGB

        switch mode {
        case .temperature(let kelvin):
            let base = mixWithNeutral(kelvinToSRGB(kelvin), amount: 0.03)
            corrected = applyBrightness(to: base)
        case .gamma:
            if isNeutralGamma {
                corrected = applyBrightness(to: RGB(red: 1.0, green: 1.0, blue: 1.0))
            } else {
                // Mid neutral base: visible channel changes without over-saturation.
                let base = RGB(red: 0.48, green: 0.48, blue: 0.48)
                let gammaCorrected = RGB(
                    red: amplifiedGammaChannel(base: base.red, gamma: gamma[0], emphasis: 2.1),
                    green: amplifiedGammaChannel(base: base.green, gamma: gamma[1], emphasis: 2.1),
                    blue: amplifiedGammaChannel(base: base.blue, gamma: gamma[2], emphasis: 3.2)
                )
                corrected = applyBrightness(
                    to: applyGammaBias(
                        to: emphasizeChannelSeparation(gammaCorrected)
                    )
                )
            }
        }

        return Color(
            red: corrected.red,
            green: corrected.green,
            blue: corrected.blue
        )
    }

    private var formattedBrightness: String {
        String(format: "%.1f", brightness)
    }

    private var formattedGamma: String {
        String(
            format: "%.1f:%.1f:%.1f",
            gamma[0],
            gamma[1],
            gamma[2]
        )
    }

    private func kelvinToSRGB(_ kelvin: Int) -> RGB {
        let temp = min(max(Double(kelvin), 1000.0), 40000.0) / 100.0
        let red: Double
        let green: Double
        let blue: Double

        if temp <= 66 {
            red = 255
            green = 99.4708025861 * log(temp) - 161.1195681661
            if temp <= 19 {
                blue = 0
            } else {
                blue = 138.5177312231 * log(temp - 10) - 305.0447927307
            }
        } else {
            red = 329.698727446 * pow(temp - 60, -0.1332047592)
            green = 288.1221695283 * pow(temp - 60, -0.0755148492)
            blue = 255
        }

        return RGB(
            red: clampUnit(red / 255.0),
            green: clampUnit(green / 255.0),
            blue: clampUnit(blue / 255.0)
        )
    }

    private func clampUnit(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private func applyBrightness(to color: RGB) -> RGB {
        RGB(
            red: clampUnit(color.red * brightness),
            green: clampUnit(color.green * brightness),
            blue: clampUnit(color.blue * brightness)
        )
    }

    private var isNeutralGamma: Bool {
        abs(gamma[0] - 1.0) < 0.0001 &&
            abs(gamma[1] - 1.0) < 0.0001 &&
            abs(gamma[2] - 1.0) < 0.0001
    }

    private func amplifiedGammaChannel(base: Double, gamma: Double, emphasis: Double) -> Double {
        let clampedGamma = max(gamma, 0.01)
        let gammaAdjusted = pow(base, 1.0 / clampedGamma)
        let gain = gammaAdjusted / max(base, 0.01)
        let emphasizedGain = 1.0 + (gain - 1.0) * emphasis
        return clampUnit(base * emphasizedGain)
    }

    private func emphasizeChannelSeparation(_ color: RGB) -> RGB {
        let average = (color.red + color.green + color.blue) / 3.0
        let redGreenBoost = 1.5
        let blueBoost = 2.4
        return RGB(
            red: clampUnit(average + (color.red - average) * redGreenBoost),
            green: clampUnit(average + (color.green - average) * redGreenBoost),
            blue: clampUnit(average + (color.blue - average) * blueBoost)
        )
    }

    private func applyGammaBias(to color: RGB) -> RGB {
        let deltaR = gamma[0] - 1.0
        let deltaG = gamma[1] - 1.0
        let deltaB = gamma[2] - 1.0
        let scale = 0.22

        return RGB(
            red: clampUnit(color.red + deltaR * scale - deltaB * (scale * 0.35)),
            green: clampUnit(color.green + deltaG * scale - deltaB * (scale * 0.35)),
            blue: clampUnit(color.blue + deltaB * (scale * 1.35) - (deltaR + deltaG) * (scale * 0.12))
        )
    }

    private func mixWithNeutral(_ color: RGB, amount: Double) -> RGB {
        let a = clampUnit(amount)
        return RGB(
            red: color.red * (1.0 - a) + a,
            green: color.green * (1.0 - a) + a,
            blue: color.blue * (1.0 - a) + a
        )
    }
}

private struct RGB {
    let red: Double
    let green: Double
    let blue: Double
}

private struct GammaEditorRow: View {
    @Binding var gammaText: String
    var showHeader: Bool = true

    private var red: Double { parsedGamma[0] }
    private var green: Double { parsedGamma[1] }
    private var blue: Double { parsedGamma[2] }

    private var parsedGamma: [Double] {
        let trimmed = gammaText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return [1.0, 1.0, 1.0]
        }

        let parts = trimmed.split(separator: ":")
        guard parts.count == 3 else {
            return [1.0, 1.0, 1.0]
        }

        let values = parts.map { Double($0) ?? 1.0 }
        if values.count != 3 {
            return [1.0, 1.0, 1.0]
        }

        return values.map { min(max($0, 0.5), 2.0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showHeader {
                HStack {
                    Text("Gamma")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Reset") {
                        gammaText = ""
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            GammaChannelRow(
                label: "R",
                value: red,
                onChange: { updateChannel(0, $0) }
            )
            GammaChannelRow(
                label: "G",
                value: green,
                onChange: { updateChannel(1, $0) }
            )
            GammaChannelRow(
                label: "B",
                value: blue,
                onChange: { updateChannel(2, $0) }
            )

            Text(gammaPreviewText)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gammaPreviewText: String {
        if gammaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Default (1.0:1.0:1.0)"
        }
        return "Applied: \(gammaText)"
    }

    private func updateChannel(_ index: Int, _ value: Double) {
        var channels = parsedGamma
        channels[index] = min(max((value * 10).rounded() / 10, 0.5), 2.0)

        if channels.allSatisfy({ abs($0 - 1.0) < 0.0001 }) {
            gammaText = ""
            return
        }

        gammaText = String(
            format: "%.1f:%.1f:%.1f",
            channels[0],
            channels[1],
            channels[2]
        )
    }
}

private struct GammaChannelRow: View {
    let label: String
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 16, alignment: .leading)

            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: 0.5...2.0,
                step: 0.1
            )
            .controlSize(.small)

            Text(String(format: "%.1fx", value))
                .font(.body.monospacedDigit())
                .frame(width: 54, alignment: .trailing)
        }
    }
}

private struct BrightnessEditorRow: View {
    @Binding var brightnessText: String
    var showHeader: Bool = true

    private var levels: (Double, Double) {
        let trimmed = brightnessText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (1.0, 1.0) }

        let parts = trimmed.split(separator: ":")
        if parts.count == 1 {
            let value = clamp(Double(parts[0]) ?? 1.0)
            return (value, value)
        }

        let day = clamp(Double(parts[0]) ?? 1.0)
        let night = clamp(Double(parts[1]) ?? day)
        return (day, night)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showHeader {
                HStack {
                    Text("Brightness")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Reset") {
                        brightnessText = ""
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            BrightnessChannelRow(
                label: "Day",
                value: levels.0,
                onChange: { update(day: $0, night: levels.1) }
            )
            BrightnessChannelRow(
                label: "Night",
                value: levels.1,
                onChange: { update(day: levels.0, night: $0) }
            )

            Text(brightnessPreviewText)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var brightnessPreviewText: String {
        if brightnessText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Default (1.0:1.0)"
        }
        return "Applied: \(brightnessText)"
    }

    private func update(day: Double, night: Double) {
        let dayValue = clamp(day)
        let nightValue = clamp(night)

        if abs(dayValue - 1.0) < 0.0001 && abs(nightValue - 1.0) < 0.0001 {
            brightnessText = ""
            return
        }

        brightnessText = String(format: "%.1f:%.1f", dayValue, nightValue)
    }

    private func clamp(_ value: Double) -> Double {
        min(max((value * 10).rounded() / 10, 0.1), 1.0)
    }
}

private struct BrightnessChannelRow: View {
    let label: String
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 42, alignment: .leading)

            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: 0.1...1.0,
                step: 0.1
            )
            .controlSize(.small)

            Text(String(format: "%.1fx", value))
                .font(.body.monospacedDigit())
                .frame(width: 54, alignment: .trailing)
        }
    }
}

private struct HelpPanelView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("What This App Does") {
                    Text("This app runs redshift to reduce blue light and adjust color temperature throughout the day.")
                }

                GroupBox("Why Latitude/Longitude Is Needed") {
                    Text("Coordinates are only needed for Sunrise/Sunset mode. In Manual Schedule mode, the app does not use location.")
                }

                GroupBox("Why Location Permission Is Needed") {
                    Text("The app can auto-fill coordinates only if macOS allows location access. If permission is denied, enter latitude/longitude manually.")
                }

                GroupBox("Why Apply Is Needed") {
                    Text("Changing settings updates the form, but redshift keeps running with its old arguments until you press Apply and restart it with new values.")
                }

                GroupBox("Privacy") {
                    Text("Coordinates stay on your Mac in app preferences. They are only used to build local redshift command arguments.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
