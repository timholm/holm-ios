# Room loading: phases, signposts, integration points

Worker 4 (room loading) owns `Screens/RoomScreen/` and the helpers in
`ElementX/Sources/Other/Stability/RoomLoading/`. Room loading spans two other
areas; this doc records the integration points so Workers 1 and 2 can drop in
their one-liners, and so Tim knows what to look for in Instruments.

## Signpost contract

- Subsystem: `com.holm.roomload`, category `RoomLoad` (see `RoomLoadSignposts.swift`).
- `room_open` interval: `RoomScreenCoordinator.init` -> `first_paint` event.
  Begun by the coordinator, ended when it receives
  `RoomScreenViewModelAction.roomFirstPaint`.
- `first_paint` event: `RoomScreen.onAppear` -> `RoomScreenViewAction.roomAppeared`
  -> `RoomScreenViewModel.startBackgroundPhases()`.
- Background phases (never block first paint):
  - `crypto_warmup`: DM verification-badge identity lookup, 3s budget
    (`RoomLoadBudgets.cryptoWarmup`). On timeout: unverified placeholder stays,
    `crypto_warmup_timeout` event fires, non-fatal logged via
    `analyticsService.trackError(domain: .E2EE, name: .UnknownError)`.
  - `pinned_banner`: `roomProxy.pinnedEventsTimeline()` creation, 5s budget.
    On timeout the pins banner stays in its loading state.
- `retry_decryption` event: `retryDecryption(sessionIDs:)` kicked off from the
  `didBecomeActive` subscription. Fire-and-forget into the Rust SDK; instrumented
  only, behaviour unchanged.

## Worker 1 integration (`Screens/Timeline/`, do not edit from Worker 4)

1. In `TimelineViewModel.init`, around `buildTimelineViews(timelineItems:)`:
   ```swift
   let signpostID = RoomLoadSignposts.begin(.timelineBuild)
   buildTimelineViews(timelineItems: timelineController.timelineItems)
   RoomLoadSignposts.end(.timelineBuild, id: signpostID)
   ```
2. Around `focusOnEvent` / `paginateBackwards` / `paginateForwards`:
   `RoomLoadSignposts.begin(.gapFill)` / `end` — these are the post-first-paint
   fills; in a healthy trace they start after `first_paint`.

## Worker 2 integration (`Services/`, do not edit from Worker 4)

1. In `TimelineController.init`, around `configureActiveTimelineItemProvider()`:
   `RoomLoadSignposts.begin(.timelineAttach)` / `end`.
2. If `JoinedRoomProxy.timeline` ever becomes lazy, wrap the Rust timeline-handle
   creation in `.timelineAttach` as well — it is currently the biggest unknown on
   the attach path.

## Known render-gate candidates (instrument, don't guess)

- Megolm session/key resolution before cached items decrypt.
- `pinnedEventsTimeline()` creating a second Rust timeline concurrently with load
  (now deferred to post-first-paint).
- `retryDecryption` on `didBecomeActive` racing room open at cold start.
- Anything in `coordinator_setup` beyond `room_viewmodel_init` (that remainder is
  Worker 1/2 code running inside the coordinator init).

## Mac verification (Instruments)

1. Build `ios-stability-roomload` on the Mac, run on device.
2. Product > Profile, choose the "Logging" template (os_signpost).
3. Filter the signpost track: subsystem `com.holm.roomload`.
4. Open a room. Expected: `room_open` begins, `coordinator_setup` and
   `room_viewmodel_init` complete inside it, `first_paint` fires, `room_open`
   ends, then `crypto_warmup` and `pinned_banner` run in the background.
5. To reproduce the slow first render: open the room from telemetry where
   `room.first_render` ~14.6s was seen (16 cached disk events, encrypted room);
   the gap between `room_open` begin and `first_paint` is the render gate, and
   whichever interval is open during it is the culprit.
