# Ant Tower Defense — Game Design Decision Register

## Purpose

This document records the product and architecture-affecting decisions approved
for the core Ant Tower Defense project. The original Core-001 register is the
evidence for Packet 00.2 of `docs/DEVELOPMENT_PLAN.md`; dated addenda record
later decisions without rewriting that historical checkpoint.

The decisions below use the roadmap's recommended defaults. They guide future
implementation but do not authorize gameplay coding, Roblox publishing,
production-data changes, or monetization.

## Decision status

- Decision set: Core-001
- Recorded: 2026-08-25
- Packet: 00.2
- Status: Accepted for core development
- Current roadmap checkpoint: the Playable Local Match, Persistent Lobby Loop,
  Squad Travel Loop, and Content and Onboarding outcomes through historical
  Phase 33 are complete. Platform, Presentation, Performance, and Analytics
  (Phases 34–37) has completed repository implementation and local milestone
  verification on `codex/platform-hardening`: clean consolidated review,
  cumulative `1,601/1,601` headless coverage, formatting/lint and all four builds
  passed. Delivery branch: `codex/platform-hardening`.
  External acceptance is incomplete and Phase 38 has not begun.

## Product identity and game loop

### GD-001 — Core game format

**Decision:** Ant Tower Defense is a cooperative Roblox tower-defense experience
with a persistent lobby and isolated matches.

The core player loop is:

    Join lobby
      → load profile
      → manage inventory/loadout/settings/chests
      → form a squad
      → choose map and difficulty
      → enter a reserved match
      → ready
      → defend through waves
      → receive results and rewards
      → retry or return to the lobby

**Reason:** This creates a complete social and progression loop while keeping
individual matches isolated and reproducible.

### GD-002 — Roblox place architecture

**Decision:** The experience uses two primary places:

- A Lobby place for profiles, inventory, loadouts, settings, gacha, parties, and
  queue formation.
- A Match place that loads the selected map/difficulty and runs the authoritative
  tower-defense simulation.

**Implementation effect:** Common, lobby-only, and match-only source must remain
separated. Ownership and place requirements are recorded in
`docs/PLACE_INVENTORY.md`; the completed creation, centralized PlaceIds, and
isolated Studio/Rojo verification are recorded in `docs/MULTI_PLACE_GATE.md`.

## Players, squads, and matchmaking

### GD-003 — Match size

**Decision:** A match supports one to four active players.

**Reason:** Four players supports solo and cooperative strategy while keeping
placement density, UI, rewards, and server simulation manageable.

**Revisit trigger:** Only revisit after real playtests demonstrate that four
players is too restrictive or harms map balance.

### GD-004 — Queue privacy

**Decision:** Queue privacy is either `Public` or `PartyOnly`. Solo is a squad
size, not a privacy mode. A `PartyOnly` solo queue remains private and does not
reserve space for future party members.

Public queues in the initial core release form from players in the same lobby
server. Cross-server public matchmaking is deferred to Phase 43.

**Reason:** This provides public-stranger play without making the initial
lobby-to-match implementation depend on global matchmaking infrastructure.

### GD-005 — Captain authority

**Decision:** The first valid enrollment becomes captain. An atomically enrolled
party uses its current party leader as captain.
Only the captain can select:

- Map.
- Difficulty.
- Queue privacy.
- Maximum player count.
- Match start.

If the captain leaves, leadership passes to the earliest remaining valid member.
An empty queue resets completely.

### GD-006 — Party separation

**Decision:** A social party exists independently from physical queue membership.
The party leader may atomically enroll the complete present party, but invited,
absent, and future members reserve no slots. A party enrollment is one unit: a
membership change or intentional leave removes it rather than silently splitting
the roster. Starting remains a manual captain action.

**Reason:** Separating party and queue state prevents invitations, walking out of
a queue, or partial teleports from producing ambiguous membership.

## Loadout and tower ownership

### GD-007 — Equipped loadout size

**Decision:** Each player equips five towers.

**Reason:** Five slots allow meaningful role choices while remaining readable on
mobile and gamepad hotbars.

