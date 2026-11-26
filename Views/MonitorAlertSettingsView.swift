import AppKit
import SwiftUI

struct MonitorAlertSettingsView: View {
    @ObservedObject var monitor: MonitorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var permissionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Monitor alerts", systemImage: "bell.badge")
                    .font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Form {
                Section("Notify me about") {
                    Toggle("Weak signal", isOn: $monitor.alerts.weakSignal)
                    Toggle("Disconnect", isOn: $monitor.alerts.disconnect)
                    Toggle("Roaming between access points", isOn: $monitor.alerts.roam)
                    Toggle("Channel change", isOn: $monitor.alerts.channelChange)
                    Toggle("Security downgrade", isOn: $monitor.alerts.securityChange)
                    Toggle("Deauth burst", isOn: $monitor.alerts.deauthBurst)
                    Toggle("Roaming failure", isOn: $monitor.alerts.roamingFailure)
                    Toggle("Gateway MAC changed", isOn: $monitor.alerts.gatewayChange)
                    Toggle("DNS answer mismatch", isOn: $monitor.alerts.dnsMismatch)
                    Toggle("VPN dropped", isOn: $monitor.alerts.vpnDrop)
                    Toggle("Possible VPN leak", isOn: $monitor.alerts.vpnLeak)
                    Toggle("New access point since baseline", isOn: $monitor.alerts.newAccessPoint)
                }

                Section("Quiet hours") {
                    Toggle("Enable quiet hours", isOn: $monitor.alerts.quietHoursEnabled)
                    if monitor.alerts.quietHoursEnabled {
                        HStack {
                            Picker("From", selection: $monitor.alerts.quietStartHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(hourLabel(hour)).tag(hour)
                                }
                            }
                            Picker("To", selection: $monitor.alerts.quietEndHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(hourLabel(hour)).tag(hour)
                                }
                            }
                        }
                        Text("Overnight ranges are supported, for example 22:00 to 07:00.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Rate limit") {
                    Picker("Minimum interval", selection: $monitor.alerts.cooldownMinutes) {
                        Text("Off").tag(0)
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                    }
                }

                Section("Permission") {
                    Text(
                        "LanFi asks macOS for permission only when you press the button below. Notifications stay local and are never sent to a server."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    HStack {
                        Button("Allow Notifications") {
                            Task {
                                let granted = await monitor.requestNotificationPermission()
                                permissionMessage =
                                    granted
                                    ? "Notifications are allowed."
                                    : "Notifications are denied. Enable them in System Settings → Notifications → LanFi."
                            }
                        }
                        if let permissionMessage {
                            Text(permissionMessage)
                                .font(.caption)
                                .foregroundColor(
                                    permissionMessage.hasPrefix("Notifications are allowed")
                                        ? .green : .orange
                                )
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(DesignToken.Spacing.large)
        .frame(width: 480, height: 560)
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
