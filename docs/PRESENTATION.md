# Client presentation contract

Historical Phases 34–37 implementation; hardware, listening and published-client
acceptance are separate gates in `PLATFORM_HARDENING_DESIGN_LOCK.md`.

## Ownership and feedback

Accepted Match snapshots, successful action receipts and validated attack events
feed `FeedbackDirector`. `FeedbackState` reduces those observations to scene and
cue names. It has no server callback, remote, reward or persistence access.
Snapshots recover lasting scenes. Revision, attack sequence and bounded retired
match history suppress duplicate/old feedback; missing optional cues are harmless.
Other-player attack effects and sound obey the saved other-player-effects setting.
Lobby selection cues and successful chest receipts use the same audio owner.

| Priority | Examples | Persistent visual equivalent |
| --- | --- | --- |
| Critical interface | Navigation, placement legality, ownership, targeting, range | Existing controls, labels and world indicators |
| Warning/result | Boss, leak/base damage, victory, defeat, reward | Boss health panel, numeric base health, result panel, reward summary |
| Transaction | Placement, upgrade, sell, selection | Tower/loadout state, cash, selected tower controls and receipt feedback |
| Disposable decoration | Attack, impact, kill | Authoritative enemy health and resulting world state |

The cue registry does not branch on content IDs or display names. Tower aim uses
only positions from already validated attack events, smooths toward the last
observed shot, and returns to placement yaw after 0.65 seconds without another
shot. New snapshots retain this visual angle. Removed/replaced towers retire the
angle state; absent targets do not stall attacks. Authored model variants use the
existing template and bounded muzzle-marker contract.

## Audio and provenance

Each production client owns one `SoundService._ATDAudio` folder with a Master
SoundGroup and nested Music, SFX and UI groups. An existing conflicting root is
preserved. Master starts at zero until saved settings arrive, then master and
category settings apply immediately as independent multipliers. Roblox documents
the parent/child mixing behavior in [Sound groups](https://create.roblox.com/docs/sound/groups).

Scene transitions stop the preceding track before requesting Lobby, Match, Boss,
Victory or Defeat music. This intentionally uses a single music voice and a silent
fallback while loading. Gameplay never waits for loading. Unknown keys are
rejected. Unapproved assets allocate no Sound; creation/load/play failures disable
that manifest key for the session. Loading polls on the existing client frame
connection with a four-second timeout and one pending load per cue key. A transient
cue that loads after its useful duration is discarded; a later cue can use the
cached asset. There are no retry tasks or audio error
logs. Cleanup stops/destroys all owned sounds/groups exactly once.

`AudioManifest` has 18 deliberately unavailable entries: five music scenes and 13
cues (Placement, Attack, Impact, Kill, Upgrade, Sell, Leak, BaseDamage, Boss,
Victory, Defeat, Reward, Selection). No licensed audio was present in the bounded
staging inventory. Each future entry requires an approved Roblox asset identifier,
owner, source, license and verified experience permission. No purchase, upload,
permission change, arbitrary asset identifier or imported model is included.
Listening, mix quality and authored-media acceptance remain pending approved assets.
Current tower aiming is procedural and requires no uploaded animation.

## Density, preferences and cleanup

These are deterministic admission safety limits, **not measured hardware budgets**:

| Item | Normal | Low detail | Reduced motion |
| --- | --- | --- | --- |
| Concurrent attack visuals | 32 | 8 | 0 |
| New attack visuals per frame | 4 | 1 | 0 |
| Decorative muzzle/impact parts | Enabled | Disabled | Disabled |
| Particle allocation | 0 | 0 | 0 |
| Tower aim animation | Enabled | Enabled | Disabled; saved yaw |

Optional attack visuals beyond 180 studs from the camera at both endpoints are
culled. Damage numbers stay inside the effect cap and obey their separate setting.
Live reduced motion removes existing attack flashes on the next presentation
frame. Health, boss/base/result/reward meaning, targeting, ranges, ownership and
navigation remain outside the optional effect admission filter.

Audio is limited to 12 total voices, one music voice and two UI voices, with
per-cue intervals. Higher-priority warning sounds may retire lower-priority effects
when full. Effects/sounds are client-owned; neither authoritative runtime entities
nor presentation instances are pooled. Profiling must demonstrate a benefit before
pooling, spatial indexing or replication changes are introduced.

Deterministic suites cover provenance/failure suppression, loading timeout,
concurrency and cadence, volume precedence, root ownership, cleanup, cue reduction,
duplicate/retired sessions, aiming/idle return, live motion reduction and dense
effect admission. They do not prove asset playback, frame time, real device
readability or engine/network soak acceptance.
