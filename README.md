# commons/service_commons

Shared plumbing for the commons services. It declares no listeners, so importing it never starts a server.

| Module | Provides |
|---|---|
| `service_commons` | `newId()` (ULID), epoch-millis time helpers, `ErrorBody` responses, `ErrorInterceptor` |
| `service_commons.auth` | `Authenticator` (JWT via JWKS or cert, API key, trusted headers), `AuthInterceptor`, `callerOf(ctx)`, scope checks, `TicketStore` for SSE |
| `service_commons.db` | `connect` for H2, MySQL and PostgreSQL, `migrate` (versioned, per-dialect), `atomic` (transactions), `ident`/`raw` for prefixed table names, `isDuplicateKey` |
| `service_commons.sse` | `Hub`: in-process fan-out by target key (`user:tara`, `role:Finance`), backlog replay, heartbeats |
| `service_commons.webhook` | `Webhooks`: subscriptions per participant, a transactional outbox (`enqueue` joins the caller's transaction), HMAC-signed delivery with backoff, a claim step so nodes don't send twice, a retry job, delivery history; `verify` for receivers |

Auth settings mirror the workflow module's `management.rest` configurables.

## Transactions go through `atomic`

Ballerina starts its transaction coordinator, an HTTP listener, once for **each package** that contains a
`transaction` block. Every start uses the same `coordinatorPort`, so the second start fails ("Address already in
use") and the program exits. The services therefore never write `transaction` themselves. They call
`service_commons.db:atomic(work)`, so the only `transaction` block is in this package.

An application that embeds these services and also uses `transaction` blocks of its own will hit the same failure.
Route its transactions through `atomic` too.

`work` is an isolated closure. It may use `self` and `final` readonly values, so clone records with
`cloneReadOnly()` into `final` locals first. It commits when it returns a value and rolls back when it returns an
error.
