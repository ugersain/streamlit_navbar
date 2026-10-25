import SwiftUI

// MARK: - Profile

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var cloud: CloudAccount
    @State private var stats: ProfileStats?
    @State private var connectors: ConnectorList?

    private var initials: String {
        let name = store.profile.name.isEmpty ? (cloud.email ?? "?") : store.profile.name
        return String(name.prefix(2)).uppercased()
    }

    private var assistantSummary: String {
        if let own = connectors?.connectors.first(where: { $0.provider == store.profile.aiProvider }) ?? connectors?.connectors.first {
            return "\(own.provider.capitalized) · using your own key"
        }
        return "Built-in parser"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                statsRow
                group("ACCOUNT") {
                    row("Personal info", icon: "person.fill", color: Pulse.routine) { PersonalInfoView() }
                    row("Password and devices", icon: "lock.fill", color: Pulse.routine) { SecurityView() }
                }
                group("YOUR PLAN") {
                    row("Body and goals", detail: "\(store.profile.calorieGoal) kcal a day", icon: "chart.line.uptrend.xyaxis", color: Pulse.fuel) { BodyGoalsView() }
                    row("Food preferences", detail: store.profile.allergies.isEmpty ? store.profile.diet : "\(store.profile.diet) · avoiding \(store.profile.allergies.joined(separator: ", ").lowercased())", icon: "fork.knife", color: Pulse.fuel) { FoodPreferencesView() }
                    row("Notifications", detail: "Quiet \(store.profile.quietStart.clockString) to \(store.profile.quietEnd.clockString)", icon: "bell.fill", color: Pulse.fuel) { NotificationsView() }
                }
                group("CONNECTIONS", highlight: true) {
                    NavigationLink { ConnectorsView() } label: {
                        HStack(spacing: 12) {
                            Circle().fill(AngularGradient(colors: Pulse.brandGradient, center: .center)).frame(width: 34, height: 34)
                                .overlay(Circle().fill(Pulse.background).frame(width: 14, height: 14))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("AI assistant").font(.subheadline.weight(.heavy)).foregroundColor(Pulse.text)
                                Text(assistantSummary).font(.caption).foregroundColor(Pulse.muted)
                            }
                            Spacer()
                            if connectors?.connectors.isEmpty == false {
                                Text("Connected").font(.caption2.weight(.heavy)).foregroundColor(.black)
                                    .padding(.horizontal, 8).padding(.vertical, 4).background(Pulse.move, in: Capsule())
                            }
                            Image(systemName: "chevron.right").foregroundColor(Pulse.muted)
                        }
                        .padding(14)
                    }
                    divider
                    status("Apple Health", "Connected")
                    divider
                    status("Apple Watch", "Paired")
                }
                group("PRIVACY AND HELP") {
                    row("Privacy and data", icon: "hand.raised.fill", color: Pulse.muted) { PrivacyView() }
                }
                Button(role: .destructive) { cloud.logout() } label: {
                    Text("Log out").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered).tint(.red)
                Text("Pulse 0.3.0 · Guidance only, not medical advice").font(.caption2).foregroundColor(Pulse.muted)
            }
            .padding(.horizontal, 20).padding(.bottom, 60)
        }
        .screenBackground()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let api = cloud.api else { return }
            stats = try? await api.stats()
            connectors = try? await api.connectors()
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Circle().stroke(Pulse.fuel.opacity(0.25), lineWidth: 5).frame(width: 96, height: 96)
                Circle().trim(from: 0, to: min(Double(stats?.streak ?? 0) / 14, 1)).stroke(Pulse.fuel, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 96, height: 96)
                Text(initials).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundColor(Pulse.power)
                    .frame(width: 78, height: 78).background(Pulse.surfaceRaised, in: Circle())
                    .frame(width: 96, height: 96)
            }
            Text(store.profile.name.isEmpty ? "Your profile" : store.profile.name).font(.system(.title2, design: .rounded).weight(.heavy))
            Text(cloud.email ?? "Using Pulse on this device only").font(.footnote).foregroundColor(Pulse.muted)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            stat("\(stats?.streak ?? 0)", "day streak", Pulse.fuel)
            stat("\(stats?.workouts ?? 0)", "workouts", Pulse.power)
            stat(String(format: "%+.1f", stats?.weightChangeKg ?? 0), "kg change", Pulse.move)
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).weight(.heavy)).foregroundColor(color)
            Text(label).font(.caption2.weight(.semibold)).foregroundColor(Pulse.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Pulse.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var divider: some View { Divider().overlay(Pulse.surfaceRaised) }

    private func group<Content: View>(_ title: String, highlight: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.heavy)).foregroundColor(Pulse.muted).padding(.leading, 6).padding(.top, 6)
            VStack(spacing: 0) { content() }
                .background(Pulse.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(highlight ? Pulse.routine.opacity(0.4) : .clear, lineWidth: 1.5))
        }
    }

    private func row<Destination: View>(_ title: String, detail: String? = nil, icon: String, color: Color,
                                        @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.subheadline.weight(.bold)).foregroundColor(color)
                    .frame(width: 34, height: 34).background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.bold)).foregroundColor(Pulse.text)
                    if let detail { Text(detail).font(.caption).foregroundColor(Pulse.muted).lineLimit(1) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundColor(Pulse.muted)
            }
            .padding(14)
        }
    }

    private func status(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(.subheadline.weight(.bold)); Spacer(); Text(value).font(.caption.weight(.bold)).foregroundColor(Pulse.move) }
            .padding(14)
    }
}

