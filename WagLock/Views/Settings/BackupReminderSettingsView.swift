import SwiftUI

struct BackupReminderSettingsView: View {
    @EnvironmentObject private var reminders: BackupReminderStore
    var body: some View {
        Form {
            Section("Backup reminders") {
                Picker("Remind me", selection: Binding(get: { reminders.frequency }, set: { reminders.setFrequency($0) })) {
                    ForEach(BackupReminderStore.Frequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("backup.reminder.frequency")
                    .accessibilityValue(reminders.frequency.title)
                if let next = reminders.nextReminder {
                    LabeledContent("Next reminder", value: next.formatted(date: .abbreviated, time: .omitted))
                }
                if let saved = reminders.lastSaved {
                    LabeledContent("Last saved to Files", value: saved.formatted(date: .abbreviated, time: .omitted))
                }
                Text("Reminders appear only after you unlock WagLock. There are no lock-screen notifications. Your schedule stays on this device.")
                    .font(.footnote)
                Text("Reminders do not create or upload backups. Saving through Files restarts the schedule; verify that your provider finishes any cloud upload.")
                    .font(.footnote)
            }
            if let error = reminders.error { Section { Text(error).foregroundStyle(ColorTheme.destructive) } }
        }
        .wagLockList().navigationTitle("Backup reminders").navigationBarTitleDisplayMode(.inline)
        .onAppear { reminders.refresh() }
    }
}
