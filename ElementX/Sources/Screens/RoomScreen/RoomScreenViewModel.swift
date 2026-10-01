//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import MatrixRustSDK
import OrderedCollections
import SwiftUI

typealias RoomScreenViewModelType = StateStoreViewModel<RoomScreenViewState, RoomScreenViewAction>

class RoomScreenViewModel: RoomScreenViewModelType, RoomScreenViewModelProtocol {
    private let clientProxy: ClientProxyProtocol
    private let roomProxy: JoinedRoomProxyProtocol
    private let appSettings: AppSettings
    private let analyticsService: AnalyticsServiceProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private var initialSelectedPinnedEventID: String?
    private let pinnedEventStringBuilder: RoomEventStringBuilder
    
    /// Gates everything that must not run before first paint (crypto warmup,
    /// pinned-events timeline). Set by `startBackgroundPhases()`, triggered
    /// once from `RoomScreen.onAppear`.
    private var backgroundPhasesStarted = false
    
    private var identityPinningViolations = [String: RoomMemberProxyProtocol]()
    private var identityVerificationViolations = [String: RoomMemberProxyProtocol]()
    
    private let actionsSubject: PassthroughSubject<RoomScreenViewModelAction, Never> = .init()
    var actions: AnyPublisher<RoomScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private var pinnedEventsTimelineItemProvider: TimelineItemProviderProtocol? {
        didSet {
            guard let pinnedEventsTimelineItemProvider else {
                return
            }
            
            buildPinnedEventContents(timelineItems: pinnedEventsTimelineItemProvider.itemProxies)
            pinnedEventsTimelineItemProvider.updatePublisher
                // When pinning or unpinning an item, the timeline might return empty for a short while, so we need to debounce it to prevent weird UI behaviours like the banner disappearing
                .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
                .sink { [weak self] updatedItems, _ in
                    guard let self else { return }
                    buildPinnedEventContents(timelineItems: updatedItems)
                }
                .store(in: &cancellables)
        }
    }
    
    init(userSession: UserSessionProtocol,
         roomProxy: JoinedRoomProxyProtocol,
         initialSelectedPinnedEventID: String?,
         ongoingCallRoomIDPublisher: CurrentValuePublisher<String?, Never>,
         appSettings: AppSettings,
         appHooks: AppHooks,
         analyticsService: AnalyticsServiceProtocol,
         userIndicatorController: UserIndicatorControllerProtocol) {
        // Cache read: everything here comes from already-loaded publishers so
        // init stays cheap and never gates first paint on network or crypto.
        let viewModelInitSignpostID = RoomLoadSignposts.begin(.viewModelInit)
        defer { RoomLoadSignposts.end(.viewModelInit, id: viewModelInitSignpostID) }
        
        clientProxy = userSession.clientProxy
        self.roomProxy = roomProxy
        self.appSettings = appSettings
        self.analyticsService = analyticsService
        self.userIndicatorController = userIndicatorController
        
        self.initialSelectedPinnedEventID = initialSelectedPinnedEventID
        pinnedEventStringBuilder = .pinnedEventStringBuilder(userID: roomProxy.ownUserID)
        
        let viewState = RoomScreenViewState(roomTitle: roomProxy.infoPublisher.value.displayName ?? roomProxy.id,
                                            roomAvatar: roomProxy.infoPublisher.value.avatar,
                                            hasOngoingCall: roomProxy.infoPublisher.value.hasRoomCall,
                                            isDM: roomProxy.infoPublisher.value.isDM,
                                            hasSuccessor: roomProxy.infoPublisher.value.successor != nil,
                                            roomHistorySharingState: roomProxy.infoPublisher.value.historySharingState)
        super.init(initialViewState: appHooks.roomScreenHook.update(viewState),
                   mediaProvider: userSession.mediaProvider)
        
        updateRoomInfo(roomProxy.infoPublisher.value)
        setupSubscriptions(ongoingCallRoomIDPublisher: ongoingCallRoomIDPublisher)
        
        // Note: the DM verification badge (crypto/key resolution) and the
        // pinned-events timeline used to start here. They now run in
        // startBackgroundPhases(), after first paint.
    }
    
    /// Starts everything that must not gate first paint: crypto warmup for the
    /// DM verification badge and the pinned-events timeline. Called once from
    /// `RoomScreen.onAppear` via `.roomAppeared`; safe to call again (no-op).
    func startBackgroundPhases() {
        guard !backgroundPhasesStarted else { return }
        backgroundPhasesStarted = true
        
        RoomLoadSignposts.event(.firstPaint)
        // Ends the coordinator's `room_open` interval.
        actionsSubject.send(.roomFirstPaint)
        
        Task { [weak self] in
            await self?.warmCryptoWithTimeout()
        }
        Task { [weak self] in
            await self?.loadPinnedEventsTimeline()
        }
    }
    
