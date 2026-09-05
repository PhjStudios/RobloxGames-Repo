# Platform hardening design lock

Status: repository implementation and local milestone verification complete,
historical Phases 34–37 as one outcome. Consolidated review is clean; cumulative
headless coverage is `1,601/1,601`, formatting/lint and all four builds passed.
Delivery branch: `codex/platform-hardening`. External acceptance is incomplete.
Phase 38 is outside scope. Baseline verified clean on 2026-09-04:
`codex/content-onboarding` at `ddd01c9c0d459d91639c122c5ae784c1e59608c3`.
Work branch: `codex/platform-hardening`. Previous milestone evidence is retained;
its full gate was not rerun to establish this baseline.

## Local milestone verification

The full milestone gate ran once: `stylua --check --verify src tests`,
`selene validate-config`, `selene src tests`, and
`lune run tests/verify-builds.luau`. Formatting, lint configuration, source/test
lint and Default/Lobby/Match/Test builds all passed. Headless coverage initially
reported `1,599/1,601`: two ReadyController cases retained stale English
expectations after localization. A diagnostic headless rerun reproduced those
same failures. Four test-only expectations were corrected, formatted and linted;
the affected ReadyController, ReadyView and ReadyViewModel suites then passed
`30/30`. Cumulative coverage is `1,601/1,601`. Production source did not change
after the full gate, and the full gate was not repeated. Consolidated review is
clean. These results complete local milestone verification; external acceptance
requires the separate evidence below.

## Bounded audit and identity

Read-only repository and Studio audit verified GameId `10764687717`, creator
group `35420107` / `PHJGAMES`, Lobby `140661668701496` (version 18, role Lobby,
`lobby.project.json`) and Match `104415140644510` (version 15, role Match,
`match.project.json`). Both were in Edit mode. Streaming is enabled in both.
No experience availability, publication, persistent content, or data change is
authorized by this outcome.

Initial ATD inventory: Lobby `Workspace.ATDSquadQueueZone`, one child/descendant
(Attachment). Match `ServerStorage.ATDMapTemplates`, two children/237 descendants,
208 parts, 31 shadow-casting parts, 21 collidable parts; and
`ReplicatedStorage.ATDPlayableTemplates`, ten children/83 descendants, 73 parts,
zero shadows/collisions. These roots contain zero scripts. Inspected Workspace,
ServerStorage, ReplicatedStorage, SoundService, and Lighting contain no Sound or
Animation assets. Owned-audio listening acceptance remains pending; procedural
tower aiming does not require uploaded animation assets.

Final [cleanup evidence](evidence/platform-final-cleanup.json) confirms both
parents in Edit, unchanged owned-root inventories, cleared runtime roots/test
attributes, restored cameras and Roblox preferences, and no remaining managed
Rojo processes or temporary clients. Lobby's original Xbox emulator and Match's
default device were restored. Profiler capture/display are off; the frame limit
was restored to the documented 256 default because its initial value was not
captured. Exact original dock-pane arrangement was not recorded. No place was
saved or published. The fresh-source [chest modal follow-up](evidence/platform-lobby-final-modal.json)
records readable Confirm/Cancel at pseudo50 and Largest text; its nine overlap
candidates were disabled background controls beneath the modal.

Findings at audit start: critical English was spread through Lobby/Match views,
controllers, view models, input hints and content descriptions. Match lacked
Lobby preference integration; keyboard focus and party invitation needed
controller-safe paths; fixed-height Match panels constrained expansion. Active
Match presentation allocated short-lived attack parts (32 concurrent, eight low
detail), had no aiming/audio owner, and sent full private projections up to 10 Hz
plus reliable attack events. Existing bounds and historical scene counts were
not frame/memory/network traces. Structured logging existed; a bounded analytics
delivery contract did not.

## Platform and evidence decision

| Candidate | Current outcome acceptance | Required evidence |
| --- | --- | --- |
| Desktop mouse/keyboard | Locally emulated geometry and bounded interactions; full acceptance pending | Complete current-tree first-session/full-match matrix; published client and measured hardware |
| Desktop keyboard only | Locally verified focus/Backspace interactions in Studio; full acceptance pending | Remaining critical controls and complete current-tree first-session/full-match matrix |
| Phone landscape touch | Locally emulated small/common layouts and touch placement; externally pending | Complete landscape loop on physical phone and published client |
| Tablet touch | Locally emulated layout; externally pending | Complete physical-tablet touch loop and published client |
| Controller/TenFoot | Locally emulated layout and discrete Ready/placement; full acceptance pending | Sustained analog hardware input, complete upgrade/target/sell and first-session/full-match controller loop; published controller client |
| Console hardware | Conditional external gate, not advertised | Genuine console client/hardware acceptance only before advertising console |
| VR | Deferred | Separate comfort/interaction/performance decision |

Evidence labels are `deterministic` (headless contracts), `Studio-emulated`
(engine/input/layout emulation), `local-hardware` (this development machine),
`physical-device` (named real device), `published-client` (named private version),
and `external-service` (reviewed destination). Labels can coexist but cannot be
substituted. No new platform or language is advertised from this audit. No
screen-reader or assistive-device support is claimed without its own test.

