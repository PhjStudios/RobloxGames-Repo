# Ant Tower Defense — Game Design Decision Register

## Purpose

This document records the product and architecture-affecting decisions approved
for the core Ant Tower Defense project. It is the evidence for Packet 00.2 of
`docs/DEVELOPMENT_PLAN.md`.

The decisions below use the roadmap's recommended defaults. They guide future
implementation but do not authorize gameplay coding, Roblox publishing,
production-data changes, or monetization.

## Decision status

- Decision set: Core-001
- Recorded: 2026-08-25
- Packet: 00.2
- Status: Accepted for core development
- Next roadmap packet: 04.1, Shared ID and result types

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
`docs/PLACE_INVENTORY.md`; the exact Match PlaceId remains pending approved
Studio creation.

## Players, squads, and matchmaking

### GD-003 — Match size

**Decision:** A match supports one to four active players.

**Reason:** Four players supports solo and cooperative strategy while keeping
placement density, UI, rewards, and server simulation manageable.

**Revisit trigger:** Only revisit after real playtests demonstrate that four
players is too restrictive or harms map balance.

### GD-004 — Queue privacy

**Decision:** Core queue modes are:

- Solo.
- Friends.
- Public.

Public queues in the initial core release form from players in the same lobby
server. Cross-server public matchmaking is deferred to Phase 43.

**Reason:** This provides public-stranger play without making the initial
lobby-to-match implementation depend on global matchmaking infrastructure.

### GD-005 — Captain authority

**Decision:** The first valid player entering a queue square becomes captain.
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
A party is not automatically treated as a committed match squad until its
members join or accept the queue flow according to the later Party/Queue design.

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

**Status:** Wave counts are accepted defaults; final balance/content remains
provisional until content and testing phases.

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

## Core scope boundary

### Included before the closed-alpha gate

- Graybox and production match loops.
- Profile persistence and migrations.
- Settings, inventory, loadout, and earn-only gacha.
- Same-server parties and Solo/Friends/Public queue squares.
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

The following do not block Packet 00.2:

- The Match PlaceId and test-place identifiers will be recorded when the Studio
  setup described by the completed Packet 00.3 inventory is approved and done.
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