    override func process(viewAction: RoomScreenViewAction) {
        switch viewAction {
        case .roomAppeared:
            startBackgroundPhases()
        case .tappedPinnedEventsBanner:
            handleTappedPinnedEventsBanner()
        case .viewAllPins:
            analyticsService.trackInteraction(name: .PinnedMessageBannerViewAllButton)
            actionsSubject.send(.displayPinnedEventsTimeline)
        case .displayRoomDetails:
            actionsSubject.send(.displayRoomDetails)
        case .displayCall(let isVoiceCall):
            actionsSubject.send(.displayCall(isVoiceCall: isVoiceCall))
            actionsSubject.send(.removeComposerFocus)
            analyticsService.trackInteraction(name: .MobileRoomCallButton)
        case .footerViewAction(let action):
            switch action {
            case .resolvePinViolation(let userID):
                Task { await resolveIdentityPinningViolation(userID) }
            case .resolveVerificationViolation(let userID):
                Task { await resolveIdentityVerificationViolation(userID) }
            }
        case .acceptKnock(let eventID):
            Task { await acceptKnock(eventID: eventID) }
        case .dismissKnockRequests:
            Task { await markAllKnocksAsSeen() }
        case .viewKnockRequests:
            actionsSubject.send(.displayKnockRequests)
        case .displaySuccessorRoom:
            guard let successorID = roomProxy.infoPublisher.value.successor?.roomId else { return }
            let serverNames = roomProxy.knownServerNames(maxCount: 50) // Limit to the same number used by ClientProxy.resolveRoomAlias(_:)
            actionsSubject.send(.displayRoom(roomID: successorID, via: Array(serverNames)))
        case .displayThreadList:
            actionsSubject.send(.displayThreadList)
        case .tappedStopLiveLocation:
            actionsSubject.send(.stopLiveLocationSharing)
        case .tappedOpenLiveLocation:
            actionsSubject.send(.displayLiveLocation)
        }
    }
    
    func stop() {
        Task {
            // When navigating away from the room, we need to mark the room as both read
            // and fully read for Synapse to clear this room from the app's badge count.
            _ = await roomProxy.markAsRead(receiptType: appSettings.sharePresence ? .read : .readPrivate)
            _ = await roomProxy.markAsRead(receiptType: .fullyRead)
        }
        // Work around QLPreviewController dismissal issues, see the InteractiveQuickLookModifier.
        state.bindings.mediaPreviewViewModel = nil
    }
    
    func timelineHasScrolled(direction: ScrollDirection) {
        state.lastScrollDirection = direction
    }
    
    func setSelectedPinnedEventID(_ eventID: String) {
        state.pinnedEventsBannerState.setSelectedPinnedEventID(eventID)
    }
    