### Current local evidence

The [final Lobby geometry record](evidence/platform-lobby-final-ui.json) covers
minimum landscape, common phone, tablet, desktop, ultrawide and TenFoot with
Roblox Largest text, transparency 0, reduced motion, pseudo50 and saved UI scale
0.75. Actual sampled viewports range from 666×374 (safe root 666×316) and
749×361 (safe root 749×303) to 3440×1438. This record retains the original
ProfileReadiness label failure on tablet/desktop/TenFoot; the
[separate header follow-up](evidence/platform-lobby-header-followup.json) closes
those failures on fresh source. The final observed controls have zero
text-overflow, undersized-touch, fixed-clipping and overlay candidates; ordinary
scrollable off-viewport controls remain recorded. Geometry does not establish
scroll activation or a complete first-session/full-match flow.

The records verify stable focus through repeated UI-scale changes and keyboard
Backspace from Settings to Home. Native Escape opens Roblox's Core menu.
The follow-up console contains one aggregated GetLobbyBanner rate-limit warning
during rapid input/layout exercise, with no invalid-focus warning or Luau error.
Local controller Ready and placement were observed separately. A native stick
trace captured 600 frames/20 axis events, peak magnitude 1, but zero frames with
a nonzero polled axis: brief injected taps do not establish sustained analog
input. Sustained analog hardware acceptance and complete controller
upgrade/target/sell behavior remain pending; inconsistent native action-state
observations are not promoted to passes.

No candidate is newly advertised by these records. Physical phone/tablet,
genuine console, published-client full-flow, screen-reader and assistive-device
acceptance remain external gates. Historical published staging observations
belong to their original source/outcome, not this branch.

## Accessibility and localization contracts

Keep saved settings/profile identifiers and schema compatible. Resolve Roblox
preferences from GuiService on both clients and on live changes. Effective reduced motion is
Roblox OR saved reduced motion; it disables camera shake and optional positional
motion/flashes. Low detail and other-player-effect settings reduce optional
presentation only. Roblox applies preferred font enlargement itself; retain
that engine behavior, combine it with bounded saved UI scale, and measure/reflow
using the ordinary client TextService context at the actual physical UI scale.
Preferred enlargement is nonlinear after UIScale; measuring only logical font
and width can under-allocate text height. Do not apply a second manual font
multiplier. Reflow/scroll instead of shrinking below readable sizes. Preferred
transparency multiplies authored panel transparency (0 is opaque, 1 is authored),
preserving text/background contrast.

Minimum criteria: 44 px touch controls, 16 px body text at default scale, visible
focus (shape/stroke plus state), deterministic traversal and modal containment,
restoration to a surviving control, safe-area containment, no required text entry
for controller, explicit touch placement confirmation, and consistent Back at
every depth. Escape remains owned by Roblox's Core menu. Lobby offers Backspace
for application Back (passing through focused text entry and the Core menu);
Match uses Q for its cancel action. Target text contrast 4.5:1 and meaningful
non-text contrast 3:1.
Warnings, ownership, health, targeting, ranges, boss/base/result/reward meaning
must remain visible without sound, color discrimination, or transient effects.
No authored strobing; no repeating bright full-screen flashes. Audit live motion
and contrast separately from deterministic configuration tests.

English source messages use stable semantic keys and typed bounded named
arguments. Internal IDs remain distinct from player-facing names. Content names
are explicitly stable/proper names; descriptions and sentences are messages.
No sentence is assembled by concatenating translated fragments. Central formats
cover integer/decimal, percent/odds, timer/wave, Gold and Battle Cash. Reject
missing/extra arguments, markup/control characters, nonfinite/out-of-range values
and unknown keys. Rich text/automatic localization must not reinterpret arguments.
Automated pseudo modes expand source text by 30–50% after validation and preserve
arguments; check the real expanded UI for clipping/overlap/hidden actions.
English source is the current language scope. Additional languages may be
advertised only after human translation and review.
The bounded verifier checks literal `Localization.text/format/bind` and
`WorldMessages.set` keys, simple literal fallback branches, known Lobby factory
keys, and enum/content-registry references. It does not prove computed or aliased
keys, arbitrary argument semantics, absence of raw English, visual fit or
assistive-device acceptance; those require the separate contract tests, manual
critical-flow review and appropriate runtime evidence.

## Presentation, assets and measurement

Presentation is a client projection of validated authority. Generic cue registry
prioritizes persistent navigation/placement/ownership/health, then boss/base/result
warnings, then transaction feedback, then disposable attack/impact/kill decoration.
Late/duplicate/missing events are harmless; snapshot recovery owns lasting state.
Aim and idle return never delay server attacks. Reduced effects keep essential
signals. Own and clean all connections, sounds, models, effects and UI state.