**Revisit trigger:** Changing this after profiles exist requires a saved-data and
UI migration decision.

### GD-008 — Duplicate representation

**Decision:** Duplicate tower copies are stored as unique persistent unit records,
not only as a single count.

Each unit record is designed to support future:

- Unique unit ID.
- Favorite status.
- Lock status.
- Merge/ascension rank.
- Cosmetic skin.
- Shiny or special appearance.
- Traits or other instance-specific progression if later approved.

**Reason:** Unique records preserve player ownership choices and prevent a later
merge system from requiring a destructive inventory-model rewrite.

**Data constraint:** Unit records must remain compact, versioned, and subject to a
documented capacity/size strategy before large inventories are possible.

### GD-009 — Duplicate loadout rule

**Decision:** Two copies of the same base tower definition cannot occupy multiple
loadout slots during the core release.

The player chooses which owned copy represents that tower in the loadout.

**Reason:** This prevents duplicates from bypassing intended roster diversity or
placement-limit design. A future mode may explicitly override this rule only
through a new recorded decision.

### GD-010 — Match upgrades versus persistent progression

**Decision:** Tower upgrades purchased with Battle Cash last only for the current
match. Persistent merge/ascension is a separate post-core system.

**Reason:** Keeping the two layers distinct makes costs, UI, balance, and saved
data understandable.

## Currencies and economy

### GD-011 — Currency names and scopes

**Decision:** The provisional currency names are:

- **Gold:** persistent lobby currency.
- **Battle Cash:** match-only placement and upgrade currency.

Gold never becomes spendable match money. Battle Cash never transfers back to
the lobby.

**Reason:** Distinct names, icons, and scopes prevent players from confusing
long-term progression with one-match strategy.

### GD-012 — Battle economy ownership

**Decision:** Battle Cash is individual per player. Players receive:

- Difficulty-defined starting Battle Cash.
- Income from eligible damage caused by their own placed towers.
- Team wave-completion stipends.
- Future economy-tower income when that system is approved.

Damage income is capped at actual health removed so overkill cannot create extra
money.

**Reason:** Damage-based income avoids competitive last-hit stealing while
preserving personal tower ownership and decisions.

### GD-013 — Tower selling

**Decision:** Selling refunds 70% of the placed tower's total Battle Cash
investment, using one server-owned rounding rule.

**Status:** Provisional balance value.

**Reason:** Players can correct mistakes without making all placements freely
reversible.

### GD-014 — Persistent Gold monetization

**Decision:** Gold remains earn-only throughout core development and closed
alpha. Gold will not be sold for Robux during the core roadmap.

Any later paid-Gold decision belongs to Phase 44 and requires:

- A new explicit product decision.
- Receipt-safe purchase granting.
- Paid-random-item policy review.
- Regional restriction handling.
- Updated disclosures and compliance questionnaire.
- A fairness review proving core success does not require payment.

**Reason:** This removes monetization and paid-random-item risk while the core
game, data safety, and balance are still unproven.

## Gacha and duplicates

### GD-015 — Chest acquisition

**Decision:** Towers can be acquired from server-owned chests/banners using
persistent Gold.

The core system supports:

- One pull.
- Ten pulls as one transaction.
- Exact disclosed outcome odds.
- A visible pity counter and explanation.
- New-versus-duplicate results.
- Server-generated outcomes.
- Idempotent transaction handling.

**Reason:** These requirements make the system understandable, fairer, and
resistant to duplicated requests.

### GD-016 — Odds disclosure

**Decision:** Exact final outcome probabilities are shown even while Gold is
earn-only and paid-random-item disclosure may not technically apply.

**Reason:** Transparent odds build trust and prevent the UI from needing a
policy-driven redesign if monetization is reconsidered later.

### GD-017 — Merge implementation

**Decision:** Duplicate merging/ascension is data-compatible but not part of the
core closed-alpha scope. It remains in Phase 41.

No temporary merge mechanic should be added during inventory or gacha work.

## Match structure

### GD-018 — Difficulties and wave counts