// MARK: - Personal info, body, food, notifications

struct PersonalInfoView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var cloud: CloudAccount
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var message = ""

    var body: some View {
        Form {
            Section("Name") { TextField("First name", text: $name).textContentType(.givenName) }
            if cloud.isSignedIn {
                Section("Email") {
                    TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if email.lowercased() != (cloud.email ?? "") {
                        SecureField("Password (to change your email)", text: $password).textContentType(.password)
                    }
                }
            }
            if !message.isEmpty { Text(message).font(.footnote).foregroundColor(Pulse.power) }
            Button("Save changes") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .scrollContentBackground(.hidden).screenBackground().navigationTitle("Personal info")
        .onAppear { name = store.profile.name; email = cloud.email ?? "" }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        store.update { $0.profile.name = trimmed }
        guard let api = cloud.api else { message = "Saved."; return }
        let changingEmail = email.lowercased() != (cloud.email ?? "")
        do {
            try await api.updateAccount(name: trimmed, email: changingEmail ? email : nil, currentPassword: changingEmail ? password : nil)
            password = ""
            message = "Saved."
        } catch { message = error.localizedDescription }
    }
}

struct BodyGoalsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var cloud: CloudAccount
    @State private var message = ""

    var body: some View {
        Form {
            Section("Daily targets") {
                Stepper("Calories: \(store.profile.calorieGoal)", value: bind(\.calorieGoal), in: 1000...6000, step: 50)
                Stepper("Protein: \(store.profile.proteinGoal) g", value: bind(\.proteinGoal), in: 20...400, step: 5)
                Stepper("Carbs: \(store.profile.carbsGoal) g", value: bind(\.carbsGoal), in: 0...800, step: 5)
                Stepper("Fat: \(store.profile.fatGoal) g", value: bind(\.fatGoal), in: 0...300, step: 5)
                Stepper("Active energy: \(store.profile.activeGoal) kcal", value: bind(\.activeGoal), in: 100...2000, step: 50)
            }
            if cloud.isSignedIn {
                Section {
                    Button("Recalculate from my body details") { Task { await recalc() } }
                    Text("Uses the age, height, weight and goal saved on your account. Edit them on the web for now.")
                        .font(.footnote).foregroundColor(Pulse.muted)
                }
            }
            if !message.isEmpty { Text(message).font(.footnote).foregroundColor(Pulse.power) }
        }
        .scrollContentBackground(.hidden).screenBackground().navigationTitle("Body and goals")
    }

    private func recalc() async {
        guard let api = cloud.api else { return }
        await cloud.pushNow()
        do {
            store.adopt(try await api.recalculatePlan())
            message = "Targets updated."
        } catch { message = error.localizedDescription }
    }

    private func bind(_ keyPath: WritableKeyPath<Profile, Int>) -> Binding<Int> {
        Binding(get: { store.profile[keyPath: keyPath] }, set: { value in store.update { $0.profile[keyPath: keyPath] = value } })
    }
}

