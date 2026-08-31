# Phase 06 and Gate A Exit Audit

> **Historical evidence:** This completed exit record is retained for reference.
> See `../ROADMAP.md` and `../AGENTS.md` for the current roadmap and workflow.

## Purpose and current status

This document records the fresh combined-state audit for Phase 06 — Network
Protocol and Remote-Security Foundation. It audits Packets 06.1 through 06.5
together after the packet reviews and current-source Studio regression. It does
not approve a gameplay endpoint or begin Phase 07.

- **Audit date:** 2026-08-26
- **Branch:** `codex/phase-06-network-security`
- **Verified Phase 05 baseline:**
  `bb122fbbfca92ddaada7e6ba1263853c5cabc134`
- **Last pushed Packet 06.5 commit:**
  `6c690fee71761165f24f7bd279bd0b3310ea2509`
- **Audit-content implementation/evidence commit:**
  `7ada807586164c8ab0c940c749393c243d4fe9e3`
- **Packets 06.1–06.5:** complete
- **Fresh local combined-state audit:** passed
- **Fresh independent source, protocol-security, and test-quality reviews:**
  passed; no P0, P1, P2, or P3 finding remains
- **Fresh independent documentation review:** passed; no P0, P1, P2, or P3
  finding remains
- **Audit-content GitHub run:** passed; run `33022784985`, job `98356927817`,
  zero retained artifacts
- **Phase 06 / Gate A status:** complete / passed — 2026-08-26
- **Phase 07 status:** next; not begun

The exact combined implementation and audit content passed the genuine GitHub
workflow. This ordinary completion record cites that run and marks Phase 06 and
Gate A complete. The completion-record commit's own workflow is verified
separately after push; its run does not need to be cited by itself.

## Baseline, branch, and packet history

Preflight proved local `HEAD`, its upstream, and the remote Phase 05 branch at
the exact authorized baseline
`bb122fbbfca92ddaada7e6ba1263853c5cabc134`. The worktree was clean except the
pre-existing ignored `sourcemap.json`. Production `src/` matched the recorded
Phase 04 source state, Phase 06 had not begun, and the new branch was created
from that exact commit without unrelated history.

The ordinary Phase 06 packet history is:

| Packet | Architecture record | Implementation/evidence commit |
| --- | --- | --- |
| 06.1 — fixed remote registry | `4efd43d` | `8eaf284` |
| 06.2 — strict payload validation | `dc94a28` | `db413f6` |
| 06.3 — server token buckets | `02d867c` | `cf7f2b9` |
| 06.4 — correlation and public errors | `d34d9a7`, clarification `098c6a8` | `bf38139` |
| 06.5 — adversarial security evidence | `862f6fa` | `6c690fe` |

Each architecture record preceded its packet's implementation. No force-push,
merge, pull request, history rewrite, branch/tag deletion, repository-setting or
secret change, deployment, Roblox save/publication, or external Roblox service
was used.

## Architecture and security boundary

The audited production design has one fixed, typed, authenticated registry.
The server alone creates its exact `ReplicatedStorage.ATDNetwork/v1` tree
parent-last and owns it through the established lifecycle and Cleanup contracts.
Clients can resolve only authenticated, active, registry-defined leaves through
one decreasing total deadline; they cannot create an Instance or select a
service, handler, action, instance path, or arbitrary remote path.

All transports are asynchronous `RemoteEvent`s. The production source contains
no `RemoteFunction`, synchronous invoke path, `FireAllClients`, unrestricted
generic bus, or client-selected dispatch. The lasting production endpoint
registry and rate-policy list are intentionally empty.

For a client-to-server request, the exact protected order is:

1. authenticate the fixed bound endpoint and reject a malformed envelope;
2. apply the server-owned per-Player/per-endpoint rate policy;
3. classify request correlation as new, duplicate, stale, or invalid;
4. derive server context and run the context-only authorizer;
5. validate and detach the payload through the endpoint's authenticated schema;
6. run one synchronous protected handler with the canonical payload; and
7. translate only to an allowlisted bounded public response and route it only
   to the originating Player.

Request IDs provide correlation only, never authorization or idempotency.
Unexpected handler failures become a fixed internal public rejection without a
raw error, traceback, payload, private value, catalog, or server state. Rejected
pre-handler requests cannot reach a mutation callback. Event dispatch uses the
same fixed endpoint, rate, authorization, validation, synchronous-handler, and
translation boundaries without fabricating a response.

