//
// Copyright 2026 Holm.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI

/// Pushes a saved site onto the chat list's own navigation stack, so it arrives with
/// the same sideways animation — and the same swipe back — as opening a room.
final class HolmLinkBrowserCoordinator: CoordinatorProtocol {
    private let link: HolmLink
    private let mediaProvider: MediaProviderProtocol?

    init(link: HolmLink, mediaProvider: MediaProviderProtocol?) {
        self.link = link
        self.mediaProvider = mediaProvider
    }

    func toPresentable() -> AnyView {
        AnyView(HolmLinkBrowser(link: link, mediaProvider: mediaProvider))
    }
}