**Decision:** Provisional finite modes are:

- Easy: 20 waves.
- Normal: 30 waves.
- Hard: 40 waves.
- Endless: unlimited waves.

Each finite difficulty changes composition, starting resources, base health,
enemy mechanics, and rewards—not only enemy health.

**Status:** The counts are implemented exactly in content version 1. Their
current balance is documented in `CONTENT_BALANCE.md`; the Content and
Onboarding consolidated gate passed on 2026-09-04.

### GD-019 — Boss cadence

**Decision:** Boss waves occur every 10 waves. Finite modes use progressively
stronger bosses at their applicable ten-wave milestones.

Endless preserves the every-ten-waves boss cadence.

### GD-020 — Wave timing

**Decision:**

- A wave has a server-owned maximum scheduled duration.
- If every scheduled enemy is resolved early, the next wave begins after a
  five-second intermission.
- If the deadline expires first, the next wave begins while surviving enemies
  remain active.
- Surviving enemies never disappear merely because their wave timer ended.
- The defender base reaching zero health is the normal match loss condition.

**Reason:** This creates a clear timer rule and intentional pressure from
overlapping waves.

### GD-021 — Initial ready check

**Decision:**

- Ready timeout is 45 seconds.
- The match starts early when every active participant is ready.
- At timeout, unready players are returned/removed and ready players continue.
- If nobody is ready, the match cancels.

**Status:** Accepted behavior; exact UX may be adjusted after multi-client tests.

### GD-022 — Skip voting

**Decision:** A wave can be skipped after a configured minimum delay when a
strict majority of active participants vote yes.

The server recalculates the threshold when active membership changes.

### GD-023 — Target modes

**Decision:** Standard target modes are:

- First.
- Last.
- Strongest.
- Weakest.
- Closest.

The server performs target selection using stable tie-breaking.

### GD-024 — Enemy paths and base damage

**Decision:**

- Maps use fixed, Studio-authored paths rather than dynamic PathfindingService
  routes.
- Enemies move from an ant nest/spawn toward the defender base.
- An enemy reaching the endpoint deals a configured fixed leak-damage value and
  is removed.

**Reason:** Fixed paths are predictable for strategy, efficient to simulate, and
easy for content authors to validate.

## Platform and interface

### GD-025 — Supported platform targets

**Decision:** The core project targets:

- Desktop mouse and keyboard.
- Mobile phone touch.
- Tablet touch.
- Gamepad/controller and console-style navigation.

VR is deferred and must not be advertised until it receives its own interaction,
comfort, UI, and performance review.

### GD-026 — Accessibility

**Decision:** Accessibility is part of core acceptance, including:

- Safe-area layouts.
- Preferred text-size support.
- Preferred transparency support.
- Reduced-motion support.
- Visual alternatives for important sound cues.
- Non-color-only status indicators.
- Navigable gamepad focus.
- Low-effects options.

### GD-027 — Inventory and placement usability

**Decision:**

- Inventory provides search, sort, filters, details, favorite, and lock.
- Placement uses a translucent local preview and ground range indicator.
- Valid and invalid states use shape/icon feedback in addition to color.
- Touch placement requires position followed by explicit confirmation.
- The server revalidates every final placement.

## Authority, content, and diagnostics

### GD-028 — Server authority

**Decision:** The server exclusively determines:

- Profile and inventory mutations.
- Gold and Battle Cash.
- Gacha outcomes.
- Queue captain permissions.
- Match tickets and roster admission.
- Ready and skip membership.
- Tower placement, upgrades, sales, targeting, and cooldowns.
- Enemy progress, health, damage, death, and leaks.
- Wave completion.
- Base health.
- Victory, defeat, and rewards.

Clients provide input intent and render responsive presentation.

### GD-029 — Data-driven content

**Decision:** Ordinary maps, towers, enemies, waves, difficulties, and banners
are created through validated definitions plus Studio-authored assets.

Core services must not branch on specific content names when a reusable behavior
or configuration field can express the requirement.

### GD-030 — Studio and Rojo ownership

**Decision:**

