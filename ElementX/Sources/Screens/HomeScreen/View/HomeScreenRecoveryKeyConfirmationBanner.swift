//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SwiftUI

struct HomeScreenRecoveryKeyConfirmationBanner: View {
    enum State { case setUpRecovery, recoveryOutOfSync }
    let state: State
    var context: HomeScreenViewModel.Context
    
    var title: String {
        switch state {
        case .setUpRecovery: L10n.bannerSetUpRecoveryTitle
        case .recoveryOutOfSync: L10n.confirmRecoveryKeyBannerTitle
        }
    }
    
    var message: String {
        switch state {
        case .setUpRecovery: L10n.bannerSetUpRecoveryContent
        case .recoveryOutOfSync: L10n.confirmRecoveryKeyBannerMessage
        }
    }
    
    var actionTitle: String {
        switch state {
        case .setUpRecovery: L10n.bannerSetUpRecoverySubmit
        case .recoveryOutOfSync: L10n.confirmRecoveryKeyBannerPrimaryButtonTitle
        }
    }
    
    var primaryAction: HomeScreenViewAction {
        switch state {
        case .setUpRecovery: .setupRecovery
        case .recoveryOutOfSync: .confirmRecoveryKey
        }
    }
    
    /// A quiet single-line notice rather than a card: an accent rule, one line of
    /// text, and an inline action. It reads as part of the list, not stacked on top of it.
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Rectangle()
                .fill(Color.compound.iconAccentPrimary)
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.compound.bodyMDSemibold)
                    .foregroundColor(.compound.textPrimary)

                Text(message)
                    .font(.compound.bodySM)
                    .foregroundColor(.compound.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack(spacing: 14) {
            Button {
                context.send(viewAction: primaryAction)
            } label: {
                Text(actionTitle)
                    .font(.compound.bodySMSemibold)
                    .foregroundColor(.compound.textActionAccent)
            }
            .accessibilityIdentifier(A11yIdentifiers.homeScreen.recoveryKeyConfirmationBannerContinue)

            if state == .setUpRecovery {
                Button {
                    context.send(viewAction: .skipRecoveryKeyConfirmation)
                } label: {
                    CompoundIcon(\.close, size: .small, relativeTo: .compound.bodySM)
                        .foregroundColor(.compound.iconTertiary)
                }
            }
        }
    }
}

struct HomeScreenRecoveryKeyConfirmationBanner_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    
    static var previews: some View {
        HomeScreenRecoveryKeyConfirmationBanner(state: .setUpRecovery,
                                                context: viewModel.context)
            .previewDisplayName("Set up recovery")
        HomeScreenRecoveryKeyConfirmationBanner(state: .recoveryOutOfSync,
                                                context: viewModel.context)
            .previewDisplayName("Out of sync")
    }
    
    static func makeViewModel() -> HomeScreenViewModel {
        let clientProxy = ClientProxyMock(.init(userID: "@alice:example.com",
                                                roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loading))))
        
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        
        return HomeScreenViewModel(userSession: userSession,
                                   selectedRoomPublisher: CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher(),
                                   appSettings: .volatile(),
                                   analyticsService: AnalyticsServiceMock(.init()),
                                   bugReportService: BugReportServiceMock(.init()),
                                   notificationManager: NotificationManagerMock(),
                                   userIndicatorController: UserIndicatorControllerMock())
    }
}