The mandatory per-endpoint shipping gate is
`docs/REMOTE_SECURITY_CHECKLIST.md`. No test fixture is an approved endpoint;
every future production definition must complete its exact direction-specific
record before registration.

## Tool installation and version audit

`rokit install` completed successfully with the tracked manifest. No tool,
manifest, action, dependency, or lockfile was changed for Phase 06.

| Tool | Required pin | Fresh reported version | Result |
| --- | --- | --- | --- |
| Rokit | bootstrap `1.2.0` | `rokit 1.2.0` | Pass |
| Rojo | `rojo-rbx/rojo@7.7.0` | `Rojo 7.7.0` | Pass |
| StyLua | `JohnnyMorganz/StyLua@2.5.2` | `stylua 2.5.2` | Pass |
| Selene | `Kampfkarren/selene@0.31.0` | `selene 0.31.0` | Pass |
| Lune | `lune-org/lune@0.10.5` | `lune 0.10.5` | Pass |

No third-party runtime or test package was needed. Official Roblox engine and
security references supporting the architecture are recorded in
`docs/NETWORK_PROTOCOL.md`.

## Formatting and lint audit

The final local combined state passed:

| Command | Result |
| --- | --- |
| `stylua src tests` | Exit 0; no remaining rewrite |
| `stylua --check --verify src tests` | Exit 0 |
| `selene validate-config` | Exit 0 |
| `selene src tests` | Exit 0; 0 errors, 0 warnings, 0 parse errors |
| `git diff --check` | Exit 0 |

No suppression, warning downgrade, generated source, or test exclusion was
introduced.

## Three-run determinism audit

Three consecutive fresh invocations of `lune run tests/run.luau` ran from the
exact final local tree in one sequential audit process. Every run returned exit
0, discovered the same 16 suites and 200 cases in canonical path and declaration
order, and ended with:

```text
[ATD_TEST][SUMMARY][failed=0][passed=200][status=PASS][suites=16][tests=200]
```

Each captured stdout stream was 40,375 UTF-8 bytes with SHA-256
`cdca55905ec1c9c6dca262ae120aaf35546bdb355ef2fbe61947eda7da370f7c`.
All three stdout strings were byte-identical and all three stderr streams were
empty. The canonical order and case counts were:

1. Cleanup — 14
2. Client request tracker — 12
3. Configuration public contract edges — 16
4. Configuration schema failures — 17
5. Lasting and loaded configuration — 6
6. Configuration privacy and malformed boundaries — 5
7. Configuration schemas valid fixtures — 4
8. Core ID, Result, and Validation contracts — 12
9. Integrated network security — 9
10. Strict payload validation — 22
11. Remote registry — 18
12. Fixed remote runtime and client lookup — 12
13. Request protocol — 13
14. Server rate limiter — 17
15. Server request dispatcher — 21
16. Runner smoke — 2

## Adversarial and privacy controls

The focused and integrated suites cover malformed/oversized envelopes; exact-key
records; depth, node, field, item, branch, and string limits; sparse and cyclic
tables; hostile metatables and keys; NaN and both infinities; non-finite Roblox
datatypes; default Instance rejection and explicit server class/ancestry policy;
duplicate, stale, cross-endpoint, cross-family, malformed, and oversized IDs;
unknown endpoints; wrong direction and semantic kind; arbitrary paths; forged
identity, team, permission, and ownership fields; bursts and refill boundaries;
authorization removal; contained Request/Event handler failures; zero partial
mutation; disconnect cleanup; and lifecycle re-entry.

Rate and protocol observability retains only frozen allowlisted aggregate
fields with bounded cardinality and interval cadence. Tests prove report failure
is isolated, payloads and Player identity are not retained, validation paths are
privacy-safe, and attacker-controlled values do not enter public responses or
logs.

The six permanent isolated runner controls were also reproduced on the final
tree. Each returned its documented nonzero class and stable code, removed its
exact generated place, and emitted none of the private assertion/module-load or
network sentinels:

