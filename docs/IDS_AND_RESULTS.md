# Shared ID and Result Contracts

## Purpose

This document records the implementation decisions and verification evidence for
Packet 04.1 of `docs/DEVELOPMENT_PLAN.md`. The packet establishes bounded,
serialization-safe identifier conventions and one generic expected-failure
contract before any content schema, runtime entity, network protocol, gameplay
service, or persistence system consumes them.

## Packet status

- Packet: 04.1
- Status: Complete
- Recorded: 2026-08-25
- ID implementation: `src/shared/util/Ids.luau`
- Result implementation: `src/shared/util/Result.luau`
- ID families: 10
- Source type mode: `--!strict`
- Configuration schemas or catalogs added: none
- Gameplay, networking, runtime entities, or persistence added: none
- General test runner or external dependency added by Packet 04.1: none; Phase
  05 later added the isolated Lune runner
- Studio-authored content changed: no
- External services enabled: no
- Place saved or published: no

## Identifier domains

The families encode domain and intended lifetime in the string prefix:

| Domain | ID families | Intended use |
| --- | --- | --- |
| Stable content | `tower`, `enemy`, `map`, `difficulty`, `wave`, `banner` | Authored definitions and cross-references |
| Persistent record | `unit` | A future player-owned unit record, distinct from its tower definition |
| Runtime coordination | `queue`, `match` | Future bounded lobby and match sessions |
| Transaction | `transaction` | Future idempotent-operation identity and replay protection |

`DifficultyId` is the one small addition beyond Packet 04.1's original list. It
is required for the typed difficulty and wave cross-references in Packet 04.3.
This packet does not define a difficulty schema or any difficulty behavior.

These categories are conventions and validation boundaries, not implemented
lifetime managers. Packet 04.1 does not create records, generate sessions,
reserve queues, enforce idempotency, or authorize any identifier.

## Canonical string grammar

Every identifier has this case-sensitive representation:

```text
<kind>:<body>
```

The body uses the regex-equivalent grammar:

```text
[a-z0-9]+(?:[._-][a-z0-9]+)*
```

Consequently:

- kind prefixes and bodies are lowercase ASCII;
- bodies contain letters, digits, and single `.`, `-`, or `_` separators;
- separators cannot lead, trail, or appear next to another separator;
- there is exactly one prefix delimiter and no normalization or case folding;
- the body is non-empty; and
- the complete prefixed ID is at most 50 bytes.

The maximum body length for a family is `50 - #kind - 1`. Since the accepted
alphabet is ASCII, byte length and character count are identical for a valid ID.
The complete-ID bound is checked before parsing, so an oversized unknown prefix
cannot cause an unbounded delimiter scan or substring allocation.

The 50-byte ceiling lets a standalone ID fit Roblox's documented 50-character
DataStore key-name limit. It does not promise that a later compound key such as
`profiles/<id>/items` fits; every compound storage key must be checked at its own
boundary. Packet 04.1 makes no DataStore request and does not enable API access.
See Roblox's
[`DataStore` limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits).

## Public family API

Each family exposes a structural string alias and explicit construction and
validation functions:

| Alias | Prefix | Body constructor | Complete-ID validator |
| --- | --- | --- | --- |
| `TowerId` | `tower:` | `makeTowerId` | `validateTowerId` |
| `EnemyId` | `enemy:` | `makeEnemyId` | `validateEnemyId` |
| `MapId` | `map:` | `makeMapId` | `validateMapId` |
| `DifficultyId` | `difficulty:` | `makeDifficultyId` | `validateDifficultyId` |
| `WaveId` | `wave:` | `makeWaveId` | `validateWaveId` |
| `BannerId` | `banner:` | `makeBannerId` | `validateBannerId` |
| `UnitId` | `unit:` | `makeUnitId` | `validateUnitId` |
| `QueueId` | `queue:` | `makeQueueId` | `validateQueueId` |
| `MatchId` | `match:` | `makeMatchId` | `validateMatchId` |
| `TransactionId` | `transaction:` | `makeTransactionId` | `validateTransactionId` |

`make*Id` accepts an unprefixed body and returns a canonical prefixed ID.
`validate*Id` accepts a complete ID. Neither API throws for an expected invalid
value; both return `Result.Result<Id, IdError>`.

The module exports `MAX_ID_LENGTH = 50` so future boundary code can share the
same complete-ID limit without duplicating a magic number. The module table is
frozen.

