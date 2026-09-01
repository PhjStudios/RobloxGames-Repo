# Content balance

This file records the configured earn-only balance rules that affect persistent
player state. It is not a commerce or monetization specification.

## Squad Travel Match rewards

Only an authenticated, server-owned ticketed Match can award persistent Gold.
Direct local, Development, test non-ticketed, spectator, and unexpected-arrival
sessions are explicitly non-rewarding.

The version 1 formula is personal and is never divided by squad size:

- eligible participation: **50 persistent Gold**;
- Victory: **an additional 200 persistent Gold**;
- first Victory clear of a configured map-and-difficulty pair: **an additional
  one-time 250 persistent Gold**.

Therefore an eligible Defeat awards 50 Gold, an eligible repeat Victory awards
250 Gold, and an eligible first Victory for that map-and-difficulty pair awards
500 Gold. No difficulty multiplier, boss bonus, Endless milestone reward, Robux,
premium currency, product, pass, trade, gift, or paid reward is part of this
policy.

Eligibility requires all of the following authoritative evidence:

1. admission as a participant through the expected roster of a valid ticket;
2. successful Ready submission;
3. at least one authoritative tower placement; and
4. either connection through Results or participation through at least two
   completed waves.

For a Defeat before two waves complete, the participant qualifies only if they
are connected at Results and placed at least one tower. A disconnected player
retains already-earned participation progress, but an immediate leaver who does
not meet the Results-or-two-waves rule receives zero. Spectators always receive
zero.

Battle Cash is Match-local. It is never copied into persistent Gold, is never a
reward-formula input, and is shown separately in Results. Results may display
persistent Gold as `Granted` only after the profile mutation has been durably
saved; otherwise the status is `Pending`, `Ineligible`, or `Failed`.

The source constant is `src/shared/config/MatchRewards.luau`. Durable claims use
one server-owned result ID per Match and record Gold, first-clear state, and the
result receipt in the same profile mutation.