struct FoodPreferencesView: View {
    @EnvironmentObject private var store: AppStore
    private let allergies = ["Peanuts", "Tree nuts", "Dairy", "Gluten", "Eggs", "Fish", "Shellfish", "Soy"]

    var body: some View {
        Form {
            Picker("Diet", selection: Binding(get: { store.profile.diet }, set: { v in store.update { $0.profile.diet = v } })) {
                ForEach(["Vegetarian", "Non-vegetarian", "Eggetarian", "Vegan"], id: \.self) { Text($0) }
            }
            Section("Allergies. We never suggest these.") {
                ForEach(allergies, id: \.self) { item in
                    Toggle(item, isOn: Binding(
                        get: { store.profile.allergies.contains(item) },
                        set: { on in store.update { snap in
                            if on { if !snap.profile.allergies.contains(item) { snap.profile.allergies.append(item) } }
                            else { snap.profile.allergies.removeAll { $0 == item } }
                        } }))
                }
            }
        }
        .scrollContentBackground(.hidden).screenBackground().navigationTitle("Food preferences")
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            DatePicker("Quiet from", selection: time(\.quietStart), displayedComponents: .hourAndMinute)
            DatePicker("Until", selection: time(\.quietEnd), displayedComponents: .hourAndMinute)
            Text("Reminders never fire inside quiet hours.").font(.footnote).foregroundColor(Pulse.muted)
        }
        .scrollContentBackground(.hidden).screenBackground().navigationTitle("Notifications")
    }

    private func time(_ keyPath: WritableKeyPath<Profile, Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: store.profile[keyPath: keyPath] / 60, minute: store.profile[keyPath: keyPath] % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.update { $0.profile[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) }
            })
    }
}

// MARK: - Password and devices

struct SecurityView: View {
    @EnvironmentObject private var cloud: CloudAccount
    @State private var current = ""
    @State private var new = ""
    @State private var sessions: [SessionInfo] = []
    @State private var message = ""
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if cloud.isSignedIn {
                Section("Change password") {
                    SecureField("Current password", text: $current).textContentType(.password)
                    SecureField("New password (8+ characters)", text: $new).textContentType(.newPassword)
                    Button("Update password") { Task { await changePassword() } }.disabled(current.isEmpty || new.count < 8)
                    Text("Other devices are signed out when you change it.").font(.footnote).foregroundColor(Pulse.muted)
                }
                Section("Signed-in devices") {
                    ForEach(sessions) { s in
                        HStack { Text(s.device); Spacer(); if s.current { Text("This device").font(.caption.weight(.bold)).foregroundColor(Pulse.move) } }
                    }
                    Button("Sign out of other devices") { Task { await revoke() } }.disabled(sessions.count < 2)
                }
                Section {
                    Button("Reset calendar link") { Task { await resetCalendar() } }
                } footer: { Text("Anyone with the link can see your workout times.") }
                Section {
                    Button("Delete my account", role: .destructive) { confirmDelete = true }
                } footer: { Text("Permanently deletes your profile, meals, workouts and any saved API key.") }
            } else {
                Text("Sign in from onboarding to manage a password and devices.").foregroundColor(Pulse.muted)
            }
            if !message.isEmpty { Text(message).font(.footnote).foregroundColor(Pulse.power) }
        }
        .scrollContentBackground(.hidden).screenBackground().navigationTitle("Password and devices")
        .task { sessions = (try? await cloud.api?.sessions()) ?? [] }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { Task { try? await cloud.deleteRemoteAccount() } }
        } message: { Text("This can't be undone.") }
    }

    private func changePassword() async {
        do {
            try await cloud.api?.changePassword(current: current, new: new)
            current = ""; new = ""; message = "Password updated."
            sessions = (try? await cloud.api?.sessions()) ?? []
        } catch { message = error.localizedDescription }
    }
    private func revoke() async {
        try? await cloud.api?.revokeOtherSessions()
        sessions = (try? await cloud.api?.sessions()) ?? []
        message = "Signed out of other devices."
    }
    private func resetCalendar() async {
        message = (try? await cloud.api?.rotateCalendar()) != nil ? "Calendar link reset. The old link no longer works." : "Couldn't reset the link."
    }
}