    func displayMediaPreview(_ mediaPreviewViewModel: TimelineMediaPreviewViewModel) {
        mediaPreviewViewModel.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss:
                state.bindings.mediaPreviewViewModel = nil
            case .displayMessageForwarding(let forwardingItem):
                state.bindings.mediaPreviewViewModel = nil
                // We need a small delay because we need to wait for the media preview to be fully dismissed.
                DispatchQueue.main.asyncAfter(deadline: .now() + TimelineMediaPreviewViewModel.displayMessageForwardingDelay) {
                    self.actionsSubject.send(.displayMessageForwarding(forwardingItem))
                }
            case .viewInRoomTimeline:
                fatalError("\(action) should not be visible on a room preview.")
            }
        }
        .store(in: &cancellables)
        
        state.bindings.mediaPreviewViewModel = mediaPreviewViewModel
    }
    
    // MARK: - Private
    
    private func setupSubscriptions(ongoingCallRoomIDPublisher: CurrentValuePublisher<String?, Never>) {
        appSettings.threadsEnabledPublisher
            .weakAssign(to: \.state.roomThreadListEnabled, on: self)
            .store(in: &cancellables)
        
        appSettings.liveLocationSharingSessionsByRoomIDPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessionsByRoomID in
                guard let self else { return }
                state.isSharingLiveLocation = sessionsByRoomID.keys.contains(roomProxy.id)
            }
            .store(in: &cancellables)
        
        roomProxy.infoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] roomInfo in
                self?.updateRoomInfo(roomInfo)
            }
            .store(in: &cancellables)
        
        let identityStatusChangesPublisher = roomProxy.identityStatusChangesPublisher.receive(on: DispatchQueue.main)
        
        Task { [weak self] in
            for await changes in identityStatusChangesPublisher.values {
                guard !Task.isCancelled else {
                    return
                }
                
                await self?.processIdentityStatusChanges(changes)
                await self?.updateVerificationBadge()
            }
        }
        .store(in: &cancellables)
        
        clientProxy.homeserverReachabilityPublisher
            .filter { $0 == .reachable }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Deferred until after first paint: building the pinned-events
                // timeline spins up a second Rust timeline and must not race
                // room load. startBackgroundPhases() kicks it off directly.
                guard let self, self.backgroundPhasesStarted else { return }
                Task { [weak self] in
                    await self?.loadPinnedEventsTimeline()
                }
            }
            .store(in: &cancellables)
        
        ongoingCallRoomIDPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ongoingCallRoomID in
                guard let self else { return }
                state.isParticipatingInOngoingCall = ongoingCallRoomID == roomProxy.id
            }
            .store(in: &cancellables)
        
        roomProxy.knockRequestsStatePublisher
            // We only care about unseen requests
            .map { knockRequestsState in
                guard case let .loaded(requests) = knockRequestsState else {
                    return []
                }
                
                return requests
                    .filter { !$0.isSeen }
                    .map(KnockRequestInfo.init)
            }
            // If the requests have the same event ids we can discard the output
            .removeDuplicates { Set($0.map(\.eventID)) == Set($1.map(\.eventID)) }
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .weakAssign(to: \.state.unseenKnockRequests, on: self)
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                RoomLoadSignposts.event(.retryDecryption)
                self?.roomProxy.timeline.retryDecryption(sessionIDs: nil)
            }
            .store(in: &cancellables)
    }
    
    private func processIdentityStatusChanges(_ changes: [IdentityStatusChange]) async {
        for change in changes {
            switch change.changedTo {
            case .pinViolation:
                guard case let .success(member) = await roomProxy.getMember(userID: change.userId) else {
                    MXLog.error("Failed retrieving room member for identity status change: \(change)")
                    continue
                }
                
                identityPinningViolations[change.userId] = member
            case .verificationViolation:
                guard case let .success(member) = await roomProxy.getMember(userID: change.userId) else {
                    MXLog.error("Failed retrieving room member for identity status change: \(change)")
                    continue
                }
                
                identityVerificationViolations[change.userId] = member
            default:
                identityVerificationViolations[change.userId] = nil
                identityPinningViolations[change.userId] = nil
            }
        }
        
        if let member = identityVerificationViolations.values.first {
            state.footerDetails = .verificationViolation(member: member,
                                                         learnMoreURL: appSettings.identityPinningViolationDetailsURL)
        } else if let member = identityPinningViolations.values.first {
            state.footerDetails = .pinViolation(member: member,
                                                learnMoreURL: appSettings.identityPinningViolationDetailsURL)
        } else {
            state.footerDetails = nil
        }
    }
    
    private func updateVerificationBadge() async {
        guard roomProxy.infoPublisher.value.isDM,
              let dmRecipient = roomProxy.membersPublisher.value.first(where: { $0.userID != roomProxy.ownUserID }),
              case let .success(userIdentity) = await clientProxy.userIdentity(for: dmRecipient.userID, fallBackToServer: true) else {
            state.dmRecipientDetails.verification = .notVerified
            return
        }
        
        guard let userIdentity else {
            // Bridged contacts (Google Voice, SMS) have no cross-signing identity of their
            // own, so a missing one is ordinary here — not a programming error to trap on.
            MXLog.info("No identity for \(dmRecipient.userID); treating the DM as unverified.")
            state.dmRecipientDetails.verification = .notVerified
            return
        }
        
        state.dmRecipientDetails.verification = userIdentity.verificationState
    }
    
    private func resolveIdentityPinningViolation(_ userID: String) async {
        defer {
            hideLoadingIndicator()
        }
        
        showLoadingIndicator()
        
        if case .failure = await clientProxy.pinUserIdentity(userID) {
            state.bindings.alertInfo = .init(id: .unknown, title: L10n.commonError)
        }
    }
    
    private func resolveIdentityVerificationViolation(_ userID: String) async {
        defer {
            hideLoadingIndicator()
        }
        
        showLoadingIndicator()
        
        if case .failure = await clientProxy.withdrawUserIdentityVerification(userID) {
            state.bindings.alertInfo = .init(id: .unknown, title: L10n.commonError)
        }
    }
    
    private func buildPinnedEventContents(timelineItems: [TimelineItemProxy]) {
        var pinnedEventContents = OrderedDictionary<String, AttributedString>()
        
        for item in timelineItems {
            // Only remote events are pinned
            if case let .event(event) = item,
               let eventID = event.id.eventID {
                pinnedEventContents.updateValue(pinnedEventStringBuilder.buildAttributedString(for: event) ?? AttributedString(L10n.commonUnsupportedEvent),
                                                forKey: eventID)
            }
        }
        
        state.pinnedEventsBannerState.setPinnedEventContents(pinnedEventContents)
        
        // If it's the first time we are setting the pinned events, we should select the initial event if available.
        if let initialSelectedPinnedEventID {
            state.pinnedEventsBannerState.setSelectedPinnedEventID(initialSelectedPinnedEventID)
            self.initialSelectedPinnedEventID = nil
        }
    }
    
    private func updateRoomInfo(_ roomInfo: RoomInfoProxyProtocol) {
        state.roomTitle = roomInfo.displayName ?? roomProxy.id
        state.roomAvatar = roomInfo.avatar
        state.dmRecipientDetails.statusEmoji = roomInfo.statusEmoji
        state.hasOngoingCall = roomInfo.hasRoomCall
        state.activeRoomCallIntent = roomInfo.activeRoomCallIntent
        state.hasSuccessor = roomInfo.successor != nil
        state.isDM = roomInfo.isDM
        
        let pinnedEventIDs = roomInfo.pinnedEventIDs
        // Only update the loading state of the banner
        if state.pinnedEventsBannerState.isLoading {
            state.pinnedEventsBannerState = .loading(numbersOfEvents: pinnedEventIDs.count)
        }
        
        switch (roomInfo.isDM, roomInfo.joinRule) {
        case (false, .knock), (false, .knockRestricted):
            state.isKnockableRoom = true
        default:
            state.isKnockableRoom = false
        }
        
        if let powerLevels = roomInfo.powerLevels {
            state.canSendMessage = powerLevels.canOwnUser(sendMessage: .roomMessage)
            state.canJoinCall = powerLevels.canOwnUserJoinCall()
            state.canAcceptKnocks = powerLevels.canOwnUserInvite()
            state.canDeclineKnocks = powerLevels.canOwnUserKick()
            state.canBan = powerLevels.canOwnUserBan()
        }
        
        state.roomHistorySharingState = roomInfo.historySharingState
    }
    
    /// DM verification badge identity lookup with a timeout. Cross-signing/key
    /// resolution must not block first render, so when the budget expires we
    /// keep the `.notVerified` placeholder and log a non-fatal instead.
    /// (updateVerificationBadge itself already degrades to `.notVerified` on
    /// lookup failure; the timeout only bounds how long we wait for it.)
    private func warmCryptoWithTimeout() async {
        let signpostID = RoomLoadSignposts.begin(.cryptoWarmup)
        defer { RoomLoadSignposts.end(.cryptoWarmup, id: signpostID) }
        
        let finished: Bool? = await RoomLoadTimeout.withTimeout(seconds: RoomLoadBudgets.cryptoWarmup) { [weak self] in
            guard let self else { return false }
            await self.updateVerificationBadge()
            return true
        }
        
        // `nil` means the timeout fired first; `false` means the view model
        // went away, in which case there is nothing to degrade or log.
        guard finished == nil else { return }
        
        RoomLoadSignposts.event(.cryptoWarmupTimeout)
        MXLog.warning("RoomScreen crypto warmup exceeded budget of \(RoomLoadBudgets.cryptoWarmup)s; keeping the unverified badge placeholder.")
        analyticsService.trackError(context: "RoomScreen crypto warmup timed out; showing the unverified verification badge placeholder.",
                                    domain: .E2EE,
                                    name: .UnknownError)
        state.dmRecipientDetails.verification = .notVerified
    }
    
    /// Builds the pinned-events timeline after first paint. `pinnedEventsTimeline()`
    /// constructs a second Rust timeline, so it runs here — in the background —
    /// instead of racing room load on the homeserver-reachable signal.
    private func loadPinnedEventsTimeline() async {
        guard pinnedEventsTimelineItemProvider == nil else { return }
        
        let signpostID = RoomLoadSignposts.begin(.pinnedBanner)
        defer { RoomLoadSignposts.end(.pinnedBanner, id: signpostID) }
        
        let loaded: Bool? = await RoomLoadTimeout.withTimeout(seconds: RoomLoadBudgets.pinnedBanner) { [weak self] in
            guard let self else { return false }
            guard case let .success(pinnedEventsTimeline) = await self.roomProxy.pinnedEventsTimeline() else { return false }
            
            if self.pinnedEventsTimelineItemProvider == nil {
                self.pinnedEventsTimelineItemProvider = pinnedEventsTimeline.timelineItemProvider
            }
            return true
        }
        
        guard loaded == nil else { return }
        
        RoomLoadSignposts.event(.pinnedBannerTimeout)
        MXLog.warning("RoomScreen pinned-events timeline exceeded budget of \(RoomLoadBudgets.pinnedBanner)s; the pins banner stays in its loading state.")
    }
    
    private func acceptKnock(eventID: String) async {
        guard case let .loaded(requests) = roomProxy.knockRequestsStatePublisher.value,
              let request = requests.first(where: { $0.eventID == eventID }) else {
            return
        }
        
        state.handledEventIDs.insert(eventID)
        switch await request.accept() {
        case .success:
            break
        case .failure:
            userIndicatorController.submitIndicator(.init(id: Self.errorIndicatorIdentifier, type: .toast, title: L10n.errorUnknown))
            state.handledEventIDs.remove(eventID)
        }
    }
    
    private func markAllKnocksAsSeen() async {
        guard case let .loaded(requests) = roomProxy.knockRequestsStatePublisher.value else {
            return
        }
        state.handledEventIDs.formUnion(Set(requests.map(\.eventID)))
        
        let failedIDs = await withTaskGroup(of: (String, Result<Void, KnockRequestProxyError>).self) { group in
            for request in requests {
                group.addTask {
                    await (request.eventID, request.markAsSeen())
                }
            }
            
            var failedIDs = [String]()
            for await result in group where result.1.isFailure {
                failedIDs.append(result.0)
            }
            return failedIDs
        }
        state.handledEventIDs.subtract(failedIDs)
    }
    
    private func handleTappedPinnedEventsBanner() {
        analyticsService.trackInteraction(name: .PinnedMessageBannerClick)
        if let eventID = state.pinnedEventsBannerState.selectedPinnedEventID {
            Task {
                switch await roomProxy.loadOrFetchEventDetails(for: eventID) {
                case .success(let event):
                    if appSettings.threadsEnabled,
                       let threadRootEventID = event.threadRootEventId() {
                        actionsSubject.send(.focusEvent(eventID: threadRootEventID))
                        actionsSubject.send(.displayThread(threadRootEventID: threadRootEventID, focussedEventID: eventID))
                    } else {
                        actionsSubject.send(.focusEvent(eventID: eventID))
                    }
                case .failure:
                    userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
                }
            }
        }
        state.pinnedEventsBannerState.previousPin()
    }
    
    // MARK: Loading indicators
    
    private static let loadingIndicatorIdentifier = "\(RoomScreenViewModel.self)-Loading"
    private static let errorIndicatorIdentifier = "\(RoomScreenViewModel.self)-Error"
    
    private func showLoadingIndicator() {
        userIndicatorController.submitIndicator(.init(id: Self.loadingIndicatorIdentifier, type: .toast, title: L10n.commonLoading))
    }
    
    private func hideLoadingIndicator() {
        userIndicatorController.retractIndicatorWithId(Self.loadingIndicatorIdentifier)
    }
}

extension RoomScreenViewModel {
    static func mock(roomProxyMock: JoinedRoomProxyMock,
                     clientProxyMock: ClientProxyMock = ClientProxyMock(.init()),
                     appHooks: AppHooks = AppHooks()) -> RoomScreenViewModel {
        RoomScreenViewModel(userSession: UserSessionMock(.init(clientProxy: clientProxyMock)),
                            roomProxy: roomProxyMock,
                            initialSelectedPinnedEventID: nil,
                            ongoingCallRoomIDPublisher: .init(.init(nil)),
                            appSettings: .volatile(),
                            appHooks: appHooks,
                            analyticsService: AnalyticsServiceMock(.init()),
                            userIndicatorController: UserIndicatorControllerMock())
    }
}

private extension KnockRequestInfo {
    init(from proxy: KnockRequestProxyProtocol) {
        self.init(displayName: proxy.displayName,
                  avatarURL: proxy.avatarURL,
                  userID: proxy.userID,
                  reason: proxy.reason,
                  eventID: proxy.eventID)
    }
}