## Validation and error contract

`IdError` has exactly:

```luau
export type IdError = {
    code: ErrorCode,
    message: string,
    expectedKind: IdKind,
}
```

| Code | Meaning |
| --- | --- |
| `INVALID_TYPE` | The body or complete ID is not a string |
| `INVALID_LENGTH` | The body is empty, or the complete ID is empty or over 50 bytes |
| `INVALID_FORMAT` | The prefix or ASCII body grammar is malformed |
| `WRONG_KIND` | A well-formed ID belongs to another recognized family |

Validation order is deterministic. Type and full-input length are checked
before parsing. A recognized foreign family is checked for valid length and
grammar before it can return `WRONG_KIND`; for example, malformed `enemy` input
validated as a tower returns the underlying format or length failure instead of
pretending it is a valid enemy ID.

Errors contain static developer-authored messages. Rejected values are never
coerced with `tostring`, copied into a message, or logged. All non-string
Luau/Roblox values are rejected, including tables with `__tostring`, functions,
threads, Instances, enum items, vectors, CFrames, buffers, and event
connections. Each `IdError` and its failure envelope is frozen.

## Result contract

`Result.Result<T, E>` is the generic tagged union:

```luau
export type Success<T> = {
    ok: true,
    value: T,
}

export type Failure<E> = {
    ok: false,
    error: E,
}

export type Result<T, E> = Success<T> | Failure<E>
```

`Result.ok(value)` and `Result.err(errorValue)` allocate fresh envelopes. The
literal boolean discriminant supports ordinary `if result.ok then` branch
narrowing. A successful `nil` payload is distinguishable from failure because
the discriminant, not payload truthiness, determines the branch.

The module and every returned envelope are frozen. Freezing is intentionally
shallow: the caller retains ownership, identity, and mutability of a table used
as `value` or `error`. A Result does not make an arbitrary payload serializable,
private, validated, or safe to send across a trust boundary.

The existing place-role and shutdown result shapes were not migrated. They have
separate closed domain contracts, and changing them is unnecessary for this
packet.

## Trust and authority limitations

Luau aliases in `Ids.luau` are structurally `string`, not nominal brands. The
type checker can therefore assign a raw string or one ID alias to another. The
explicit family constructor or validator is the runtime trust boundary; callers
must not treat an unchecked cast as validation.

`make*Id` validates and formats syntax only. It does not provide:

- GUID generation, entropy, collision resistance, or global uniqueness;
- issuance, existence, freshness, ownership, or authorization;
- secrecy, authentication, signatures, or replay protection; or
- transaction idempotency merely because the family is `transaction`.

A syntactically valid ID is not proof that a server issued it or that referenced
content or a record exists. Future authoritative systems must generate IDs where
needed, validate them at trust boundaries, resolve them against the correct
catalog or store, and check the caller's permission and context. Arbitrary
Instances, object references, and Instance names are not persistent or network
identifiers.

No generic `AnyId`, untyped family router, uniqueness registry, cross-reference
resolver, configuration schema, remote validator, or logging field was added.
Those responsibilities belong to later roadmap packets.

## Focused Studio Edit-mode validation

The real Rojo-synchronized modules were cloned into a temporary ServerStorage
harness and required in both isolated Studio places. Each primary harness passed
1,323 counted assertions; a supplemental adversarial probe passed 10 more
assertions. The same cases passed in Lobby and Match.

The validation covered:

- every one of the 10 constructor/validator pairs, including `DifficultyId`;
- every same-family case and all 90 cross-family mismatches;
- one-byte bodies and an exact 50-byte complete ID for every prefix length;
- one byte over each family maximum, a 51-byte complete input, and a 100,005-byte
  unknown-prefix input rejected by the early full-input guard;
- UUID-shaped bodies and every allowed separator;
- empty body and complete ID, missing/empty/unknown/uppercase prefixes, extra
  colons, uppercase bodies, Unicode, whitespace, controls, NUL, path and bracket
  characters, and leading, trailing, repeated, or mixed adjacent separators;
- `nil`, booleans, ordinary and non-finite numbers, tables, a table with
  `__tostring`, functions, threads, Instances, enum items, vectors, CFrames,
  buffers, and an `RBXScriptConnection`;
- malformed foreign-family input producing its grammar failure before
  `WRONG_KIND`;
- a secret sentinel never appearing in a failure message;
- frozen modules, Result envelopes, and ID errors, including failed mutation;
- success, failure, `nil` success, payload identity, and intentionally shallow
  payload mutability;
