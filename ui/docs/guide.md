# bal-commons Web Components guide

This guide covers what every bal-commons UI package has in common: installing, authentication, the live model,
CORS and proxies, theming, the `correlationId` convention, events, framework notes and TypeScript types. Each
element has its own reference page.

| Package | Elements | Service |
|---|---|---|
| [`@bal-commons/notification-ui`](https://github.com/bal-commons/module-commons-notification/tree/main/ui) | [`<commons-notification-bell>`](https://github.com/bal-commons/module-commons-notification/blob/main/ui/docs/commons-notification-bell.md), [`<commons-inbox>`](https://github.com/bal-commons/module-commons-notification/blob/main/ui/docs/commons-inbox.md) | notification (`/notifications/v1`, port 9100) |
| [`@bal-commons/chat-ui`](https://github.com/bal-commons/module-commons-chat/tree/main/ui) | [`<commons-conversation-list>`](https://github.com/bal-commons/module-commons-chat/blob/main/ui/docs/commons-conversation-list.md), [`<commons-conversation>`](https://github.com/bal-commons/module-commons-chat/blob/main/ui/docs/commons-conversation.md) | chat (`/chat/v1`, port 9101) |
| [`@bal-commons/attachment-ui`](https://github.com/bal-commons/module-commons-attachment/tree/main/ui) | [`<commons-upload-case>`](https://github.com/bal-commons/module-commons-attachment/blob/main/ui/docs/commons-upload-case.md), [`<commons-case-list>`](https://github.com/bal-commons/module-commons-attachment/blob/main/ui/docs/commons-case-list.md), [`<commons-file-viewer>`](https://github.com/bal-commons/module-commons-attachment/blob/main/ui/docs/commons-file-viewer.md), [`<commons-file-preview>`](https://github.com/bal-commons/module-commons-attachment/blob/main/ui/docs/commons-file-preview.md) | attachment (`/attachments/v1`, port 9102) |
| [`@bal-commons/hub-ui`](https://github.com/bal-commons/commons-hub-ui) | [`<commons-hub>`](https://github.com/bal-commons/commons-hub-ui/blob/main/docs/commons-hub.md) | all three |
| `@bal-commons/ui-core` (this package) | none | shared plumbing |

All elements are Lit 3 Web Components with Shadow DOM. They work in plain HTML and in any framework.

## Install

> The packages are not yet published to npm. Until they are, build them locally (`npm install && npm run build` in
> each package directory, starting with `service-commons/ui`) and either `npm link` them into your app or copy the
> `dist/*.bundle.js` files into your static assets. The `npm install` and CDN lines below are the intended usage
> once the packages are published.

### With a bundler (npm)

```sh
npm install @bal-commons/notification-ui @bal-commons/chat-ui @bal-commons/attachment-ui
```

```js
import "@bal-commons/notification-ui";   // registers <commons-notification-bell> and <commons-inbox>
import {bearer, configureAuth} from "@bal-commons/chat-ui";
```

Importing a package registers its elements. `dist/index.js` contains only the package's own code; `lit` and
`@bal-commons/ui-core` are regular dependencies, so your bundler shares one copy of each across packages.

If you want the single page with everything, install only the hub. It depends on and registers all the other
packages:

```sh
npm install @bal-commons/hub-ui
```

### Without a build step (single-file bundle)

Each package also ships `dist/<name>.bundle.js`: one ES module with Lit and ui-core inlined.

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/@bal-commons/notification-ui@0.1/dist/notification-ui.bundle.js"></script>
<script type="module">
  import {bearer, configureAuth} from "https://cdn.jsdelivr.net/npm/@bal-commons/notification-ui@0.1/dist/notification-ui.bundle.js";
  configureAuth(bearer(() => sessionStorage.getItem("token")));
</script>
```

| Bundle | Contains |
|---|---|
| `notification-ui.bundle.js` | Lit, ui-core, notification-ui |
| `chat-ui.bundle.js` | Lit, ui-core, chat-ui |
| `attachment-ui.bundle.js` | Lit, ui-core, attachment-ui |
| `hub-ui.bundle.js` | Lit, ui-core, notification-ui, chat-ui, attachment-ui, hub-ui |

The npm packages expose the bundle as a subpath too, e.g. `@bal-commons/hub-ui/bundle`.

**Load one bundle per page where you can.** If you use `<commons-hub>`, load only `hub-ui.bundle.js`: it already
registers every commons element. Loading a package bundle next to the hub bundle does not break anything (each
element is defined only once, by whichever bundle loads first, and the auth default is shared through `globalThis`),
but the page then downloads Lit and the components twice, and each bundle keeps its own live feeds, so the page
opens two SSE connections to the same service. Mixing the notification, chat and attachment bundles on one page has
the same cost for Lit and ui-core, but each service still gets one stream.

`chat-ui` renders `<commons-upload-case>` for attachment messages only when that element is registered, so load
`attachment-ui` (or the hub) too if your conversations carry upload requests.

## Authentication

Components never read tokens themselves. They ask an **auth adapter** for request headers.

```ts
interface AuthAdapter {
  headers(): Record<string, string> | Promise<Record<string, string>>;
  // Called when a service answers 401, e.g. to send the user to sign in again.
  onUnauthorized?(): void;
}
```

| Adapter | Sends | When |
|---|---|---|
| `bearer(getToken, onUnauthorized?)` | `Authorization: Bearer <token>`, or nothing when `getToken` returns empty | The app has an OIDC or OAuth access token. `getToken` may be async, so it can refresh first |
| `devUser(userId, roles?, scopes?)` | `x-user-id`, `x-user-roles` (comma-separated), `x-user-scopes` (space-separated, only when given) | The service runs with neither JWT nor API key enabled and trusts these headers. Development only |
| your own object | whatever `headers()` returns | Anything else, e.g. a gateway header or a cookie-backed session with a CSRF header |

`bearer`, `devUser` and `configureAuth` are exported by every package (and by the hub), so import them from the
package you already load.

### A custom adapter

```ts
import {configureAuth, type AuthAdapter} from "@bal-commons/ui-core";

const gatewayAuth: AuthAdapter = {
  async headers() {
    const token = await myAuthClient.getAccessToken();   // refreshes if needed
    return {Authorization: `Bearer ${token}`, "x-tenant": currentTenant()};
  },
  onUnauthorized() {
    myAuthClient.signIn();
  }
};
configureAuth(gatewayAuth);
```

Any extra header you send cross-origin must be allowed by the service's CORS configuration. The services allow
`Authorization`, `Content-Type`, the three `x-user-*` headers and the configured API key header.

### `configureAuth` versus the `auth` property

- `configureAuth(adapter)` sets the default for every bal-commons element on the page. It is stored on
  `globalThis`, so it also reaches elements from a second bundle. Call it once at startup, before or after the
  elements are created. Elements read it on each request.
- Every element also has an `auth` property (property only, no attribute). It overrides the default for that
  element's requests: `inbox.auth = bearer(() => otherToken)`.

One limit applies to the per-element `auth`: the live stream for a service URL is created by the first element that
subscribes to it, with that element's adapter (or the default when it has none), and it is kept for the page's
lifetime. Later elements on the same URL share that stream even if their `auth` differs. Use one identity per
service URL on a page.

When a request answers 401, `request()` calls `onUnauthorized()` before throwing. The live stream's ticket request
goes through the same path.

## The live model

Every list and detail element stays up to date without polling.

1. **One stream per service URL.** Each package keeps a feed per base URL (`notificationFeed`, `chatFeed`,
   `attachmentFeed`). The first element that needs it opens the stream; every other element on the same URL shares
   it. The stream closes when the last element unsubscribes (for example, when it is removed from the DOM).
2. **Ticket, then EventSource.** `EventSource` cannot send headers, so each connect first calls
   `POST <base-url>/stream-ticket` with the adapter's headers. The service returns a short-lived ticket (60 seconds
   by default, `ticketTtlSeconds`). The component then opens `GET <base-url>/stream?ticket=...`.
3. **Reconnects.** If the stream errors or the ticket call fails, it retries after 1 second, doubling up to 30
   seconds. Each reconnect gets a new ticket.
4. **Catching up.** After a reconnect, elements refetch what they show. The notification stream also sends
   `lastEventId` so the service replays missed `notification.created` events (up to `replayLimit`, 200 by default);
   the chat and attachment services do not replay, so their elements rely on the refetch.
5. **Change handling.** Some elements apply events directly (the inbox inserts new notifications, the conversation
   appends streamed text). Others refetch on any relevant change, debounced by 300 ms (conversation list, case
   list, hub badges).

If `EventSource` is not available (for example during server-side rendering), the stream does nothing.

You can subscribe to a feed yourself, e.g. to refresh your own view when a case changes:

```ts
import {attachmentFeed, type AttachmentChange} from "@bal-commons/attachment-ui";

const stop = attachmentFeed("/api/attachments").subscribe((change: AttachmentChange) => {
  if (change.type === "case" && change.event === "case.submitted") {
    refreshOrder(change.case.correlationId);
  }
});
// later: stop();
```

| Feed | Change types |
|---|---|
| `notificationFeed(url, auth?)` | `created` (`notification`), `read` (`id`, `readAt`), `unread` (`id`), `read-all`, `deleted` (`id`), `reconnected` |
| `chatFeed(url, auth?)` | `message` (`message`), `delta` (`conversationId`, `messageId`, `text`), `typing` (`conversationId`, `participantId`), `conversation` (`conversation`), `read` (`conversationId`, `participantId`, `seq`), `reconnected` |
| `attachmentFeed(url, auth?)` | `case` (`event`, `case`), `file` (`event`, `caseId`, `attachment`), `reconnected` |

### Proxies must not buffer SSE

The stream is a long-lived `text/event-stream` response. A proxy that buffers responses holds events back until
the buffer fills, so the UI looks frozen. For nginx:

```nginx
location /api/notifications/ {
    proxy_pass http://notifications:9100/notifications/v1/;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 1h;
}

location /api/attachments/ {
    proxy_pass http://attachments:9102/attachments/v1/;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_buffering off;
    proxy_read_timeout 1h;
    client_max_body_size 10m;   # at least the service's maxFileBytes (10 MiB by default)
}
```

Proxy the whole base path. The attachment service serves signed file links under `<base path>/links/...`, and
`AttachmentClient.link()` maps them onto the `base-url` you gave the element.

## CORS

When the page and a service are on different origins, set `corsAllowOrigins` in that service's `Config.toml`. The
default is `["*"]`.

```toml
[commons.attachment.server]
corsAllowOrigins = ["https://app.example.com"]
```

A same-origin proxy path (e.g. `base-url="/api/chat"`) avoids CORS altogether.

## Theming

### Tokens

Every element reads these CSS custom properties. Set them on any ancestor; custom properties inherit through
Shadow DOM.

| Token | Light default | Dark default | Used for |
|---|---|---|---|
| `--bc-font` | `system-ui, -apple-system, "Segoe UI", sans-serif` | same | Font family |
| `--bc-fg` | `#1d2330` | `#e6e8ec` | Text |
| `--bc-muted` | `#6b7280` | `#9aa3b2` | Secondary text |
| `--bc-bg` | `#ffffff` | `#171b23` | Surfaces: cards, bubbles, inputs |
| `--bc-surface` | `#f5f6f8` | `#0f1218` | Backgrounds behind surfaces, hover |
| `--bc-border` | `#e3e6eb` | `#2a303b` | Borders |
| `--bc-accent` | `#2563eb` | `#6ea0ff` | Buttons, selection, links, unread markers |
| `--bc-accent-soft` | `#e8efff` | `#1d2940` | Selected rows, own chat bubbles |
| `--bc-info` | `#2563eb` | same | INFO notifications |
| `--bc-warning` | `#d97706` | same | WARNING notifications, "Needs your upload" |
| `--bc-error` | `#dc2626` | same | Errors, the bell badge, delete actions |
| `--bc-success` | `#059669` | same | SUCCESS notifications, satisfied slots |
| `--bc-radius` | `8px` | same | Corner radius of cards and panels |

```css
:root {
  --bc-accent: #7c3aed;
  --bc-accent-soft: #f1ebff;
  --bc-font: "Inter", system-ui, sans-serif;
  --bc-radius: 12px;
}
```

Text on accent-coloured buttons and badges is always white (`#fff`), so pick an accent with enough contrast.

### Dark mode

The defaults follow `prefers-color-scheme`. A token you set wins in both schemes, because the dark defaults are
only fallbacks. So if you set colour tokens, set them for dark mode too:

```css
:root { --bc-bg: #fffdf8; --bc-surface: #f6f1e7; }
@media (prefers-color-scheme: dark) {
  :root { --bc-bg: #1b1916; --bc-surface: #12110f; }
}
/* Or follow your app's own switch: */
:root[data-theme="dark"] { --bc-fg: #e6e8ec; --bc-bg: #171b23; --bc-surface: #0f1218; --bc-border: #2a303b; }
```

To force one scheme regardless of the OS setting, set all seven scheme-dependent tokens (`--bc-fg`, `--bc-muted`,
`--bc-bg`, `--bc-surface`, `--bc-border`, `--bc-accent`, `--bc-accent-soft`).

### CSS parts

Each element exposes named parts for layout and fine-tuning, listed on its reference page:

```css
commons-inbox::part(item) { border-radius: 0; }
commons-notification-bell::part(badge) { background: var(--bc-accent); }
```

Parts reach one shadow root deep. Parts of elements nested inside another element's shadow root (for example the
inbox inside `<commons-hub>`, or the preview dialog inside `<commons-file-viewer>`) are not re-exported, so style
those through the tokens.

## The `correlationId` convention

Notifications, conversations and upload cases each carry an optional `correlationId`: the ID of the business
object they are about, such as an order, a claim or a maintenance request. Use **the same value** for all three
when they concern the same object.

| Service | Field | Notes |
|---|---|---|
| notification | `Notification.correlationId` | Optional. Filter with `<commons-inbox correlation-id>` |
| chat | `Conversation.correlationId` | Defaults to the conversation ID. Creating a conversation with an existing `correlationId` returns the existing one, so there is one conversation per value. Shown as the title when there is no `title` |
| attachment | `Case.correlationId` | Defaults to the case ID. Several cases may share a value |

What this gives you:

- `<commons-hub>` routes a clicked notification to the conversation with the same `correlationId`, or, if there is
  none, to the newest upload case with it.
- `<commons-inbox>`, `<commons-conversation-list>` and `<commons-case-list>` all take `correlation-id`, so an
  order page can show "everything about order 4711" with three elements and one value.

```html
<commons-inbox base-url="/api/notifications" correlation-id="order-4711" hide-tabs></commons-inbox>
<commons-conversation-list base-url="/api/chat" correlation-id="order-4711"></commons-conversation-list>
<commons-case-list base-url="/api/attachments" correlation-id="order-4711"></commons-case-list>
```

## Events

- Every element event is a `CustomEvent` named `commons-*`.
- All of them bubble and are composed, so they cross Shadow DOM boundaries. You can listen on the element, on a
  container, on `<commons-hub>` or on `document`.
- Data is in `event.detail`, always an object with a named field (`{notification}`, `{conversation}`, `{message}`,
  `{attachment}`, `{case}`), except `commons-bell-click` and `commons-preview-close`, which carry no detail.
- A few events are cancelable. Call `event.preventDefault()` to stop the element's default action:

| Event | Default action |
|---|---|
| `commons-notification-click` | Marks the notification read |
| `commons-file-open` | Opens the built-in `<commons-file-preview>` dialog |
| `commons-hub-navigate` | The hub shows the pane (and selection) in `detail` |

| Event | Fired by | `detail` |
|---|---|---|
| `commons-bell-click` | bell | none |
| `commons-notification-click` | inbox | `{notification: Notification}` |
| `commons-conversation-select` | conversation list | `{conversation: Conversation}` |
| `commons-message-sent` | conversation | `{message: Message}` |
| `commons-form-submitted` | conversation | `{message: Message}` (the answer) |
| `commons-case-select` | case list | `{case: Case}` |
| `commons-file-uploaded` | upload case | `{attachment: Attachment}` |
| `commons-file-deleted` | upload case, file viewer | `{attachment: Attachment}` |
| `commons-file-open` | upload case, file viewer | `{attachment: Attachment}` |
| `commons-file-downloaded` | file viewer, file preview | `{attachment: Attachment}` |
| `commons-case-submitted` | upload case | `{case: Case}` |
| `commons-preview-close` | file preview | none |
| `commons-hub-navigate` | hub | `{pane: string; id?: string; notification?: Notification}` |

Because events are composed, an event from an element nested inside another one (for example
`commons-file-uploaded` from the upload card inside a conversation, or `commons-file-downloaded` from the preview
inside a file viewer) also reaches listeners on the outer element, retargeted to it.

Events report what the caller did through this element. Changes made elsewhere (another tab, another user, the
backend) arrive through the live stream and update the elements, but do not fire these events. Subscribe to a feed
for those.

## Framework notes

The elements are registered by importing the package. Import it before the framework renders them, so the
framework can see their properties.

### React 19

React 19 passes properties and events to custom elements directly. A prop whose name is a property of the element
(`me`, `auth`, `showFilters`) is set as a property; any other prop (`base-url`) is set as an attribute. A prop
starting with `on` and holding a function adds an event listener for the rest of the name.

```tsx
import "@bal-commons/chat-ui";
import {useState} from "react";

export function Chat({userId}: {userId: string}) {
  const [id, setId] = useState<string>();
  return <div className="chat">
    <commons-conversation-list base-url="/api/chat" me={userId} searchable={true}
        oncommons-conversation-select={(e: CustomEvent) => setId(e.detail.conversation.id)} />
    {id && <commons-conversation base-url="/api/chat" conversation-id={id} me={userId} />}
  </div>;
}
```

For boolean options, pass the camelCase property (`showFilters={true}`, `hideTabs={true}`, `unreadOnly={true}`)
rather than the dashed attribute name. React 18 and earlier set everything as attributes and cannot add custom
event listeners; use a `ref` and `addEventListener` there.

The packages declare their elements in `HTMLElementTagNameMap` but ship no JSX types. For TypeScript, declare the
tags you use:

```ts
// custom-elements.d.ts
import type {CommonsConversation, CommonsConversationList} from "@bal-commons/chat-ui";
import type {DetailedHTMLProps, HTMLAttributes} from "react";

type Element<T> = DetailedHTMLProps<HTMLAttributes<T>, T> & Partial<Omit<T, keyof HTMLElement>> & {
  [attribute: `${string}-${string}`]: unknown;
};

declare module "react" {
  namespace JSX {
    interface IntrinsicElements {
      "commons-conversation-list": Element<CommonsConversationList>;
      "commons-conversation": Element<CommonsConversation>;
    }
  }
}
```

### Vue 3

Tell the compiler the `commons-` tags are custom elements:

```ts
// vite.config.ts
import vue from "@vitejs/plugin-vue";
export default {
  plugins: [vue({template: {compilerOptions: {isCustomElement: (tag) => tag.startsWith("commons-")}}})]
};
```

```vue
<commons-inbox base-url="/api/notifications" :auth.prop="auth" show-filters
    @commons-notification-click="(e) => router.push(e.detail.notification.actionUrl)" />
```

Vue sets a binding as a property when the element has one; `.prop` forces it (useful for `auth` and `labels`).

### Angular

Add `CUSTOM_ELEMENTS_SCHEMA` to the component (or module) that uses the tags:

```ts
import {Component, CUSTOM_ELEMENTS_SCHEMA} from "@angular/core";
import "@bal-commons/attachment-ui";

@Component({
  selector: "app-case",
  standalone: true,
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  template: `<commons-upload-case base-url="/api/attachments" [attr.case-id]="caseId" [me]="userId"
      (commons-case-submitted)="onSubmitted($event)"></commons-upload-case>`
})
export class CaseComponent { /* caseId, userId, onSubmitted(e: CustomEvent) */ }
```

`[prop]` binds a property (use it for `auth`, `me`, `caseId`); `[attr.name]` binds an attribute; `(event)`
listens to a custom event.

### Svelte

Svelte sets a prop as a property when the element has one. Listen with `on:commons-...` in Svelte 4, or
`oncommons-...` in Svelte 5:

```svelte
<script>
  import "@bal-commons/notification-ui";
</script>
<commons-inbox base-url="/api/notifications" showFilters={true}
    oncommons-notification-click={(e) => goto(e.detail.notification.actionUrl)}></commons-inbox>
```

## TypeScript types

Each package ships `.d.ts` files and a Custom Elements Manifest (`dist/custom-elements.json`, referenced from
`package.json` as `customElements`), which IDEs and tools read.

| Package | Types |
|---|---|
| ui-core | `AuthAdapter`, `RequestOptions`, `ServiceError`, `LiveStream`, `LiveStreamOptions`, `EventHandlers` |
| notification-ui | `Notification`, `NotificationPage`, `UnreadCount`, `ListOptions`, `Box`, `Severity`, `RecipientType`, `FeedChange`, element classes `CommonsNotificationBell`, `CommonsInbox`, `NotificationClient` |
| chat-ui | `Conversation`, `Message`, `MessageKind`, `Participant`, `ParticipantType`, `FormContent`, `FormSchema`, `ChatChange`, element classes `CommonsConversationList`, `CommonsConversation`, `ChatClient` |
| attachment-ui | `Case`, `CasePage`, `CaseQuery`, `CaseStatus`, `Slot`, `Attachment`, `AttachmentChange`, `PreviewKind`, element classes `CommonsUploadCase`, `CommonsCaseList`, `CommonsFileViewer`, `CommonsFilePreview`, `AttachmentClient`, helpers `formatBytes`, `previewKind` |
| hub-ui | `CommonsHub`, `HubLocation`, `BuiltInPane` |

`document.querySelector("commons-inbox")` is typed as `CommonsInbox` once the package is imported, because each
element adds itself to `HTMLElementTagNameMap`.

### Calling a service without the elements

Each package has a typed client for custom views; they use the same auth adapter:

```ts
import {ChatClient} from "@bal-commons/chat-ui";
import {ServiceError} from "@bal-commons/ui-core";

const chat = new ChatClient("/api/chat");          // or new ChatClient(url, adapter)
try {
  const {items} = await chat.listConversations({status: "OPEN", correlationId: "order-4711"});
} catch (e) {
  if (e instanceof ServiceError) console.log(e.status, e.code, e.message);
}
```

`request(baseUrl, path, options)` is the underlying call: it adds the adapter's headers, sends `body` as JSON,
drops empty `query` values, returns `undefined` for 204, and throws `ServiceError(status, code, message)` from the
service's `{code, message}` error body (or `HTTP_<status>` and the status text when the body is not one).

`relativeTime(iso)` formats a timestamp as "3 minutes ago" or "yesterday" with `Intl.RelativeTimeFormat` in the
browser's locale; the elements put the exact ISO time in a `title` attribute next to it.
