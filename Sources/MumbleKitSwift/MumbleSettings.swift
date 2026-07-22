// Copyright 2024 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import Foundation
import MumbleKit

// MARK: - Transmit Mode

public enum TransmitMode: String, CaseIterable, Identifiable {
    case pushToTalk  = "Push-to-Talk"
    case continuous  = "Dauersenden"
    case voiceActivity = "Spracherkennung"

    public var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .pushToTalk:    return "hand.tap"
        case .continuous:    return "mic.fill"
        case .voiceActivity: return "waveform"
        }
    }

    var description: String {
        switch self {
        case .pushToTalk:    return "Antippen um zu sprechen"
        case .continuous:    return "Mikrofon immer aktiv"
        case .voiceActivity: return "Sprache wird automatisch erkannt"
        }
    }

    var mkTransmitType: MKTransmitType {
        switch self {
        case .pushToTalk:    return MKTransmitTypeToggle
        case .continuous:    return MKTransmitTypeContinuous
        case .voiceActivity: return MKTransmitTypeVAD
        }
    }
}

// MARK: - Settings Store

@MainActor
public final class MumbleSettings: ObservableObject {
    public static let shared = MumbleSettings()

    @Published public var transmitMode: TransmitMode {
        didSet { UserDefaults.standard.set(transmitMode.rawValue, forKey: "mumble.transmitMode") }
    }

    @Published public var vadThreshold: Double {
        didSet { UserDefaults.standard.set(vadThreshold, forKey: "mumble.vadThreshold") }
    }

    // Noise suppression level in dB (negative). -15 = minimal, -60 = maximum.
    @Published public var noiseSuppression: Int {
        didSet { UserDefaults.standard.set(noiseSuppression, forKey: "mumble.noiseSuppression") }
    }

    // Microphone hardware input gain, 0.0 (quiet) to 1.0 (max). Only effective if hardware supports it.
    @Published public var micInputGain: Double {
        didSet { UserDefaults.standard.set(micInputGain, forKey: "mumble.micInputGain") }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "mumble.transmitMode") ?? ""
        transmitMode = TransmitMode(rawValue: raw) ?? .pushToTalk
        vadThreshold = UserDefaults.standard.object(forKey: "mumble.vadThreshold") as? Double ?? 0.6
        let ns = UserDefaults.standard.integer(forKey: "mumble.noiseSuppression")
        noiseSuppression = ns != 0 ? ns : -30
        let gain = UserDefaults.standard.object(forKey: "mumble.micInputGain") as? Double
        micInputGain = gain ?? 0.5
    }
}

// MARK: - Chat Message

public struct ChatMessage: Identifiable {
    public var id = UUID()
    public var senderName: String
    public var text: String
    public var timestamp: Date
    public var isPrivate: Bool
    public var senderSession: UInt

    init(senderName: String, text: String, timestamp: Date = .now, isPrivate: Bool = false, senderSession: UInt = 0) {
        self.senderName    = senderName
        self.text          = text
        self.timestamp     = timestamp
        self.isPrivate     = isPrivate
        self.senderSession = senderSession
    }
}
