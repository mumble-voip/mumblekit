// Copyright 2024 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import Foundation
import AVFoundation
import MumbleKit

// MARK: - Favorites

public struct ServerFavorite: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: UInt
    public var username: String
    public var password: String

    public init(name: String, host: String, port: UInt = 64738, username: String, password: String = "") {
        self.id = UUID()
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }
}

public final class FavoritesStore: ObservableObject {
    @Published public var favorites: [ServerFavorite] = []
    private let key = "mumble.favorites"

    public init() { load() }

    public func add(_ favorite: ServerFavorite) {
        favorites.append(favorite)
        save()
    }

    public func remove(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        save()
    }

    public func update(_ favorite: ServerFavorite) {
        guard let idx = favorites.firstIndex(where: { $0.id == favorite.id }) else { return }
        favorites[idx] = favorite
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ServerFavorite].self, from: data) else { return }
        favorites = decoded
    }
}

// MARK: - MumbleClient

@MainActor
public final class MumbleClient: NSObject, ObservableObject {

    // MARK: Published State

    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var rootChannel: MKChannel?
    @Published public private(set) var localUser: MKUser?
    @Published public private(set) var isTalking: Bool = false
    @Published public private(set) var isMuted: Bool = false

    // Chat
    @Published public private(set) var chatMessages: [ChatMessage] = []
    @Published public private(set) var unreadCount: Int = 0

    // Channel listeners (Mumble 1.4+)
    @Published public private(set) var listenedChannelIds: Set<UInt> = []

    // Connection info
    @Published public private(set) var connectedAt: Date? = nil
    @Published public private(set) var tcpPingMs: Float = 0
    @Published public private(set) var udpPingMs: Float = 0
    @Published public private(set) var udpAvailable: Bool = false
    @Published public private(set) var udpLostPackets: UInt32 = 0

    // MARK: Types

    public enum ConnectionState: Equatable {
        case disconnected, connecting, connected, failed(String)
    }

    // MARK: Private

    private var connection: MKConnection?
    private var serverModel: MKServerModel?
    private let audio = MKAudio.shared()
    private var pendingUsername = ""
    private var pendingPassword = ""
    private var pingRefreshTimer: Timer?

    // MARK: Init

    public override init() {
        super.init()
    }

    // MARK: Connection

    public func connect(to host: String, port: UInt = 64738, username: String, password: String = "") {
        guard connectionState == .disconnected || {
            if case .failed = connectionState { return true }
            return false
        }() else { return }

        // Must be set before connectionOpened fires and sends the Authenticate message
        MKVersion.shared().setOpusEnabled(true)

        connectionState = .connecting

        guard let conn = MKConnection() else { connectionState = .failed("Init failed"); return }
        conn.setDelegate(self)
        connection = conn

        guard let model = MKServerModel(connection: conn) else { connectionState = .failed("Init failed"); return }
        model.addDelegate(self)
        serverModel = model

        pendingUsername = username
        pendingPassword = password
        conn.connect(toHost: host, port: port)
    }

    public func connect(with favorite: ServerFavorite) {
        connect(to: favorite.host, port: favorite.port, username: favorite.username, password: favorite.password)
    }

    public func disconnect() {
        connection?.disconnect()
    }

    // MARK: Channel Operations

    public func joinChannel(_ channel: MKChannel) {
        serverModel?.join(channel)
    }

    // MARK: Audio / Transmit

    public func applyMicInputGain(_ gain: Double) {
        let session = AVAudioSession.sharedInstance()
        guard session.isInputGainSettable else { return }
        try? session.setInputGain(Float(gain))
    }

    public func applyTransmitMode(_ mode: TransmitMode) {
        isTalking = false
        audio?.setForceTransmit(false)
        var settings = MKAudioSettings()
        settings.codec = MKCodecFormatOpus
        settings.transmitType = mode.mkTransmitType
        settings.quality = 40000
        settings.audioPerPacket = 2
        settings.noiseSuppression = Int32(MumbleSettings.shared.noiseSuppression)
        settings.amplification = 20.0
        settings.jitterBufferSize = 1
        settings.volume = 1.0
        settings.outputDelay = 0
        settings.micBoost = Float(MumbleSettings.shared.micInputGain)
        settings.enablePreprocessor = true
        settings.enableEchoCancellation = false
        settings.enableSideTone = false
        settings.sidetoneVolume = 0
        if mode == .voiceActivity {
            let t = Float(MumbleSettings.shared.vadThreshold)
            settings.vadKind = MKVADKindAmplitude
            settings.vadMax = t
            settings.vadMin = max(0.0, t - 0.12)
        }
        audio?.update(&settings)
        if connectionState == .connected {
            audio?.restart()
        }
    }