Master/music/SFX/UI routing applies settings immediately; Lobby/Match/boss/
victory/defeat transitions have bounded concurrency and silent asset-failure
fallbacks. No invented IDs, purchases, uploads or code-bearing imported models.
Manifest assets require owner/license, source, approved identifier, permission
check and intended usage. Existing original primitive geometry remains the visual
fallback. All 18 audio manifest entries (five music scenes and 13 feedback cues)
remain unavailable; provenance/permission and listening/mix acceptance require
approved owned assets. Procedural aiming needs no
uploaded animation; asset-backed animation needs approval only if added.

Measure before optimization: idle, normal, boss, dense four-player, results,
cleanup and repeated finite/Endless scenarios. Record duration, environment,
hardware/emulation, tool, samples, target/warning/failure thresholds and limits in
the [performance evidence document](PERFORMANCE_BUDGETS.md). Measured local
development regression thresholds apply only to their recorded environment;
representative supported-device and published-client budgets remain unverified.
Track frame p50/p95/max, update time, first-interactive time, total/script memory,
entities/effects/sounds/UI/connections, network event rate and serialized payload
estimates separately from transport bytes, triangles/draws/shadows/collisions/
textures/streaming and cleanup growth. Existing caps are safety limits, not
measured platform acceptance. Retain current protocols/indexing/pooling until a
trace justifies change; never move authoritative outcomes to unreliable delivery.

## Analytics, operational logging and development tools

Versioned allowlisted events cover onboarding, party/queue, travel/admission/
return/recovery, Ready/match/terminal/wave buckets, Gold sources/sinks, chest
quantity/pity/acquisition, and operational failure categories. Emit only after
successful authoritative outcomes; failures have explicit operational vocabulary.
Never emit inside retryable transaction callbacks. Delivery cannot block gameplay,
determine persistence, or change rewards. No per-enemy/per-attack analytics.

No names, chat, free-form user text, profiles, inventories, receipts, access codes,
teleport data, secrets or unnecessary raw identifiers. Correlation uses bounded
ephemeral session/operation tokens, never reusable account identity. Dictionary
specifies dimensions, bounded buffer/rate/batch/retry/drop/shutdown behavior and
mock-sink tests. External sink remains disabled. Retention of local volatile
events ends at shutdown; external retention/dashboard usefulness requires reviewed
provider evidence. Structured operational warnings/errors are bounded and
rate-limited, with one owner per handled failure; hostile fields are rejected.
No destination/dashboard is configured. External delivery, dashboard usefulness,
provider retention behavior and Packet 37.6 remain unverified by mock-sink tests.

Development commands live under tests, absent from production builds/remotes.
Authorization fails closed on ambiguous identity/environment/role. Permit only
confirmed staging Studio or explicitly allowlisted private-test users, and narrow
wave/test Battle Cash/state/map/presentation/performance actions. No persistent
Gold/inventory/profile/store/receipt/teleport mutation. Reuse the production
runtime for deterministic read-only balance reports with recorded content version
and inputs; do not introduce a second simulation.

## External acceptance gates

Repository implementation and local milestone verification are complete. Physical
phone/tablet and sustained controller analog input, a new private
published version with complete first-session/full-match checks, approved audio
for the 18 manifest entries and listening/mix checks, an
uninstructed newcomer and analytics destination/dashboard acceptance stay pending
until actually supplied/authorized. Any later approval must name exact
experience/version, roots/assets or provider/events/accounts, expected writes,
privacy/retention boundary, abort conditions, cleanup and rollback. Production,
persistent Team Create edits and availability settings remain untouched.
Genuine console hardware acceptance is required only before advertising console;
human translation and review are required only before advertising additional
languages. Neither is inferred from desktop controller emulation or pseudo text.
No uploaded animation is essential to the current procedural aiming architecture;
future authored animation or persistent asset changes require their own bounded
approval. English source plus pseudolocalization does not advertise another
language. No newly published version of this branch, external event delivery or
production activity is claimed.

### Next bounded approval: private staging publication

The reviewable source is implementation commit
`cc87b64360b07342682828eee7dfea6cb87c9573`; the following documentation commit
does not alter builds. Publication is not yet authorized. The proposed write is
one new private place version for each PHJGAMES staging place in GameId
`10764687717`: Lobby `140661668701496` from `lobby.project.json`, and Match
`104415140644510` from `match.project.json`. Preserve the existing Studio-owned
assets and all experience settings. External analytics remains disabled.

Before any approved publication, reverify identity, private status, current
version and owned-root inventories; abort on any mismatch or newer unrelated
place changes. The audit recorded Lobby version 18 and Match version 15; record
the actual pre-publication versions as rollback targets, without overwriting
subsequent user work. Sync the reviewed role-specific source, inspect the source
and asset inventories, publish each place once, then verify the resulting version
identifiers and stop/disconnect Rojo. No store reset, asset edit, purchase or
platform-availability change is included. If only one publication succeeds, stop
and report the partial state before taking any rollback action. Restoration of
the recorded prior place versions requires the same explicit bounded approval.

Published-client testing additionally needs designated test accounts and approval
for their ordinary private-staging profile/queue/travel/reward operations. This
publication proposal alone does not authorize those data writes or complete
first-session, hardware, newcomer, owned-audio or analytics acceptance.
