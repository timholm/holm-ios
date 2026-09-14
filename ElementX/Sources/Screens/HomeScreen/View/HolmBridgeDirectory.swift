//
// Copyright 2026 Holm.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compound
import SwiftUI

/// A bridge that can be connected to this account, and the bot you talk to in order
/// to connect it.
///
/// This list describes the bridges running on the homeserver, which a Matrix client
/// has no way to discover on its own — appservices are invisible over the client API.
/// It lives here so there's one place to edit when a server gains or loses a bridge.
struct HolmBridge: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String

    /// The bot's full user ID on the given server.
    func botUserID(on server: String) -> String { "@\(id):\(server)" }

    static let all: [HolmBridge] = [
        .init(id: "signalbot", name: "Signal", symbol: "message.fill"),
        .init(id: "whatsappbot", name: "WhatsApp", symbol: "phone.fill"),
        .init(id: "telegrambot", name: "Telegram", symbol: "paperplane.fill"),
        .init(id: "discordbot", name: "Discord", symbol: "gamecontroller.fill"),
        .init(id: "slackbot", name: "Slack", symbol: "number"),
        .init(id: "metabot", name: "Messenger & Instagram", symbol: "camera.fill"),
        .init(id: "twitterbot", name: "X", symbol: "bird.fill"),
        .init(id: "blueskybot", name: "Bluesky", symbol: "cloud.fill"),
        .init(id: "linkedinbot", name: "LinkedIn", symbol: "briefcase.fill"),
        .init(id: "gvoicebot", name: "Google Voice", symbol: "phone.connection.fill"),
        .init(id: "gmessagesbot", name: "Google Messages", symbol: "bubble.left.fill"),
        .init(id: "jmpchatbot", name: "JMP.chat", symbol: "antenna.radiowaves.left.and.right"),
        .init(id: "jabberbot", name: "XMPP", symbol: "dot.radiowaves.left.and.right")
    ]
}

/// Pick a service to bring into Holm. Choosing one opens its bot, where the bot walks
/// you through signing in.
struct HolmBridgeDirectory: View {
    let server: String
    let onSelect: (HolmBridge) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(HolmBridge.all) { bridge in
                Button {
                    dismiss()
                    onSelect(bridge)
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: bridge.symbol)
                            .font(.compound.bodyLG)
                            .foregroundStyle(.compound.iconAccentPrimary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(bridge.name)
                                .font(.compound.bodyLGSemibold)
                                .foregroundStyle(.compound.textPrimary)

                            Text(bridge.botUserID(on: server))
                                .font(.compound.bodySM)
                                .foregroundStyle(.compound.textSecondary)
                        }

                        Spacer()

                        CompoundIcon(\.chevronRight, size: .small, relativeTo: .compound.bodyMD)
                            .foregroundStyle(.compound.iconTertiary)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.compound.bgCanvasDefault)
            }
            .listStyle(.plain)
            .background(Color.compound.bgCanvasDefault)
            .navigationTitle("Add a bridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionCancel) { dismiss() }
                }
            }
        }
    }
}
