# @bal-commons/ui-core

Shared plumbing for the bal-commons UI components, such as
[`@bal-commons/notification-ui`](https://github.com/bal-commons/module-commons-notification/tree/main/ui). Apps
normally use it only through those packages, which re-export `configureAuth`, `bearer` and `devUser`.

| Export | |
|---|---|
| `configureAuth(adapter)`, `bearer(getToken)`, `devUser(id, roles)` | How components authenticate. The default is shared by every package on the page |
| `request(baseUrl, path, options)`, `ServiceError` | Calls a commons service and maps its `{code, message}` errors |
| `LiveStream` | A service's SSE stream: fetches a single-use ticket, then reconnects with backoff (1–30 s), optionally replaying missed events |
| `tokens`, `relativeTime` | The `--bc-*` design tokens (with dark-mode defaults) and "3 min ago" formatting |

```sh
npm install && npm run build
```