- `src/` remains authoritative for scripts.
- Roblox Studio and Team Create remain authoritative for maps, terrain, models,
  animations, and unmapped instances.
- Lasting edits to Rojo-managed scripts are never made in Studio.
- Roblox Script Sync is never used on Rojo-managed folders.

### GD-031 — Development diagnostics

**Decision:** The project uses extensive structured development logging.

Development/Studio logs should cover:

- Client and server bootstrap.
- Service initialization, start, and shutdown.
- Configuration validation.
- Profile load, migration, save, release, and failure state.
- Queue membership, captain changes, lock, and recovery.
- Party changes, ticket creation/claim, and teleport attempts/failures.
- Match-state transitions.
- Ready and skip-vote changes.
- Wave start, spawn completion, early clear, deadline overlap, boss, and result.
- Tower placement, upgrade, sell, target-mode changes, and rejected requests.
- Reward calculation, claim, duplicate prevention, and return.
- Rate-limit and security rejections through aggregate or sampled messages.

Log records should include severity, execution context, subsystem, and relevant
safe correlation identifiers.

The project does not log every frame, every enemy movement step, or every visual
projectile by default. High-frequency tracing must be opt-in, sampled, or scoped
to a specific entity so useful evidence is not buried and performance is not
damaged.

Production logging is quieter and rate-limited. Logs never include:

- Complete profiles.
- Secrets or credentials.
- Reserved-server access codes.
- Purchase secrets.
- Unnecessary personal information.

**Reason:** Rich development diagnostics help identify failures early, while
structured levels and high-frequency limits keep output usable.

## Content and onboarding implementation addendum — 2026-09-04

This addendum locks the product choices implemented for historical Phases
29–33. The outcome passed its consolidated review, current headless/build gate,
and bounded solo/mobile/four-client private-staging Studio acceptance on
2026-09-04.

### GD-032 — Content identity, selection, and compatibility

**Decision:** Release content is additive and uses stable versioned identifiers:

- `map:backyard-garden-v1`;
- `difficulty:easy-v1`, `difficulty:normal-v1`, `difficulty:hard-v1`, and
  `difficulty:endless-v1`;
- `tower:bombardier-ant`;
- `enemy:broodling-ant` and `enemy:royal-guard-ant`;
- `banner:garden-v1` version 1; and
- content version 1 with generator key `wave-generator.garden-v1`.

An authenticated travel ticket is the authority for the travelled Match map
and difficulty. Lobby configuration accepts only validated, non-hidden,
non-development map/difficulty pairs and presents their display names to
players. Direct local development instead uses the explicit server-owned
`map:phase07-graybox` plus `difficulty:local` fallback, which remains hidden and
non-rewarding.

The legacy graybox/local IDs, three original tower IDs, four original enemy IDs,
`banner:starter` version 1, `queue:backyard-squad`, saved unit/pity/first-clear
keys, old tickets, and result version 1 retain their existing meanings. New
result fields use compatible record version 2 rather than changing version 1.

### GD-033 — First release map and strategic rosters

**Decision:** Backyard Garden is the first release map. Its bright ant-scale
vegetable-garden composition uses Studio-built primitives and Roblox materials:
warm soil and stone communicate the fixed enemy lane, cool grass and bounded
build pockets communicate placement, and a nest and seed store communicate
spawn and goal. The unchanged map contract supplies one ordered `main` lane,
four player spawns, overview framing, placement/exclusion regions, and stable
queue/travel compatibility. Reduced effects may remove optional motion or
bursts, never gameplay silhouettes, navigation, or warnings.

The playable tower roster has four configuration-driven jobs and complete
three-level upgrades: Dart Ant is balanced, Rapid Ant covers fast/numerous
targets, Guard Ant focuses durable enemies and bosses, and Bombardier Ant adds
generic area damage. All support First, Last, Strongest, Weakest, and Closest
targeting; services do not branch on a tower ID or display name.

