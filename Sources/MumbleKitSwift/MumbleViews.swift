// Copyright 2024 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import SwiftUI
import MumbleKit

#if os(iOS)

// MARK: - Root Navigation

public struct MumbleRootView: View {
    @StateObject private var client = MumbleClient()
    @StateObject private var favoritesStore = FavoritesStore()
    @StateObject private var settings = MumbleSettings.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            switch client.connectionState {
            case .disconnected:
                StartView(client: client, favoritesStore: favoritesStore)
            case .failed(let message):
                StartView(client: client, favoritesStore: favoritesStore)
                    .overlay(alignment: .top) {
                        Text(message)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.red, in: .capsule)
                            .padding()
                    }
            case .connecting:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Verbinde…").foregroundStyle(.secondary)
                }
                .navigationTitle("Verbinde")
            case .connected:
                MumbleServerView(client: client)
                    .environmentObject(settings)
            }
        }
    }
}

// MARK: - Start Screen

private struct StartView: View {
    @ObservedObject var client: MumbleClient
    @ObservedObject var favoritesStore: FavoritesStore
    @ObservedObject private var settings = MumbleSettings.shared
    @State private var showSettings = false

    var body: some View {
        TabView {
            if favoritesStore.favorites.isEmpty {
                Tab("Direkte Verbindung", systemImage: "network") {
                    MumbleConnectView(client: client, favoritesStore: favoritesStore)
                }
                Tab("Favoriten", systemImage: "star.fill") {
                    FavoritesView(client: client, favoritesStore: favoritesStore)
                }
            } else {
                Tab("Favoriten", systemImage: "star.fill") {
                    FavoritesView(client: client, favoritesStore: favoritesStore)
                }
                Tab("Direkte Verbindung", systemImage: "network") {
                    MumbleConnectView(client: client, favoritesStore: favoritesStore)
                }
            }
        }
        .navigationTitle("Mumble")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(client: client, settings: settings)
        }
    }
}

// MARK: - Connect Screen

public struct MumbleConnectView: View {
    @ObservedObject public var client: MumbleClient
    @ObservedObject var favoritesStore: FavoritesStore
    @State private var host = ""
    @State private var port = "64738"
    @State private var username = ""
    @State private var password = ""
    @State private var favoriteName = ""
    @State private var showSaveFavorite = false

    public init(client: MumbleClient, favoritesStore: FavoritesStore = FavoritesStore()) {
        self.client = client
        self.favoritesStore = favoritesStore
    }

    public var body: some View {
        Form {
            Section("Server") {
                TextField("Hostname oder IP", text: $host)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Port", text: $port).keyboardType(.numberPad)
            }
            Section("Konto") {
                TextField("Benutzername", text: $username)
                    .textContentType(.username).autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Passwort (optional)", text: $password)
                    .textContentType(.password)
            }
            Section {
                Button {
                    client.connect(to: host, port: UInt(port) ?? 64738, username: username, password: password)
                } label: {
                    HStack { Spacer(); Text("Verbinden").bold(); Spacer() }
                }
                .disabled(host.isEmpty || username.isEmpty)

                Button { showSaveFavorite = true } label: {
                    HStack { Spacer(); Label("Als Favorit speichern", systemImage: "star"); Spacer() }
                }
                .disabled(host.isEmpty || username.isEmpty)
            }
        }
        .alert("Favorit speichern", isPresented: $showSaveFavorite) {
            TextField("Name", text: $favoriteName)
            Button("Speichern") {
                favoritesStore.add(ServerFavorite(
                    name: favoriteName.isEmpty ? host : favoriteName,
                    host: host, port: UInt(port) ?? 64738,
                    username: username, password: password))
                favoriteName = ""
            }
            Button("Abbrechen", role: .cancel) { favoriteName = "" }
        } message: { Text("Gib dem Server einen Namen.") }
    }
}

// MARK: - Favorites Screen

private struct FavoritesView: View {
    @ObservedObject var client: MumbleClient
    @ObservedObject var favoritesStore: FavoritesStore

