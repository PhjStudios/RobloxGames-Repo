# Consolidated platform-hardening review

Historical Phases 34–37 were reviewed as one change against clean baseline
`ddd01c9c0d459d91639c122c5ae784c1e59608c3`, on `codex/platform-hardening`.
This is the consolidated implementation review, not Phase 38 or a separate
acceptance audit. Implementation, scoped local verification and this review are
complete. The milestone gate has cumulative 1,601/1,601 coverage and all four
builds passed. Delivery branch: `codex/platform-hardening`; external acceptance
remains pending.

## Resolved findings

- Physical font measurement now includes saved UIScale in the rendering client.
  Roblox preferred text size is applied once. Lobby headers, inventory toolbar,
  Match compact HUD and modal footers reflow within actual safe-area dimensions.
  The minimum landscape safe height is accepted instead of rejecting its render.
- Focus survives Lobby reparenting and scale changes by stable control identity.
  Disabled/hidden/destroyed controls cannot retain focus; modal scopes contain it.
  Roblox owns Escape; Lobby Backspace preserves text entry and Core menu behavior.
- Remaining chest confirmation/result and initial Match loading messages use
  whole-message keys. The bounded source-reference guard validates literal keys
  and registries, with positive and negative fixtures.
- Optional effect construction cleans partially built roots on failure. Audio
  admission, asset failure and cleanup remain bounded and independent of combat.
- Controller cursor polling uses the active engine controller enum. The existing
  Tower-context guard preserves R1 targeting while placement uses R1 for hotbar
  cycling. Native emulator taps do not prove sustained analog movement.
- Measurement harnesses retain unavailable observations, bound their samples,
  disconnect actual listeners and dispose owned profiler resources. Profiler
  setup and restore failures cannot produce a successful evidence report.
- Analytics runs after authoritative outcomes, rejects private/unbounded fields,
  bounds delivery and correlation, and contains sink exceptions or attempted
  yields. External delivery remains disabled. Development commands exist only
  in test sources and fail closed on ambiguous authorization or staging identity.

The final source review found no open material localization, accessibility,
presentation, audio, authority, analytics or test-isolation defects. The full
milestone sequence ran once: StyLua check/verify, Selene configuration/source
lint and all four builds passed. Headless coverage initially passed 1,599/1,601;
a diagnostic rerun reproduced two stale ReadyController text expectations.
Four test-only assertions were updated, formatted/linted, and the affected
ReadyController/ReadyView/ReadyViewModel bundle passed 30/30. Cumulative coverage
is 1,601/1,601, with no production-source change or repeated full gate. Overlapping
focused counts are not added together.

## Evidence limits

The source guard cannot prove dynamic/aliased key expressions, arbitrary argument
semantics, absence of every English literal, rendered fit or assistive-device
acceptance. Manual critical-flow review and recorded engine observations are
separate evidence. The final Lobby header follow-up closes failures retained in
the earlier six-layout record; it is not a new complete six-layout flow run.

The initial three-cycle trace passed owned-object cleanup but showed 64.324 MB
of unattributed Studio process growth while Rojo source updates occurred. The
unchanged-source follow-up completed three actual cycles in 504.379 seconds:
Ready memory decreased 7.796875 MB, instances rose once by two and stayed flat,
and all owned entities/effects/probe connections were cleared. Its 191-file
fingerprint remained unchanged. The earlier growth was not reproduced and is
still unexplained; different viewport/preferences also limit direct comparison.
This supports the bounded local cleanup result, not long-duration or physical-
device memory acceptance. The following warmed 12.199-second Ready probe had
732 frames, p95 17.9634 ms, maximum 23.9034 ms and flat instance counts. The
separate earlier idle trace's 210.63 ms worst frame remains recorded; it is not
silently discarded as an assumed GC event.

Final-source Garden Hard supplies an actual four-client, twelve-tower,
twenty-enemy density trace and boss-bracketed client/server MicroProfiler
captures. Client frame p95 was 19.2138 ms over 30.399 seconds. Server service-step
mean inclusive CPU was 0.448744 ms per captured frame, maximum span 3.136342 ms;
snapshot publication was the largest measured contributor. This heavier scene
has separate provisional review headroom from the earlier Easy scenario.
Measured frame cost does not justify speculative protocol/index/pooling changes.
Two active Endless windows also retained Playing observations, with boss health
visible in the second; their later MicroProfiler was already Results and is not
claimed as an active boss CPU trace. Viewpoint scene counts, short traces and
inclusive CPU spans do not establish GPU, hosted-server or long-run capacity.

The later 12.150-second Hard trace also remained active boss/dense combat; its
p95 was 19.4566 ms and it is not described as a cleanup measurement. A separate
natural terminal observation reached Results at wave 34/base health zero, then
an accepted ordinary replay produced Ready with no towers/enemies/effects and
three presentation descendants. The terminal result enum was not reliably
captured. All four temporary clients closed and Match Edit emulator/camera,
test attributes and ATD-owned inventories were restored, with zero ATD runtime
residue. The [final cleanup record](evidence/platform-final-cleanup.json) also
confirms Lobby preference/emulator/camera restoration, unchanged queue-root
inventory and zero managed Rojo processes. The original profiler frame limit
was not captured; its documented default was restored. Exact pane arrangement
was not recorded.

Physical devices, sustained analog/full controller behavior, current published
travel/profile/reward/reconnect flows, owned-audio listening, independent newcomer
testing and external analytics delivery remain acceptance gates. See the design
lock, test matrix, presentation manifest and performance evidence for the exact
boundaries. Production, platform availability and stored staging versions remain
unchanged; Phase 38 has not begun.