The six-enemy roster teaches basic (Worker), fast (Scout), durable/elite
(Soldier), swarm (Broodling), miniboss (Royal Guard), and boss (Garden Queen)
pressure. Threat class and presentation are configuration-driven. Armor,
stealth, flying, support aura, economy towers, and status mechanics remain out
of scope until play evidence demonstrates a need.

### GD-034 — Authored campaigns and acquisition

**Decision:** Backyard Garden has exactly 20 Easy, 30 Normal, and 40 Hard waves,
with boss waves at every tenth wave and readable miniboss teaching pressure
between them. Easy introduces roles separately with the most base health,
starting Battle Cash, recovery, and income. Normal combines roles sooner and
tightens resources. Hard begins with mixed pressure, layers fast/swarm enemies
behind durable screens, shortens recovery, and uses the leanest economy. Health
and speed modifiers reinforce rather than define those distinctions.

A new profile receives Dart Ant and Bombardier Ant once and starts with that
valid loadout, so neither onboarding nor Easy depends on a random outcome. Every
tower is also available from the earn-only Garden Tower Chest for 250 Gold per
pull or 2,250 for ten: 40% Dart, 30% Rapid, 20% Bombardier, and 10% Guard, with
hard pity at ten for Guard. Exact odds, earn-only policy, pity, and unique-unit
duplicate handling are disclosed together. `CONTENT_BALANCE.md` is the source
for the accepted combat, economy, and persistent-reward values.

### GD-035 — Endless is an unbounded mode of the existing Match

**Decision:** Endless reuses the authoritative playable runtime. Ten authored
opening waves are followed by lazy stateless generation from content version,
seed, wave number, and draw index. Boss cadence remains every ten waves.
Generation and runtime cap groups, spawns, active enemies, simultaneous wave
origins, simulation work, health, speed, Battle Cash, counters, and replicated
collections; no accumulated infinite schedule exists.

Endless never reports Victory or a fake last wave. Base defeat, deliberate
departure, all participants leaving, shutdown, or technical termination creates
one version-2 authoritative result with highest completed wave, elapsed time,
map, difficulty, seed, content version, and termination reason. The terminal
Gold award is bounded, receipt-idempotent, and based on each participant's
completed participation rather than connected time. No global leaderboard is
introduced.

### GD-036 — Persistent server-observed onboarding

**Decision:** Profile schema v6 owns a resumable tutorial state machine. Its
steps initialize the deterministic starter inventory/loadout, explain Gold,
Battle Cash, and disclosed chest odds, validate the loadout, observe a singleton
PartyOnly Easy Garden queue, authenticate Match arrival, observe an accepted
placement and upgrade, observe the durable terminal result, and confirm the
matching return to Lobby before completion.

The persisted numeric graph is:

0. initialize starter inventory and a safe loadout;
1. explain persistent Gold, match-only Battle Cash, and chest odds;
2. validate the starter loadout;
3. observe entry into the singleton PartyOnly Easy Garden queue;
4. observe authenticated arrival in its Match;
5. observe an accepted tower placement;
6. observe an accepted upgrade of an owned tower;
7. observe the tracked Match's durable terminal result;
8. observe its matching return to Lobby; and
9. complete.

Clients may request Continue, Skip, or Replay, but cannot declare gameplay
steps complete. Rejected, out-of-order, public, squad, spectator, or
foreign-match activity cannot advance the state. Skip is available only after
safe initialization; replay increments a bounded attempt without duplicating
starter units. Any tutorial timing or assistance is derived only for the
authenticated singleton onboarding ticket and cannot affect public or squad
matches. Lobby and Match show short contextual guidance rather than a modal
course.

### Content and staging boundary

The private staging identity was verified as GameId `10764687717`, Lobby PlaceId
`140661668701496`, Match PlaceId `104415140644510`, owner `PHJGAMES` group
`35420107` before bounded Team Create authoring. Only the authorized Match map
and playable-template roots changed; the Lobby needed no tutorial world marker.
Final inventory found two map templates/237 descendants (Garden: 212) and ten
playable templates/83 descendants, with zero scripts or runtime residue. A
local iPhone 17 Pro landscape session verified touch placement, selection,
upgrade, camera bounds, and defeat. One four-client session verified common
Garden/Easy state, four independently owned placements, one upgrade, and
wave-12 boss overlap presentation. Reduced-effects behavior is covered by the
deterministic client projection/view gate: optional effects are suppressed
without removing boss warning/health communication.