// MARK: - Privacy

struct PrivacyView: View {
    @EnvironmentObject private var cloud: CloudAccount
    @State private var exportURL: URL?
    @State private var message = ""

    var body: some View {
        Form {
            Section {
                Text("Health data stays on your devices. Meals are sent to the server only when you sync or ask the assistant to log them.")
                    .font(.footnote).foregroundColor(Pulse.muted)
            }
            if cloud.isSignedIn {
                Section("Your data") {
                    if let exportURL { ShareLink("Share export", item: exportURL) }
                    else { Button("Export my data") { Task { await export() } } }
                }
            }
            if !message.isEmpty { Text(message).font(.footnote).foregroundColor(Pulse.power) }
        }
        .scrollContentBackground(.hidden).screenBackground().navigationTitle("Privacy and data")
    }

    private func export() async {
        do {
            let data = try await cloud.api?.exportData() ?? Data()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-export.json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
        } catch { message = error.localizedDescription }
    }
}

// MARK: - AI connectors (bring your own key)

struct ConnectorsView: View {
    @EnvironmentObject private var cloud: CloudAccount
    @EnvironmentObject private var store: AppStore
    @State private var list: ConnectorList?
    @State private var adding: ProviderInfo?
    @State private var removing: ProviderInfo?
    @State private var error = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Connect your own AI account and Pulse will use it for voice logging and answers. Your key, your usage, your control.")
                    .font(.subheadline).foregroundColor(Pulse.muted).frame(maxWidth: .infinity, alignment: .leading)
                if !cloud.isSignedIn {
                    Text("Sign in from onboarding first. Keys are stored with your account.").font(.footnote).foregroundColor(Pulse.power)
                }
                if let list, !list.encryptionAvailable {
                    Text("Saving keys is switched off on this server because it has no encryption key set up.")
                        .font(.footnote.weight(.semibold)).foregroundColor(.red)
                }
                ForEach(list?.providers ?? []) { provider in
                    card(provider, connector: list?.connectors.first { $0.provider == provider.id })
                }
                protection
                if !error.isEmpty { Text(error).font(.footnote).foregroundColor(.red) }
            }
            .padding(.horizontal, 20).padding(.bottom, 60)
        }
        .screenBackground().navigationTitle("AI assistant").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $adding) { provider in AddKeySheet(provider: provider) { await load() } }
        .sheet(item: $removing) { provider in RemoveKeySheet(provider: provider) { await load() } }
    }

    private func load() async {
        guard let api = cloud.api else { return }
        do { list = try await api.connectors() } catch { self.error = error.localizedDescription }
    }

    private func card(_ provider: ProviderInfo, connector: ConnectorInfo?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(String(provider.name.prefix(1))).font(.headline.weight(.heavy)).foregroundColor(Pulse.fuel)
                    .frame(width: 40, height: 40).background(Pulse.surfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.name).font(.subheadline.weight(.heavy))
                    Text(connector == nil ? "Not connected" : (connector?.status == "ok" ? "Connected" : "Key rejected by provider"))
                        .font(.caption).foregroundColor(connector?.status == "rejected" ? .red : Pulse.muted)
                }
                Spacer()
                if connector == nil {
                    Button("Add key") { adding = provider }
                        .buttonStyle(.borderedProminent).tint(Pulse.fuel).foregroundColor(.black)
                        .disabled(!(list?.encryptionAvailable ?? false) || !cloud.isSignedIn)
                }
            }
            if let connector {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR KEY").font(.caption2.weight(.bold)).foregroundColor(Pulse.muted)
                    Text("••••••••••\(connector.last4)").font(.body.weight(.bold)).tracking(1)
                    Text("Never shown again").font(.caption2).foregroundColor(Pulse.muted)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Pulse.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack {
                    Button("Replace key") { adding = provider }.buttonStyle(.bordered)
                    Button("Remove", role: .destructive) { removing = provider }.buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(Pulse.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(connector == nil ? .clear : (connector?.status == "ok" ? Pulse.move : .red), lineWidth: 1.5))
    }

    private var protection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How your key is protected", systemImage: "lock.fill").font(.subheadline.weight(.heavy)).foregroundColor(Pulse.move)
            Text("Encrypted on our server and never sent back to any device, so it can't be read from the app, the web or a data export. Adding or removing a key needs your password. It's wiped if you delete the key or your account.")
                .font(.caption).foregroundColor(Pulse.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Pulse.move.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct AddKeySheet: View {
    @EnvironmentObject private var cloud: CloudAccount
    @Environment(\.dismiss) private var dismiss
    let provider: ProviderInfo
    var done: () async -> Void
    @State private var key = ""
    @State private var password = ""
    @State private var error = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("\(provider.name) API key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.none)
                        .privacySensitive()
                    Button("Paste from clipboard") { key = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                } header: { Text("Your key") } footer: { Text(provider.hint) }
                Section("Confirm with your Pulse password") {
                    SecureField("Password", text: $password).textContentType(.password)
                }
                Section {
                    Label("Checked with \(provider.name) before saving", systemImage: "checkmark.shield")
                    Label("Encrypted on our server, never shown again", systemImage: "lock")
                    Label("Only used for your own requests", systemImage: "person")
                } footer: { Text("You pay \(provider.name) for usage. Set a spending limit in their dashboard for extra safety.") }
                if !error.isEmpty { Text(error).font(.footnote).foregroundColor(.red) }
                Button(working ? "Checking…" : "Save and test") { Task { await save() } }
                    .disabled(working || key.isEmpty || password.isEmpty)
            }
            .navigationTitle("Add your key").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { wipe(); dismiss() } } }
            .onDisappear { wipe() }
        }
        .interactiveDismissDisabled(working)
    }

    private func wipe() { key = ""; password = "" }

    private func save() async {
        guard let api = cloud.api else { return }
        working = true; error = ""
        do {
            _ = try await api.saveKey(provider: provider.id, key: key, password: password)
            wipe()
            await done()
            await cloud.pull()
            dismiss()
        } catch { self.error = error.localizedDescription }
        working = false
    }
}

struct RemoveKeySheet: View {
    @EnvironmentObject private var cloud: CloudAccount
    @Environment(\.dismiss) private var dismiss
    let provider: ProviderInfo
    var done: () async -> Void
    @State private var password = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Text("The key is deleted from our server. Pulse will use the built-in parser until you add another.").font(.footnote)
                SecureField("Your Pulse password", text: $password).textContentType(.password)
                if !error.isEmpty { Text(error).font(.footnote).foregroundColor(.red) }
                Button("Remove key", role: .destructive) { Task { await remove() } }.disabled(password.isEmpty)
            }
            .navigationTitle("Remove \(provider.name) key").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func remove() async {
        do {
            try await cloud.api?.removeKey(provider: provider.id, password: password)
            password = ""
            await done()
            await cloud.pull()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
