import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: RedshiftController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section("Redshift") {
                    TextField("Binary Path", text: $controller.settings.binaryPath)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        TextField("Latitude", text: $controller.settings.latitude)
                            .textFieldStyle(.roundedBorder)
                        TextField("Longitude", text: $controller.settings.longitude)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("Color") {
                    Stepper(
                        value: $controller.settings.dayTemp,
                        in: 1000...6500,
                        step: 100
                    ) {
                        Text("Day Temp: \(controller.settings.dayTemp)K")
                    }

                    Stepper(
                        value: $controller.settings.nightTemp,
                        in: 1000...4500,
                        step: 100
                    ) {
                        Text("Night Temp: \(controller.settings.nightTemp)K")
                    }

                    TextField("Gamma (optional, e.g. 1.0:1.0:1.0)", text: $controller.settings.gamma)
                        .textFieldStyle(.roundedBorder)

                    TextField("Brightness (optional, e.g. 1.0:0.9)", text: $controller.settings.brightness)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Schedule") {
                    Toggle("Use Schedule", isOn: $controller.settings.useSchedule)

                    DatePicker(
                        "Start",
                        selection: scheduleBinding(
                            hour: controller.settings.scheduleStartHour,
                            minute: controller.settings.scheduleStartMinute,
                            onChange: { hour, minute in
                                controller.settings.scheduleStartHour = hour
                                controller.settings.scheduleStartMinute = minute
                            }
                        ),
                        displayedComponents: [.hourAndMinute]
                    )
                    .disabled(!controller.settings.useSchedule)

                    DatePicker(
                        "End",
                        selection: scheduleBinding(
                            hour: controller.settings.scheduleEndHour,
                            minute: controller.settings.scheduleEndMinute,
                            onChange: { hour, minute in
                                controller.settings.scheduleEndHour = hour
                                controller.settings.scheduleEndMinute = minute
                            }
                        ),
                        displayedComponents: [.hourAndMinute]
                    )
                    .disabled(!controller.settings.useSchedule)
                }

                Section("System") {
                    Toggle("Start at Login", isOn: $controller.settings.startAtLogin)
                }
            }

            HStack {
                Button("Reset Color") {
                    controller.resetColor()
                }

                Spacer()

                Button("Apply Settings") {
                    controller.applySettings()
                }
                .keyboardShortcut(.defaultAction)
            }

            if !controller.statusMessage.isEmpty {
                Text(controller.statusMessage)
                    .foregroundColor(.red)
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }

    private func scheduleBinding(
        hour: Int,
        minute: Int,
        onChange: @escaping (Int, Int) -> Void
    ) -> Binding<Date> {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return Binding<Date>(
            get: { date },
            set: { newValue in
                let comps = calendar.dateComponents([.hour, .minute], from: newValue)
                onChange(comps.hour ?? 0, comps.minute ?? 0)
            }
        )
    }
}