No production place, production data, experience setting, purchased/uploaded
asset, or published place version was involved. A newly published
staging-client gate and an uninstructed first-time-player test were not run and
remain separate acceptance evidence if later required.

## Platform hardening implementation addendum — 2026-09-04

This addendum records the Phases 34–37 implementation contracts. The clean
starting point was `ddd01c9c0d459d91639c122c5ae784c1e59608c3`, with historical
`1,486/1,486` coverage. Repository implementation and local milestone verification
are complete. Consolidated review is clean; formatting/lint and all four builds
passed. The full milestone gate ran once. Its initial headless result was
`1,599/1,601`; a diagnostic headless rerun reproduced two stale ReadyController
English expectations. Four test-only expectations were corrected, formatted and
linted; the affected ReadyController/View/ViewModel suites passed `30/30`, giving
cumulative `1,601/1,601` coverage without production-source changes or another
full gate. Delivery branch: `codex/platform-hardening`. Neither check establishes external
platform, published-client or analytics acceptance.

### GD-037 — Evidence-based platform and language support

**Decision:** Candidate inputs are desktop mouse/keyboard, keyboard-only,
landscape phone touch, tablet touch and controller/TenFoot. Advertise a target
only after its first-session and full-match criteria have evidence at the
appropriate level. Studio emulation, local desktop hardware, physical devices,
published clients and external services are different evidence classes. A
desktop controller does not establish console support; genuine console hardware
acceptance is required only if console is later advertised. VR remains deferred;
experience platform availability is unchanged.

Current Studio-emulated Lobby geometry covers minimum landscape, common phone,
tablet, desktop, ultrawide and TenFoot at Largest text, transparency 0, reduced
motion, pseudo50 and saved UI scale 0.75. The
[final Lobby sample](evidence/platform-lobby-final-ui.json) retains three header
label failures; the separate
[header follow-up](evidence/platform-lobby-header-followup.json) closes them.
Observed controls have no remaining text-overflow, undersized-touch,
fixed-clipping or overlay candidates. Scrollable off-viewport controls still
require input verification; these samples are not a full-session or full-match
acceptance matrix. Recorded keyboard checks include stable setting focus and
Backspace returning to Home. Escape opens Roblox's Core menu.

Local controller Ready and placement were observed. A native stick trace recorded
600 frames and 20 axis events with peak magnitude 1, but zero frames reading a
nonzero polled axis; brief injected taps do not verify sustained analog control.
That hardware/input gate and complete controller upgrade/target/sell acceptance
remain pending. No physical phone/tablet, genuine console, published full-loop,
screen-reader or assistive-device acceptance is inferred from these observations.

English messages use stable keys and bounded named arguments, consistent number,
currency, odds, timer and wave formatting, and explicit proper-name treatment.
Automated 30–50% pseudolocalization is an expansion test, not a translation.
Advertising an additional language requires human translation and review.
English remains the source-language scope. Roblox text
size/transparency preferences apply consistently with bounded saved settings;
effective reduced motion is Roblox OR saved preference. Critical controls reflow
or scroll rather than becoming unreadably small. Exact precedence, layout/focus
criteria and remaining acceptance gates are in the
[design lock](PLATFORM_HARDENING_DESIGN_LOCK.md).

### GD-038 — Presentation cannot decide gameplay

**Decision:** Validated snapshots and events drive generic client feedback and
smooth tower aiming. They never decide attacks, damage, targeting, income,
rewards or results. Persistent health, ranges, ownership, navigation and warnings
remain visible when optional effects, motion or sound are disabled. Master,
music, SFX and UI audio routing is bounded and fails silently for unavailable
assets. All 18 manifest entries remain unavailable: five music scenes and 13
feedback cues. Approved owned audio is still required for listening and mix
acceptance; procedural tower aiming needs no uploaded animation. Any future
authored media needs provenance and permission approval. No invented asset IDs,
uploads or purchases are authorized. See
[presentation architecture and provenance](PRESENTATION.md).