| Control | Expected/actual exit | Stable code | Result |
| --- | ---: | --- | --- |
| `assertion` | `1` / `1` | `ASSERT_EQUAL_FAILED` | Pass |
| `zero` | `2` / `2` | `ZERO_TESTS` | Pass |
| `module-load` | `2` / `2` | `MODULE_EXECUTION_FAILED` | Pass |
| `malformed` | `2` / `2` | `MISNAMED_SPEC` | Pass |
| `malformed-root` | `2` / `2` | `ROOT_WRONG_CLASS` | Pass |
| `runner-crash` | `3` / `3` | `RUNNER_CRASH` | Pass |

Phase 05's genuine intentional failing commits were not recreated.

## Four-project shipping and source-integrity audit

`lune run tests/verify-builds.luau` rebuilt and inspected every project, then
removed its exact four generated outputs:

| Build | Fresh structural marker | Result |
| --- | --- | --- |
| Default | `MODULES_40_SCRIPTS_1_LOCALSCRIPTS_1` | Pass |
| Lobby | `MODULES_40_SCRIPTS_1_LOCALSCRIPTS_1` | Pass |
| Match | `MODULES_40_SCRIPTS_1_LOCALSCRIPTS_1` | Pass |
| Test | `MODULES_65_SHARED_33_NETWORKING_6_TEST_OWNED_26_RUNNABLE_SCRIPTS_0` | Pass |

The verifier matches every production Lua container to an exact DataModel
path, class, authoritative file, and byte-for-byte source. It separately
allowlists all 26 Test-owned ModuleScripts by exact path, class, authoritative
file, and source content, and authenticates the six copied networking modules.
It proves:

- tests, fixtures, controls, support modules, Studio harnesses, and test-only
  dependencies are absent from Default, Lobby, and Match;
- the Test project has no runnable Script or LocalScript;
- Lobby contains no Match source and Match contains no Lobby source;
- each production build has exactly one common server and one common client
  bootstrap;
- each production tree retains all 33 shared modules, the exact role-safe common
  networking ownership modules, and no unapproved source; and
- exact generated outputs are removed on success and protected failure.

Canonical configuration cases additionally prove every lasting gameplay
catalog remains empty and settings/economy remain policy-only. The only lasting
network policy collections are the empty frozen production registry and empty
frozen rate-policy list. No gameplay, map, UI, persistence, teleport, economy,
reward, purchase, gacha, enemy, wave, tower, matchmaking, or Phase 07 source was
added.

## Unsaved Roblox Studio regression

Roblox Studio `0.735.0.7351131` from installation directory
`version-dcbeee682ce74ee0` ran only authorized unsaved local tests. Lobby was
paired only with `lobby.project.json` and Match only with `match.project.json`,
one project at a time. Three plain Lobby and three plain Match Play/Stop cycles
passed with one empty production registry root, zero endpoints, server service
count one, client service count zero, and clean `Shutdown`/`Cleaned` teardown.

The fresh Match `Server & Clients` regression used exactly two clients and the
current tracked runtime-only harness sources:

- server SHA-256:
  `883bcdb665f54cb5adff9f935af90992cc5b71e5a486f7293a6f5a2f27bdec6a`;
- client SHA-256:
  `8223e9e95dfb4caee94986da9f722917b68ec23ee5e7c7e1992d2173fc1ea290`.

The accepted run produced:

```text
[ATD_PHASE06_STUDIO][PASS][context=client][case=completed][caseCount=10]
[ATD_PHASE06_STUDIO][PASS][context=server][caseCount=10][clientCount=2][cleanupState=Cleaned]
[ATD_PHASE06_STUDIO][INSPECT][context=server][rootCount=1][rootClass=Folder][versionClass=Folder][endpointCount=0][fixtureCount=0]
[ATD_PHASE06_STUDIO][LOG_AUDIT][context=server][forbiddenMatches=0][errorCount=0]
[ATD_PHASE06_STUDIO][LOG_AUDIT][context=client][forbiddenMatches=0][errorCount=0]
```

It proved real asynchronous delivery, engine-supplied originating Player,
origin-only responses, live datatype rejection, explicit server Instance
policy, forged-authority rejection, independent Player/endpoint burst limits,
bounded aggregates, real `LeaveTest()` and `PlayerRemoving`, exact departing-
Player limiter/correlation cleanup, continued remaining-peer service, fixture
destruction, and production-root preservation. Both original places were
returned to Edit mode. No Edit-mode instance, place, asset, external service,
save, or publication was changed. Exact timestamps and procedure are in
`docs/NETWORK_SECURITY_STUDIO_REGRESSION.md`.