- deterministic construction without claiming uniqueness; and
- JSON encode/decode followed by family revalidation.

A separate transient `--!strict` consumer imported the generic and every ID
alias, exercised success/failure branch narrowing and
`Result.Failure<Ids.IdError>`, then parsed, required, and executed successfully
in both places. This verifies Studio accepts and runs the typed module boundary.
The Packet 04.1 toolchain had no standalone Luau analyzer, and the Studio bridge
did not expose the editor's built-in diagnostic list, so this evidence does not
claim a programmatic Script Analysis diagnostic count. Packet 04.1 did not add a
package to manufacture that evidence. Phase 05 later selected Lune for runtime
tests; it still does not claim standalone static type-analysis coverage.

Every temporary ModuleScript, cloned folder, Instance, and connection was
destroyed or disconnected. Neither place was saved.

## Phase 03 regression evidence

At Packet 04.1 completion, the new pure modules were not required by either
bootstrap and therefore could not change startup behavior. One isolated
Play-Stop regression nevertheless passed in each synchronized place:

| Place | Ready state | Stop state | Application warnings/errors | Final mode |
| --- | --- | --- | ---: | --- |
| Lobby (`100561454756026`) | Correct `Lobby` role; lifecycle `Started`; cleanup `Active` | Lifecycle `Shutdown`; cleanup `Cleaned` | 0 | Edit |
| Match (`136401514513678`) | Correct `Match` role; lifecycle `Started`; cleanup `Active` | Lifecycle `Shutdown`; cleanup `Cleaned` | 0 | Edit |

Both servers emitted the expected structured shutdown start and completion
records with a 10-second budget and `DeveloperShutdown` close reason. No place
was saved or published.

## Formatting, lint, build, and structure verification

| Check | Result |
| --- | --- |
| `stylua src/shared/util/Ids.luau src/shared/util/Result.luau` | Pass |
| `stylua --check src` | Pass |
| `stylua --check --verify src` | Pass |
| `selene src` | Pass; 0 errors, 0 warnings, 0 parse errors |
| `rojo build default.project.json` | Pass |
| `rojo build lobby.project.json` | Pass |
| `rojo build match.project.json` | Pass |

At Packet 04.1 completion, both `Ids` and `Result` appeared at
`ReplicatedStorage.Shared.util` in every independent build:

| Build | ModuleScripts | Server Scripts | Client LocalScripts | Role-source structure |
| --- | ---: | ---: | ---: | --- |
| Default | 8 | 1 | 1 | Combined common plus empty lobby and match layers |
| Lobby | 8 | 1 | 1 | Common plus lobby; no match source |
| Match | 8 | 1 | 1 | Common plus match; no lobby source |

The exact generated build outputs were inspected, remained ignored, and were
removed afterward. Current combined-state counts are recorded in
`docs/PHASE_04_EXIT_AUDIT.md`.

## Regression procedure

After changing `Ids` or `Result`:

1. Run `stylua src tests`, then `stylua --check --verify src tests`.
2. Run `selene validate-config`, then `selene src tests`.
3. Run `lune run tests/run.luau`. Confirm all 76 ordered cases pass, including
   every ID family, malformed and cross-family use, boundaries, privacy,
   immutability, and both Result branches.
4. Run `lune run tests/verify-builds.luau`. Confirm all four builds pass, both
   modules retain their exact production source paths, Lobby/Match remain
   isolated, and no test code ships in Default, Lobby, or Match.
5. Use a temporary reviewed Studio harness only for an engine-parity case that
   the headless suite cannot represent; remove the exact harness afterward.
6. If bootstrap or engine-integration behavior changed, run isolated Play-Stop
   checks in each affected place and confirm the established lifecycle and
   cleanup terminal states.
7. Leave both places in Edit mode. Remove exact generated builds and temporary
   harnesses only. Do not save or publish merely to test.

Phase 05 subsequently added persistent fixtures and headless coverage for all ten
ID families, Result branches, malformed/cross-family use, boundaries, freezing,
and privacy. Run `lune run tests/run.luau`; the current evidence is in
`docs/TEST_RUNNER.md` and the environment status is in `docs/TEST_MATRIX.md`.
Packets 04.2 through 04.5 remain the original schema and bootstrap consumers, and
the historical Phase 04 audit remains in `docs/PHASE_04_EXIT_AUDIT.md`.
