//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SentrySwiftUI
import SwiftUI

struct HomeScreen: View {
    @Environment(\.isInSidebar) private var isInSidebar
    
    @ObservedObject var context: HomeScreenViewModel.Context
    
    @State private var scrollViewAdapter = ScrollViewAdapter()
    
    @Namespace private var navigationTransitionNamespace
    private enum NavigationTransitionSourceID {
        case spaceFilters
    }

    /// Whether the spaces row is open. It lives here because the mark that opens it
    /// sits in the toolbar while the row itself belongs to the list.
    @State private var spacesExpanded = false

    var body: some View {
        HomeScreenContent(context: context,
                          scrollViewAdapter: scrollViewAdapter,
                          spacesExpanded: $spacesExpanded)
            .alert(item: $context.alertInfo)
            .alert(item: $context.leaveRoomAlertItem,
                   actions: leaveRoomAlertActions,
                   message: leaveRoomAlertMessage)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .track(screen: .Home)
            .toolbarBloom(hasSearchBar: context.viewState.isRoomListSearchEnabled)
            .sentryTrace("\(Self.self)")
            .sheet(item: $context.spaceFiltersViewModel) { vm in
                ChatsSpaceFiltersScreen(context: vm.context)
                    .navigationTransition(.zoom(sourceID: NavigationTransitionSourceID.spaceFilters,
                                                in: navigationTransitionNamespace))
            }
    }
    
    // MARK: - Private
    
    private var title: String {
        if let selectedSpace = context.viewState.selectedSpaceFilter {
            selectedSpace.room.name
        } else {
            L10n.screenRoomlistMainSpaceTitle
        }
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // The corner shows where you are — Holm's mark on every message, or the space
        // you're reading. Tapping it unfolds the spaces; they stay hidden until asked for.
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                // Scrolling is what puts the row away, so the second tap is free:
                // it takes you to your profile instead of just closing.
                if spacesExpanded {
                    context.send(viewAction: .showSettings)
                } else {
                    // The row lives at the top of the list, so bring the list with it —
                    // you can reach for the spaces from anywhere in your chats. Scroll
                    // after the row has taken its height, or we stop short of the top.
                    // Jump rather than animate: animating a long scroll makes the list lay
                    // out every row on the way past, which locks the screen for seconds.
                    // Landing at the top first also means the row can grow above the
                    // content without fighting a scroll that's still running.
                    scrollListToTop()

                    // From inside a space, the corner is also the way home.
                    if context.viewState.selectedSpaceFilter != nil {
                        context.send(viewAction: .selectSpaceFilter(nil))
                    }

                    spacesExpanded = true
                }
            } label: {
                currentSpaceMark
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(spacesExpanded ? L10n.commonSettings : L10n.screenRoomlistYourSpaces)
            .accessibilityAddTraits(spacesExpanded ? .isSelected : [])
            .accessibilityIdentifier(A11yIdentifiers.homeScreen.spaceFilters)
        }
        .backportSharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .principal) {
            Text(title)
                .font(.compound.bodyLGSemibold)
                .foregroundStyle(.compound.textPrimary)
                .lineLimit(1)
        }
        .backportSharedBackgroundVisibility(.hidden)
        
        ToolbarItem(placement: .primaryAction) {
            newRoomButton
        }
        .backportSharedBackgroundVisibility(.hidden)
    }

    /// Whatever you're looking at: your own face on every message, or the space you're in.
    private func scrollListToTop() {
        guard let scrollView = scrollViewAdapter.scrollView else { return }
        let top = CGPoint(x: 0, y: -scrollView.adjustedContentInset.top)
        guard scrollView.contentOffset != top else { return }
        scrollView.setContentOffset(top, animated: false)
    }

    @ViewBuilder
    private var currentSpaceMark: some View {
        Group {
            // While the row is open the corner is you — it's the way to your profile.
            // Closed, it goes back to telling you which space you're reading.
            if let space = context.viewState.selectedSpaceFilter, !spacesExpanded {
                LoadableAvatarImage(url: space.room.avatarURL,
                                    name: space.room.name,
                                    contentID: space.room.id,
                                    avatarSize: .room(on: .spaceFilters),
                                    mediaProvider: context.mediaProvider)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                AvatarSettingsButtonLabel(userProfile: context.viewState.userProfile,
                                          mediaProvider: context.mediaProvider)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: context.viewState.selectedSpaceFilter?.id)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: spacesExpanded)
    }

    @ViewBuilder
    private var newRoomButton: some View {
        switch context.viewState.roomListMode {
        case .empty, .rooms:
            Button {
                context.send(viewAction: .startChat)
            } label: {
                CompoundIcon(\.compose)
                    .toolbarChrome()
            }
            .accessibilityLabel(L10n.actionStartChat)
            .accessibilityIdentifier(A11yIdentifiers.homeScreen.startChat)
        default:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func leaveRoomAlertActions(_ item: LeaveRoomAlertItem) -> some View {
        Button(item.cancelTitle, role: .cancel) { }
        Button(item.confirmationTitle, role: .destructive) {
            context.send(viewAction: .confirmLeaveRoom(roomIdentifier: item.roomID))
        }
    }
    
    private func leaveRoomAlertMessage(_ item: LeaveRoomAlertItem) -> some View {
        Text(item.subtitle)
    }
    
}

private extension View {
    /// One soft container per toolbar action — no per-button circles, no glass rings.
    func toolbarChrome(tinted: Bool = false) -> some View {
        font(.compound.bodyLG)
            .foregroundStyle(tinted ? Color.compound.textOnSolidPrimary : Color.compound.iconPrimary)
            .frame(width: 46, height: 40)
            .background(tinted ? Color.compound.bgAccentRest : Color.compound.bgSubtleSecondary,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

// MARK: - Previews

struct HomeScreen_Previews: PreviewProvider, TestablePreview {
    static let loadingViewModel = viewModel(.skeletons)
    static let emptyViewModel = viewModel(.empty)
    static let loadedViewModel = viewModel(.rooms)
    
    static var previews: some View {
        ElementNavigationStack {
            HomeScreen(context: loadingViewModel.context)
        }
        .snapshotPreferences(expect: loadingViewModel.context.$viewState.map { state in
            state.roomListMode == .skeletons
        })
        .previewDisplayName("Loading")
        
        ElementNavigationStack {
            HomeScreen(context: emptyViewModel.context)
        }
        .snapshotPreferences(expect: emptyViewModel.context.$viewState.map { state in
            state.roomListMode == .empty
        })
        .previewDisplayName("Empty")
        
        ElementNavigationStack {
            HomeScreen(context: loadedViewModel.context)
        }
        .snapshotPreferences(expect: loadedViewModel.context.$viewState.map { state in
            state.roomListMode == .rooms
        })
        .previewDisplayName("Loaded")
    }
    
    static func viewModel(_ mode: HomeScreenRoomListMode) -> HomeScreenViewModel {
        let userID = "@alice:example.com"
        
        let roomSummaryProviderState: RoomSummaryProviderMockConfigurationState = switch mode {
        case .skeletons:
            .loading
        case .empty:
            .loaded([])
        case .rooms:
            .loaded(.mockRooms)
        }
        
        let clientProxy = ClientProxyMock(.init(userID: userID,
                                                roomSummaryProvider: RoomSummaryProviderMock(.init(state: roomSummaryProviderState))))
        
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