    var body: some View {
        Group {
            if favoritesStore.favorites.isEmpty {
                ContentUnavailableView(
                    "Keine Favoriten",
                    systemImage: "star.slash",
                    description: Text("Fuege Server ueber \"Direkte Verbindung\" als Favorit hinzu.")
                )
            } else {
                List {
                    ForEach(favoritesStore.favorites) { fav in
                        FavoriteRow(fav: fav, client: client, favoritesStore: favoritesStore)
                    }
                    .onDelete { favoritesStore.remove(at: $0) }
                }
                .toolbar { EditButton() }
            }
        }
        .navigationTitle("Favoriten")
    }
}

private struct FavoriteRow: View {
    let fav: ServerFavorite
    @ObservedObject var client: MumbleClient
    @ObservedObject var favoritesStore: FavoritesStore
    @State private var isEditing = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(fav.name).font(.headline)
                Text("\(fav.host):\(fav.port)").font(.caption).foregroundStyle(.secondary)
                Text(fav.username).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Button { client.connect(with: fav) } label: {
                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                if let idx = favoritesStore.favorites.firstIndex(where: { $0.id == fav.id }) {
                    favoritesStore.remove(at: IndexSet(integer: idx))
                }
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            Button { isEditing = true } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .sheet(isPresented: $isEditing) {
            EditFavoriteSheet(favorite: fav, favoritesStore: favoritesStore)
        }
    }
}

private struct EditFavoriteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var favoritesStore: FavoritesStore

    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String

    init(favorite: ServerFavorite, favoritesStore: FavoritesStore) {
        self.favoritesStore = favoritesStore
        self._name = State(initialValue: favorite.name)
        self._host = State(initialValue: favorite.host)
        self._port = State(initialValue: String(favorite.port))
        self._username = State(initialValue: favorite.username)
        self._password = State(initialValue: favorite.password)
        self._editedFavorite = State(initialValue: favorite)
    }

    @State private var editedFavorite: ServerFavorite

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $name)
                    TextField("Hostname oder IP", text: $host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $port).keyboardType(.numberPad)
                }
                Section("Konto") {
                    TextField("Benutzername", text: $username)
                        .textContentType(.username).autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Passwort (optional)", text: $password)
                        .textContentType(.password)
                }
            }
            .navigationTitle("Favorit bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        var updated = editedFavorite
                        updated.name = name.isEmpty ? host : name
                        updated.host = host
                        updated.port = UInt(port) ?? 64738
                        updated.username = username
                        updated.password = password
                        favoritesStore.update(updated)
                        dismiss()
                    }
                    .disabled(host.isEmpty || username.isEmpty)
                }
            }
        }
    }
}

// MARK: - Server Screen

public struct MumbleServerView: View {
    @ObservedObject public var client: MumbleClient
    @EnvironmentObject private var settings: MumbleSettings
    @State private var showSettings = false
    @State private var showChat = false

    public init(client: MumbleClient) { self.client = client }

    public var body: some View {
        Group {
            if let root = client.rootChannel {
                List { ChannelTreeView(channel: root, client: client) }
            } else {
                ProgressView("Lade…")
            }
        }
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Trennen", role: .destructive) { client.disconnect() }
                    .tint(.red)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                // Chat icon (left)
                Button { showChat = true; client.markChatRead() } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bubble.left.and.bubble.right")
                        if client.unreadCount > 0 {
                            Text("\(min(client.unreadCount, 99))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(.red, in: .circle)
                                .offset(x: 6, y: -6)
                        }
                    }
                }

                Spacer()

                // Center: PTT mic button (visible only in push-to-talk mode, always in layout)
                Button {
                    client.setTalking(!client.isTalking)
                } label: {
                    ZStack {
                        Circle()
                            .fill(client.isTalking ? Color.green.opacity(0.2) : Color.secondary.opacity(0.1))
                            .animation(.easeInOut(duration: 0.3), value: client.isTalking)
                        Image(systemName: client.isTalking ? "mic.fill" : "mic")
                            .font(.title2)
                            .foregroundStyle(client.isTalking ? .green : .primary)
                            .scaleEffect(client.isTalking ? 1.2 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: client.isTalking)
                    }
                    .frame(width: 64, height: 64)
                }
                .buttonStyle(.plain)
                .opacity(settings.transmitMode == .pushToTalk ? 1 : 0)
                .disabled(settings.transmitMode != .pushToTalk)