## Workflow security and remote evidence

The least-privilege workflow remains verification-only. Its user-facing name is
now phase-neutral, `Repository Verification`; its triggers, top-level
`contents: read` permission, full-SHA checkout, non-persisted credentials,
digest-verified Rokit bootstrap, exact tool pins, required commands, residue
check, and zero-artifact policy are unchanged. It references no secret and has
no deployment, release, cache, artifact upload, Roblox save, or publication
authority.

Packet 06.5 commit `6c690fee71761165f24f7bd279bd0b3310ea2509`
already passed every required step in
[run 33014884391](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/33014884391)
([job 98330403303](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/33014884391/job/98330403303)).
That run proves the packet commit but does not close the fresh combined exit
gate by itself.

Audit-content commit `7ada807586164c8ab0c940c749393c243d4fe9e3`
subsequently passed
[run 33022784985](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/33022784985)
([job 98356927817](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/33022784985/job/98356927817)).
The public API confirmed a `push` event, exact matching head SHA, run attempt
one, successful `Repository Verification` conclusion, and one successful
`Windows verification` job on requested label `windows-2025` (runner
`GitHub Actions 1000000023`). Setup, checkout, pinned Rokit installation and
version checks, formatting, Selene configuration, lint, deterministic tests,
all-project structural verification, and generated-output residue checks each
reported success. The artifact API returned `total_count = 0`. The
unauthenticated job-log archive endpoint returned HTTP 403, so this audit does
not infer an image version from the numeric API runner name.

## Link, privacy, residue, and scope audit

The complete 30-file README/Markdown set passed a generated relative-link and
GitHub-style heading-anchor audit: all 57 local targets/anchors resolved. The
first read-only external pass checked 96 unique URLs and found five legacy
Roblox API-reference routes returning HTTP 502. Those five were corrected to
Roblox's official `.md` API-reference form. A fresh complete pass then checked
all 95 unique current external URLs with zero HTTP failure.

A high-confidence credential scan found zero GitHub token, Roblox security
cookie, AWS key, private-key, Slack-token, or similar secret pattern. The
sensitive-filename scan found zero `.env`, credential, secret, private-key, or
certificate file. No place build, log, temporary/backup file, package/install
output, or dependency-manifest change exists. Exact generated verifier outputs
were removed. The only ignored residue remains the pre-existing
`sourcemap.json`.

The production-service/transport scan found no DataStore, MemoryStore,
TeleportService, MarketplaceService, MessagingService, `RemoteFunction`, invoke
API, or `FireAllClients`. The only two production `HttpService` references are
the fixed client request tracker's local `GenerateGUID(false)` generator; they
perform no HTTP request. Production role folders contain zero source file, all
12 Phase 06 `src/` changes are foundation-only paths, and a client-selected
action/service/handler/path scan found zero dispatch surface.

Current/next wording marks Phases 00–06 complete and Gate A passed only after the
audit-content run above, identifies Phase 07 as next, and states that Phase 07
has not begun. Deferred gameplay, published-client, device, persistence,
purchase, and destructive tests remain deferred, unavailable, or prohibited in
`docs/TEST_MATRIX.md`; none is promoted by this gate.

## Independent review status

Fresh independent read-only reviews cover production source, protocol security,
test quality including the exact current Studio hashes/evidence, and the final
documentation set. Source and protocol-security review found no P0, P1, P2, or
P3 issue. Test-quality review found no P0, P1, P2, or P3 issue after exact
Test-owned build allowlisting, failure-safe runtime-fixture cleanup,
non-yielding Studio callbacks, computed case counts, coordinator containment,
and bounded aggregate validation were added. Documentation review independently
rechecked all current status/next wording, historical evidence boundaries,
future-test classifications, checklist authority, and live Markdown targets;
it found no P0, P1, P2, or P3 issue.

## Exit-gate result

**Passed — 2026-08-26.** Every Phase 06 technical, adversarial, determinism,
build-shipping, privacy, cleanup, Studio, independent-review, and documentation
gate is green. The exact audit-content commit passed the genuine clean workflow
in run `33022784985` with zero retained artifacts, and this ordinary completion
record cites it.

Phases 00–06 are complete and Gate A passed. Phase 07 is next and has not begun.
No gameplay endpoint, Phase 07 source, or broader authority is introduced by
this result.