### GD-039 — Measure before optimizing

**Decision:** Use recorded local frame, CPU, process-memory, instance and network
observations to set matching-environment regression thresholds. JSON-like payload
estimates, server Heartbeat cadence, deterministic cleanup and generated Endless
descriptions cannot substitute for wire traffic, simulation CPU, engine memory
or real-time device soaks. The initial traces do not justify changing authority,
spatial indexing, replication protocols or pooling. Physical-device and published
budgets remain pending. [Performance budgets](PERFORMANCE_BUDGETS.md) records
hardware, scenarios, limitations and thresholds.

### GD-040 — Private bounded observability and isolated development tools

**Decision:** A versioned event dictionary observes successful server outcomes
with bounded allowlisted dimensions and ephemeral correlation. Delivery cannot
block gameplay or create persistence/reward authority. Raw identities, profiles,
inventories, chat, secrets, receipts and teleport data never enter analytics.
External delivery is disabled; mock sinks do not complete dashboard acceptance.
Operational warnings are structured, rate-limited and owned by one layer.
Packet 37.6 remains pending a reviewed destination and explicit authorization
for designated accounts, event subset, retention boundary and expected writes.
A new private publication and independent newcomer/full-loop test remain separate
acceptance gates; historical published-client checks belong to their earlier
outcome and do not validate the current source.

Development commands exist only under the isolated test root, with exact staging
identity and server/environment authorization on every invocation. Their finite
test Battle Cash and scenario adapters cannot mutate persistent Gold, profiles,
inventory, stores, receipts or production. The read-only report command
`lune run tests/balance-report.luau` reuses production configuration and the
existing simulator/runtime; it does not change balance or live state. Contracts
are in [analytics and commands](ANALYTICS.md) and
[content balance](CONTENT_BALANCE.md). Phase 38 remains outside this outcome.

## Core scope boundary

### Included before the closed-alpha gate

- Graybox and production match loops.
- Profile persistence and migrations.
- Settings, inventory, loadout, and earn-only gacha.
- Same-server parties and Public/PartyOnly queue squares for squads of one to four.
- Reserved match servers and safe teleports.
- Persistent match rewards.
- One production map.
- First tower and enemy rosters.
- Easy, Normal, Hard, and Endless.
- Tutorial/onboarding.
- Desktop, mobile/tablet, and gamepad support.
- Accessibility, performance, analytics, security, QA, and operations.

### Explicitly deferred

- Duplicate merging/ascension implementation.
- Cross-server public matchmaking.
- Paid Gold or other Robux-backed gacha currency.
- Trading.
- PvP.
- Clans.
- Battle passes.
- Ranked modes.
- Global Endless leaderboards.
- Multiple upgrade branches.
- Consumable revives and match items.
- VR support.

Deferred items must not be implemented opportunistically during a core packet.

## Decisions intentionally left for later packets

The following list is preserved as the historical Core-001 state at Packet
00.2. Its map, roster, wave, and balance questions are now resolved by the
2026-09-04 addendum above; the remaining future decisions stay deferred.

- Any additional test-place identifiers or environments beyond the verified
  Lobby and Match places require a later explicit test-strategy decision.
- Tool versions and test framework: Phases 01 and 05.
- First map theme and art direction: Phase 29.
- First tower roster names/stats: Phase 30.
- First enemy roster and exact authored waves: Phase 31.
- Final reward, pity, Gold income, and Battle Cash numbers: content/balance phases.
- Whether any post-core monetization should exist at all: Phase 44.

## Change control

These decisions can be changed, but architecture-affecting changes must:

1. Be explicitly requested or justified by test evidence.
2. Update this register and the roadmap.
3. Identify affected saved data, UI, security, content, tests, and migrations.
4. Be made before dependent implementation where possible.

Balance values marked provisional may be tuned without replacing the underlying
decision unless the tuning changes the system's meaning.
