//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import PhotosUI
import SentrySwiftUI
import SwiftUI

struct HomeScreenContent: View {
    @ObservedObject var context: HomeScreenViewModel.Context
    let scrollViewAdapter: ScrollViewAdapter
    @Binding var spacesExpanded: Bool
    
    @State private var topSectionHeight: CGFloat = 0
    @State private var isShowingBridges = false
    @State private var isShowingAddLink = false
    @State private var linkAwaitingPhoto: HolmLink?
    @State private var photoItem: PhotosPickerItem?
    @State private var isRearranging = false
    
    var body: some View {
        roomList
            .sentryTrace("\(Self.self)")
            .fullScreenCover(isPresented: $isShowingAddLink) {
                HolmAddLinkSheet { link in
                    context.send(viewAction: .addLink(link))
                }
            }
            .sheet(isPresented: $isRearranging) {
                HolmRailOrderSheet(items: railItems, mediaProvider: context.mediaProvider) { order in
                    context.send(viewAction: .reorderRail(order))
                }
            }
            .photosPicker(isPresented: .init(get: { linkAwaitingPhoto != nil },
                                             set: { if !$0 { linkAwaitingPhoto = nil } }),
                          selection: $photoItem,
                          matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item, var link = linkAwaitingPhoto else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let thumbnail = HolmLinkMetadata.thumbnail(from: data) {
                        link.iconData = thumbnail
                        context.send(viewAction: .updateLink(link))
                    }
                    photoItem = nil
                    linkAwaitingPhoto = nil
                }
            }
            .sheet(isPresented: $isShowingBridges) {
                HolmBridgeDirectory(server: homeserverName) { bridge in
                    context.send(viewAction: .addBridge(userID: bridge.botUserID(on: homeserverName)))
                }
            }
    }
    
    private var roomList: some View {
        GeometryReader { geometry in
            ScrollView {
                switch context.viewState.roomListMode {
                case .skeletons:
                    LazyVStack(spacing: 0) {
                        ForEach(context.viewState.visibleRooms) { room in
                            HomeScreenRoomCell(room: room, isSelected: false, mediaProvider: context.mediaProvider, action: context.send)
                                .redacted(reason: .placeholder)
                                .shimmer() // Putting this directly on the LazyVStack creates an accordion animation on iOS 16.
                        }
                    }
                    .disabled(true)
                    .accessibilityRepresentation {
                        Text(L10n.commonLoading)
                    }
                case .empty:
                    HomeScreenEmptyStateLayout(minHeight: geometry.size.height) {
                        topSection
                        
                        HomeScreenEmptyStateView(context: context)
                            .layoutPriority(1)
                    }
                case .rooms:
                    LazyVStack(spacing: 0) {
                        Section {
                            if context.viewState.shouldShowEmptyFilterState {
                                RoomListFiltersEmptyStateView(state: context.filtersState)
                                    .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - topSectionHeight))
                            } else {
                                HomeScreenRoomList(context: context)
                                    .accessibilityAddTraits(.updatesFrequently)
                            }
                        } header: {
                            topSection
                        }
                    }
                }
            }
            .introspect(.scrollView, on: .supportedVersions) { scrollView in
                guard scrollView != scrollViewAdapter.scrollView else { return }
                scrollViewAdapter.scrollView = scrollView
            }
            .onReceive(scrollViewAdapter.didScroll) { _ in
                sendVisibleRange()

                // Already at the top and still pulling? That asks for the spaces.
                if !spacesExpanded, overscroll > 60 {
                    spacesExpanded = true
                }
            }
            .onReceive(scrollViewAdapter.isScrolling) { isScrolling in
                updateVisibleRange()

                // Reading the list puts the spaces away again; pulling down brings them back,
                // as does the mark in the corner.
                if isScrolling, spacesExpanded, overscroll <= 0 {
                    spacesExpanded = false
                }
            }
            .onChange(of: context.searchQuery) {
                updateVisibleRange()
            }
            .onChange(of: context.viewState.visibleRooms) {
                updateVisibleRange()
                
                // We have been seeing a lot of issues around the room list not updating properly after
                // rooms shifting around:
                // * Tapping on the room list doesn't always take you to the right room  - https://github.com/element-hq/element-x-ios/issues/2386
                // * Big blank gaps in the room list - https://github.com/element-hq/element-x-ios/issues/3026
                //
                // We initially thought it's caused by the filters header or the geometry reader but
                // the problem is still reproducible without those.
                //
                // As a last attempt we will manually force it to update by shifting the
                // inner scroll view by a point every time the room list is updated
                DispatchQueue.main.async {
                    guard !scrollViewAdapter.isScrolling.value, let scrollView = scrollViewAdapter.scrollView else {
                        return
                    }
                    
                    let oldOffset = scrollView.contentOffset
                    var newOffset = scrollView.contentOffset
                    newOffset.y += 1
                    
                    scrollView.setContentOffset(newOffset, animated: false)
                    scrollView.setContentOffset(oldOffset, animated: false)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollDisabled(context.viewState.roomListMode == .skeletons)
            .scrollBounceBehavior(context.viewState.roomListMode == .empty ? .basedOnSize : .automatic)
            .animation(.elementDefault, value: context.viewState.roomListMode)
            .animation(.none, value: context.viewState.visibleRooms)
        }
    }
    
    @ViewBuilder
    private var topSection: some View {
        // An empty VStack causes glitches within the room list
        if !context.viewState.spaceFilters.isEmpty || context.viewState.isRoomListSearchEnabled ||
            context.viewState.shouldShowFilters || context.viewState.shouldShowBanner {
            VStack(spacing: 0) {
                if context.viewState.isRoomListSearchEnabled {
                    HolmSearchField(query: $context.searchQuery,
                                    isFocused: $context.isSearchFieldFocused)
                }

                HomeScreenSpaceBar(spaces: context.viewState.spaceFilters,
                                   selected: context.viewState.selectedSpaceFilter,
                                   unreadSpaceIDs: context.viewState.unreadSpaceIDs,
                                   mediaProvider: context.mediaProvider,
                                   isExpanded: spacesExpanded,
                                   links: context.viewState.links,
                                   order: context.viewState.railOrder,
                                   onSelect: { context.send(viewAction: .selectSpaceFilter($0)) },
                                   onOpenLink: { context.send(viewAction: .openLink($0)) },
                                   onChangePhoto: { link in
                                       linkAwaitingPhoto = link
                                   },
                                   onRemoveLink: { context.send(viewAction: .removeLink($0)) },
                                   onRearrange: { isRearranging = true },
                                   onCreateSpace: { context.send(viewAction: .createSpace) },
                                   onAddBridge: { isShowingBridges = true },
                                   onAddLink: { isShowingAddLink = true })

                // Filters keep the same company as the spaces: hidden until you open the
                // corner, and held open while one is actually doing something.
                if context.viewState.shouldShowFilters, spacesExpanded || context.filtersState.isFiltering {
                    RoomListFiltersView(state: $context.filtersState)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                if case let .show(state) = context.viewState.securityBannerMode {
                    HomeScreenRecoveryKeyConfirmationBanner(state: state, context: context)
                } else if context.viewState.shouldShowNewSoundBanner {
                    HomeScreenNewSoundBanner { context.send(viewAction: .dismissNewSoundBanner) }
                }
            }
            .background(Color.compound.bgCanvasDefault)
            .animation(.spring(response: 0.26, dampingFraction: 0.88), value: spacesExpanded)
            .readHeight($topSectionHeight)
        }
    }
    
    private var railItems: [HolmRailItem] {
        let items = context.viewState.spaceFilters.map(HolmRailItem.space) +
            context.viewState.links.map(HolmRailItem.link)
        let order = context.viewState.railOrder
        guard !order.isEmpty else { return items }

        return items.sorted {
            (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max)
        }
    }

    /// The part of your user ID after the colon — the bridges live on the same server.
    private var homeserverName: String {
        context.viewState.userProfile.id.components(separatedBy: ":").last ?? ""
    }

    /// How far the list has been dragged past its top, in points. Zero or less means
    /// you're reading the list rather than pulling on it.
    private var overscroll: CGFloat {
        guard let scrollView = scrollViewAdapter.scrollView else { return 0 }
        return -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
    }

    /// Often times the scroll view's content size isn't correct yet when this method is called e.g. when cancelling a search
    /// Dispatch it with a delay to allow the UI to update and the computations to be correct
    /// Once we move to iOS 17 we should remove all of this and use scroll anchors instead
    /// Update: We're on iOS 26 now and the scroll achors still don't work properly.
    private func updateVisibleRange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { delayedUpdateVisibleRange() }
    }
    
    private func delayedUpdateVisibleRange() {
        guard scrollViewAdapter.isScrolling.value == false else {
            // Scrolling reports live through didScroll
            return
        }
        sendVisibleRange()
    }
    
    private func sendVisibleRange() {
        guard let scrollView = scrollViewAdapter.scrollView,
              context.searchQuery.isEmpty == true, // Ignore while filtering
              !context.viewState.visibleRooms.isEmpty else {
            return
        }
        
        guard scrollView.contentSize.height > scrollView.bounds.height else {
            // This list never scrolls, publish the range manually.
            context.send(viewAction: .updateVisibleItemRange(0..<context.viewState.visibleRooms.count))
            return
        }
        
        let adjustedContentSize = max(scrollView.contentSize.height - scrollView.contentInset.top - scrollView.contentInset.bottom, scrollView.bounds.height)
        let cellHeight = adjustedContentSize / Double(context.viewState.visibleRooms.count)
        
        let firstIndex = Int(max(0.0, scrollView.contentOffset.y + scrollView.contentInset.top) / cellHeight)
        let lastIndex = Int(max(0.0, scrollView.contentOffset.y + scrollView.bounds.height) / cellHeight)
        
        // This will be deduped and throttled on the view model layer
        context.send(viewAction: .updateVisibleItemRange(firstIndex..<lastIndex))
    }
}

private extension View {
    @ViewBuilder
    func roomListSearchable(isEnabled: Bool, isSearchFieldFocused: Binding<Bool>, searchQuery: Binding<String>) -> some View {
        if isEnabled {
            isSearching(isSearchFieldFocused)
                // Search rides with the list: it scrolls away as you read and comes
                // back when you pull down. Only the toolbar stays pinned.
                .searchable(text: searchQuery, placement: .navigationBarDrawer(displayMode: .automatic))
                .compoundSearchField()
                .disableAutocorrection(true)
        } else {
            self
        }
    }
}