                Spacer()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(client: client, settings: settings)
        }
        .sheet(isPresented: $showChat) {
            ChatSheet(client: client)
        }
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @ObservedObject var client: MumbleClient
    @ObservedObject var settings: MumbleSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Sendemodus") {
                    ForEach(TransmitMode.allCases) { mode in
                        Button {
                            settings.transmitMode = mode
                            client.applyTransmitMode(mode)
                        } label: {
                            HStack {
                                Label(mode.rawValue, systemImage: mode.systemImage)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if settings.transmitMode == mode {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }

                Section {
                    Text(settings.transmitMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if settings.transmitMode == .voiceActivity {
                    Section("Auslöseschwelle") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Schwellwert")
                                Spacer()
                                Text(String(format: "%.0f%%", settings.vadThreshold * 100))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $settings.vadThreshold, in: 0.3...0.88) {
                                Text("Schwellwert")
                            } minimumValueLabel: {
                                Text("Sensitiv").font(.caption2)
                            } maximumValueLabel: {
                                Text("Streng").font(.caption2)
                            } onEditingChanged: { editing in
                                if !editing { client.applyTransmitMode(settings.transmitMode) }
                            }
                        }
                        Text("Basiert auf Lautstärke. Niedrig: auch leise Töne. Hoch: nur deutliche Sprache.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("Mikrofon-Pegel") {
                        VADMeterView(threshold: settings.vadThreshold, isTalking: client.isTalking)
                    }
                }

                Section("Mikrofon-Eingang") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Eingangspegel")
                            Spacer()
                            Text(String(format: "%.0f%%", settings.micInputGain * 100))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.micInputGain, in: 0.1...1.0) {
                            Text("Eingangspegel")
                        } minimumValueLabel: {
                            Text("Leise").font(.caption2)
                        } maximumValueLabel: {
                            Text("Laut").font(.caption2)
                        } onEditingChanged: { editing in
                            if !editing { client.applyTransmitMode(settings.transmitMode) }
                        }
                    }
                    Text("Steuert den Mikrofonverstärker (AGC-Ziel). Bei 50% ist der Pegel moderat; höher = lauter für andere.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Rauschunterdrückung") {
                    Picker("Stärke", selection: $settings.noiseSuppression) {
                        Text("Schwach (-15 dB)").tag(-15)
                        Text("Mittel (-30 dB)").tag(-30)
                        Text("Stark (-45 dB)").tag(-45)
                        Text("Maximum (-60 dB)").tag(-60)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: settings.noiseSuppression) { _, _ in
                        client.applyTransmitMode(settings.transmitMode)
                    }
                    Text("Höhere Unterdrückung filtert mehr Umgebungsgeräusche, kann aber Stimme leicht dämpfen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if client.connectionState == .connected {
                    Section("Verbindungsinfo") {
                        ClientInfoView(client: client)
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Client Info

private struct ClientInfoView: View {
    @ObservedObject var client: MumbleClient

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    func pingColor(_ ms: Float) -> Color {
        if ms <= 0.5 { return .secondary }
        if ms < 80   { return .green }
        if ms < 150  { return .yellow }
        return .red
    }

    var duration: String {
        let secs = Int(client.connectionDuration)
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        LabeledContent("Server", value: client.serverAddress)
        LabeledContent("TCP-Ping") {
            Text(client.tcpPingMs > 0.5 ? String(format: "%.0f ms", client.tcpPingMs) : "Warte…")
                .foregroundStyle(pingColor(client.tcpPingMs))
        }
        LabeledContent("UDP-Ping") {
            Group {
                if client.udpPingMs > 0.5 {
                    Text(String(format: "%.0f ms", client.udpPingMs))
                        .foregroundStyle(pingColor(client.udpPingMs))
                } else if client.connectionDuration > 15 {
                    Text(client.udpAvailable ? "—" : "TCP-Tunnel")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Warte…").foregroundStyle(.secondary)
                }
            }
        }
        LabeledContent("Paketverlust") {
            Text("\(client.udpLostPackets) Pakete")
        }
        LabeledContent("Verbunden seit", value: duration)
            .onReceive(timer) { now = $0 }
    }
}

// MARK: - Chat Sheet

private struct ChatSheet: View {
    @ObservedObject var client: MumbleClient
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var selectedTab = 0

    var channelMessages: [ChatMessage] {
        client.chatMessages.filter { !$0.isPrivate }
    }

    var privateMessages: [ChatMessage] {
        client.chatMessages.filter { $0.isPrivate }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Kanal").tag(0)
                    Text("Privat").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                let messages = selectedTab == 0 ? channelMessages : privateMessages

                if messages.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        selectedTab == 0 ? "Keine Nachrichten" : "Keine privaten Nachrichten",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(messages) { msg in
                                    ChatBubble(msg: msg, localSession: client.localUser?.session() ?? 0)
                                        .id(msg.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let last = messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }

                Divider()

                // Input (only for channel chat)
                if selectedTab == 0, let channel = client.localUser?.channel() {
                    HStack(spacing: 8) {
                        TextField("Nachricht…", text: $messageText)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            client.sendMessage(messageText, toChannel: channel)
                            messageText = ""
                        } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

private struct ChatBubble: View {
    let msg: ChatMessage
    let localSession: UInt

    var isOwn: Bool { msg.senderSession == localSession }

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 60) }
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 2) {
                if !isOwn {
                    Text(msg.senderName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(msg.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isOwn ? Color.blue : Color.secondary.opacity(0.15), in: .rect(cornerRadius: 12))
                    .foregroundStyle(isOwn ? .white : .primary)
                Text(msg.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !isOwn { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Channel Tree

private struct ChannelTreeView: View {
    let channel: MKChannel
    @ObservedObject var client: MumbleClient

    var users: [MKUser] { (channel.users() as? [MKUser]) ?? [] }
    var subchannels: [MKChannel] { (channel.channels() as? [MKChannel]) ?? [] }
    var isLocalChannel: Bool { client.localUser?.channel()?.channelId() == channel.channelId() }
    var isListening: Bool { client.listenedChannelIds.contains(UInt(channel.channelId())) }

    var body: some View {
        Section {
            ForEach(users, id: \.self) { user in
                UserRow(user: user, client: client)
            }
            ForEach(subchannels, id: \.self) { sub in
                ChannelTreeView(channel: sub, client: client)
            }
        } header: {
            Button {
                if !isLocalChannel { client.joinChannel(channel) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isLocalChannel ? "speaker.wave.2.fill" : "speaker.wave.2")
                        .foregroundStyle(isLocalChannel ? .green : .secondary)
                    Text(channel.channelName() ?? "Channel")
                        .foregroundStyle(isLocalChannel ? .green : .primary)
                        .bold(isLocalChannel)
                    Spacer()
                    if isListening {
                        Image(systemName: "ear").font(.caption).foregroundStyle(.blue)
                    }
                    if !isLocalChannel {
                        Image(systemName: "arrow.right.circle").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .textCase(nil)
            .font(.headline)
            .contextMenu {
                if !isLocalChannel {
                    Button { client.joinChannel(channel) } label: {
                        Label("Beitreten", systemImage: "arrow.right.circle")
                    }
                }
                Button { client.toggleListenChannel(channel) } label: {
                    Label(isListening ? "Nicht mehr zuhören" : "Zuhören",
                          systemImage: isListening ? "ear.trianglebadge.exclamationmark" : "ear")
                }
            }
        }
    }
}

// MARK: - User Row

private struct UserRow: View {
    let user: MKUser
    @ObservedObject var client: MumbleClient
    @State private var showKickAlert = false
    @State private var showBanAlert = false
    @State private var showMoveSheet = false
    @State private var moderationReason = ""
    @State private var talkPulse = false

    var isLocal: Bool { user.session() == client.localUser?.session() }
    var isTalkingLocally: Bool { isLocal && client.isTalking }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: talkIcon).foregroundStyle(talkColor).frame(width: 20)
            Text(user.userName() ?? "Unbekannt").bold(isLocal)
            if isLocal { Text("(du)").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if user.isMuted() || user.isSelfMuted() {
                Image(systemName: "mic.slash.fill").foregroundStyle(.red).font(.caption)
            }
            if user.isDeafened() || user.isSelfDeafened() {
                Image(systemName: "ear.trianglebadge.exclamationmark").foregroundStyle(.orange).font(.caption)
            }
        }
        .contextMenu {
            if !isLocal {
                Button {
                    client.setMuted(!user.isMuted(), forUser: user)
                } label: {
                    Label(user.isMuted() ? "Entstummschalten" : "Stummschalten",
                          systemImage: user.isMuted() ? "mic.fill" : "mic.slash")
                }
                Button { showMoveSheet = true } label: {
                    Label("Verschieben", systemImage: "arrow.right.circle")
                }
                Divider()
                Button(role: .destructive) { moderationReason = ""; showKickAlert = true } label: {
                    Label("Kicken", systemImage: "person.badge.minus")
                }
                Button(role: .destructive) { moderationReason = ""; showBanAlert = true } label: {
                    Label("Bannen", systemImage: "hand.raised.slash")
                }
            }
        }
        .alert("Kicken", isPresented: $showKickAlert) {
            TextField("Grund (optional)", text: $moderationReason)
            Button("Kicken", role: .destructive) { client.kickUser(user, reason: moderationReason) }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("\(user.userName() ?? "Benutzer") entfernen?") }
        .alert("Bannen", isPresented: $showBanAlert) {
            TextField("Grund (optional)", text: $moderationReason)
            Button("Bannen", role: .destructive) { client.banUser(user, reason: moderationReason) }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("\(user.userName() ?? "Benutzer") dauerhaft sperren?") }
        .sheet(isPresented: $showMoveSheet) {
            MoveUserSheet(user: user, client: client, isPresented: $showMoveSheet)
        }
        .listRowBackground(
            isTalkingLocally
                ? Color.green.opacity(talkPulse ? 0.2 : 0.07)
                : Color.clear
        )
        .animation(.easeInOut(duration: 0.15), value: isTalkingLocally)
        .onChange(of: isTalkingLocally) { _, talking in
            if talking {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    talkPulse = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    talkPulse = false
                }
            }
        }
    }

    private var talkIcon: String {
        switch user.talkState() {
        case MKTalkStateTalking:    return "mic.fill"
        case MKTalkStateShouting:   return "speaker.wave.3.fill"
        case MKTalkStateWhispering: return "mic.circle.fill"
        default:                    return "mic"
        }
    }

    private var talkColor: Color {
        switch user.talkState() {
        case MKTalkStateTalking:    return .green
        case MKTalkStateShouting:   return .orange
        case MKTalkStateWhispering: return .blue
        default:                    return .secondary
        }
    }
}

// MARK: - Move User Sheet

private struct MoveUserSheet: View {
    let user: MKUser
    @ObservedObject var client: MumbleClient
    @Binding var isPresented: Bool

    var allChannels: [MKChannel] {
        guard let root = client.rootChannel else { return [] }
        return collectChannels(root)
    }

    var body: some View {
        NavigationStack {
            List(allChannels, id: \.self) { channel in
                Button {
                    client.moveUser(user, toChannel: channel)
                    isPresented = false
                } label: {
                    Label(channel.channelName() ?? "Channel", systemImage: "speaker.wave.2")
                }
            }
            .navigationTitle("\(user.userName() ?? "User") verschieben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { isPresented = false }
                }
            }
        }
    }

    private func collectChannels(_ channel: MKChannel) -> [MKChannel] {
        var result = [channel]
        for sub in (channel.channels() as? [MKChannel]) ?? [] {
            result.append(contentsOf: collectChannels(sub))
        }
        return result
    }
}

// MARK: - VAD Meter

private struct VADMeterView: View {
    let threshold: Double
    let isTalking: Bool

    @State private var peakDb: Float = -96

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    // Same formula as MKVADKindAmplitude in MKAudioInput.m
    private var amplitudeLevel: Float { max(0, peakDb / 96.0 + 1.0) }
    var isActive: Bool { Double(amplitudeLevel) >= threshold }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Signalpegel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isActive ? "Erkannt" : "Stille")
                    .font(.caption.bold())
                    .foregroundStyle(isActive ? .green : .secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 14)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? Color.green : Color.blue.opacity(0.6))
                        .frame(width: max(0, geo.size.width * CGFloat(amplitudeLevel)), height: 14)
                        .animation(.linear(duration: 0.05), value: amplitudeLevel)

                    // Threshold marker
                    let markerX = geo.size.width * CGFloat(threshold)
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: 20)
                        .offset(x: markerX - 1, y: -3)
                }
            }
            .frame(height: 14)

            HStack {
                Text("Mikrofon: \(String(format: "%.0f dB", peakDb))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text("Schwelle: \(String(format: "%.0f%%", threshold * 100))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .onReceive(timer) { _ in
            if let audio = MKAudio.shared() {
                peakDb = audio.peakCleanMic()
            }
        }
    }
}

#if DEBUG
#Preview("Root View") { MumbleRootView() }
#endif

#endif // os(iOS)