    public func setTalking(_ talking: Bool) {
        audio?.setForceTransmit(talking)
        isTalking = talking
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        serverModel?.setSelfMuted(muted, andSelfDeafened: false)
    }

    // MARK: User Moderation

    public func setMuted(_ muted: Bool, forUser user: MKUser) {
        serverModel?.setMuted(muted, for: user)
    }

    public func kickUser(_ user: MKUser, reason: String = "") {
        serverModel?.kick(user, withReason: reason)
    }

    public func banUser(_ user: MKUser, reason: String = "") {
        serverModel?.ban(user, withReason: reason)
    }

    public func moveUser(_ user: MKUser, toChannel channel: MKChannel) {
        serverModel?.move(user, to: channel)
    }

    // MARK: Channel Listening (Mumble 1.4+)

    public func toggleListenChannel(_ channel: MKChannel) {
        let cid = UInt(channel.channelId())
        if listenedChannelIds.contains(cid) {
            stopListeningToChannel(channel)
        } else {
            listenToChannel(channel)
        }
    }

    public func listenToChannel(_ channel: MKChannel) {
        guard let session = localUser?.session(), let conn = connection else { return }
        let cid = UInt(channel.channelId())
        // UserState with listening_channel_add (field 21) — Mumble 1.4+ channel listener
        conn.sendMessage(with: UserStateMessage, data: userStateListenData(session: session, addChannel: cid))
        listenedChannelIds.insert(cid)
    }

    public func stopListeningToChannel(_ channel: MKChannel) {
        guard let session = localUser?.session(), let conn = connection else { return }
        let cid = UInt(channel.channelId())
        // UserState with listening_channel_remove (field 22) — Mumble 1.4+ channel listener
        conn.sendMessage(with: UserStateMessage, data: userStateListenData(session: session, removeChannel: cid))
        listenedChannelIds.remove(cid)
    }

    private func userStateListenData(session: UInt, addChannel: UInt? = nil, removeChannel: UInt? = nil) -> Data {
        func varint(_ v: UInt64) -> [UInt8] {
            var val = v; var out = [UInt8]()
            repeat {
                var b = UInt8(val & 0x7F); val >>= 7
                if val > 0 { b |= 0x80 }
                out.append(b)
            } while val > 0
            return out
        }
        var bytes = [UInt8]()
        // field 1 = session
        bytes += varint(UInt64(1 << 3)) + varint(UInt64(session))
        // field 21 = listening_channel_add
        if let cid = addChannel {
            bytes += varint(UInt64(21 << 3)) + varint(UInt64(cid))
        }
        // field 22 = listening_channel_remove
        if let cid = removeChannel {
            bytes += varint(UInt64(22 << 3)) + varint(UInt64(cid))
        }
        return Data(bytes)
    }

    // MARK: Chat

    public func sendMessage(_ text: String, toChannel channel: MKChannel) {
        guard let msg = MKTextMessage(string: text) else { return }
        serverModel?.send(msg, to: channel)
        let name = localUser?.userName() ?? "Ich"
        chatMessages.append(ChatMessage(senderName: name, text: text, isPrivate: false,
                                        senderSession: localUser?.session() ?? 0))
    }

    public func sendPrivateMessage(_ text: String, toUser user: MKUser) {
        guard let msg = MKTextMessage(string: text) else { return }
        serverModel?.send(msg, to: user)
        let name = localUser?.userName() ?? "Ich"
        chatMessages.append(ChatMessage(senderName: name, text: text, isPrivate: true,
                                        senderSession: localUser?.session() ?? 0))
    }

    public func markChatRead() {
        unreadCount = 0
    }

    // MARK: Stats helpers

    public var connectionDuration: TimeInterval {
        guard let start = connectedAt else { return 0 }
        return Date().timeIntervalSince(start)
    }

    public var serverAddress: String {
        guard let m = serverModel else { return "-" }
        return "\(m.hostname() ?? "-"):\(m.port())"
    }

    public var packetLossPercent: Float {
        let total = Float(udpLostPackets) + Float(max(1, udpLostPackets))
        guard total > 0 else { return 0 }
        return (Float(udpLostPackets) / total) * 100
    }

