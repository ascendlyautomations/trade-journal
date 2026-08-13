# Repository request lifecycle

Native iOS standard for `Default*Repository` network methods.

## Lifecycle (composition)

| Step | Responsibility |
|------|----------------|
| fetch | Repository method; optional memory / session cache hit |
| coalesce | ``RepositoryRequestFlight`` — identical concurrent keys share one network op |
| refresh(force:) | Feature / bootstrap clears cache then calls fetch |
| invalidate | Logout / identity change via ``SessionScopedCaches`` |

`RepositoryRequestFlight` is **not** a result cache. Session stores (`SessionAccountsStore`, `SessionOwnerTradesStore`, etc.) own TTL / disk semantics.

## Flown bootstrap paths

- `profiles.profile` / `profiles.stats` (via `ProfileRequestFlight` façade)
- `profiles.wallPosts` / `profiles.followState`
- `trades.owned` / `trades.accounts`
- `achievements.list`
- `feed.profileReels`
- `rooms.owned`

## Intentionally not flown at repo layer

Feed timeline pages, messaging conversations, notification unread — single screen/domain owners already serialize; rapidly changing or cursor-paginated surfaces without shared owners.