    // MARK: Private

    private func refreshChannelTree() {
        rootChannel = serverModel?.rootChannel()
    }

    private func startPingTimer() {
        pingRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let conn = self.connection else { return }
                self.tcpPingMs = conn.tcpPingAvgMs
                self.udpPingMs = conn.udpPingAvgMs
                self.udpAvailable = conn.udpAvailable
                self.udpLostPackets = conn.udpLostPackets
            }
        }
    }

    private func stopPingTimer() {
        pingRefreshTimer?.invalidate()
        pingRefreshTimer = nil
    }

    private func cleanUp() {
        rootChannel = nil
        localUser = nil
        isTalking = false
        isMuted = false
        connectedAt = nil
        listenedChannelIds = []
        udpAvailable = false
        serverModel = nil
        connection = nil
        stopPingTimer()
    }
}

// MARK: - MKConnectionDelegate

extension MumbleClient: @preconcurrency MKConnectionDelegate {

    public func connectionOpened(_ conn: MKConnection!) {
        conn.authenticate(withUsername: pendingUsername, password: pendingPassword, accessTokens: nil)
    }

    public func connection(_ conn: MKConnection!, unableToConnectWithError err: Error!) {
        connectionState = .failed(err?.localizedDescription ?? "Unable to connect")
        cleanUp()
    }

    public func connection(_ conn: MKConnection!, closedWithError err: Error!) {
        connectionState = .disconnected
        cleanUp()
        audio?.stop()
    }

    public func connection(_ conn: MKConnection!, trustFailureInCertificateChain chain: [Any]!) {
        conn.setIgnoreSSLVerification(true)
        conn.reconnect()
    }

    public func connection(_ conn: MKConnection!, rejectedWith reason: MKRejectReason, explanation: String!) {
        let message: String
        switch reason {
        case MKRejectReasonWrongUserPassword, MKRejectReasonWrongServerPassword:
            message = "Falsches Passwort"
        case MKRejectReasonUsernameInUse:
            message = "Benutzername bereits vergeben"
        case MKRejectReasonServerIsFull:
            message = "Server ist voll"
        case MKRejectReasonNoCertificate:
            message = "Server erfordert Zertifikat"
        default:
            message = explanation ?? "Verbindung abgelehnt"
        }
        connectionState = .failed(message)
        cleanUp()
    }
}

// MARK: - MKServerModelDelegate

extension MumbleClient: @preconcurrency MKServerModelDelegate {

    public func serverModel(_ model: MKServerModel!, joinedServerAs user: MKUser!, withWelcome msg: MKTextMessage!) {
        localUser = model.connectedUser()
        connectionState = .connected
        connectedAt = Date()
        refreshChannelTree()
        audio?.start()
        audio?.setMainConnectionFor(connection)
        applyTransmitMode(MumbleSettings.shared.transmitMode)
        applyMicInputGain(MumbleSettings.shared.micInputGain)
        startPingTimer()
    }

    public func serverModelDisconnected(_ model: MKServerModel!) {
        connectionState = .disconnected
        cleanUp()
        audio?.stop()
    }

    public func serverModel(_ model: MKServerModel!, userJoined user: MKUser!) { refreshChannelTree() }
    public func serverModel(_ model: MKServerModel!, userLeft user: MKUser!) { refreshChannelTree() }
    public func serverModel(_ model: MKServerModel!, userMoved user: MKUser!, to chan: MKChannel!, by mover: MKUser!) { refreshChannelTree() }
    public func serverModel(_ model: MKServerModel!, channelAdded channel: MKChannel!) { refreshChannelTree() }
    public func serverModel(_ model: MKServerModel!, channelRemoved channel: MKChannel!) { refreshChannelTree() }

    public func serverModel(_ model: MKServerModel!, userTalkStateChanged user: MKUser!) {
        if user.session() == localUser?.session() {
            isTalking = user.talkState() == MKTalkStateTalking || user.talkState() == MKTalkStateShouting
        }
        refreshChannelTree()
    }

    public func serverModel(_ model: MKServerModel!, textMessageReceived msg: MKTextMessage!, from user: MKUser!) {
        let senderName = user?.userName() ?? "Server"
        let isPrivate = user != nil
        let chat = ChatMessage(
            senderName: senderName,
            text: msg.plainTextString() ?? "",
            isPrivate: isPrivate,
            senderSession: user?.session() ?? 0
        )
        chatMessages.append(chat)
        unreadCount += 1
    }
}
