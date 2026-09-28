import {AuthAdapter, defaultAuth} from "./auth.js";
import {request} from "./api.js";

export type EventHandlers = Record<string, (data: any) => void>;

export interface LiveStreamOptions {
  auth?: AuthAdapter;
  // Called after every reconnect, so views can refetch what they may have missed.
  onReconnect?: () => void;
  // Sent as lastEventId on reconnect, for services that replay missed events.
  replay?: boolean;
}

// A service's SSE stream. EventSource cannot send headers, so every (re)connect first fetches a single-use ticket
// with the auth headers, then opens `/stream?ticket=...`. Reconnects back off from 1 to 30 seconds.
export class LiveStream {
  private source?: EventSource;
  private lastEventId?: string;
  private retry = 1000;
  private timer?: ReturnType<typeof setTimeout>;
  private stopped = true;

  constructor(private readonly baseUrl: string, private readonly handlers: EventHandlers,
      private readonly options: LiveStreamOptions = {}) {}

  start(): void {
    if (!this.stopped || typeof EventSource === "undefined") {
      return;
    }
    this.stopped = false;
    void this.connect(false);
  }

  stop(): void {
    this.stopped = true;
    clearTimeout(this.timer);
    this.source?.close();
    this.source = undefined;
  }

  private async connect(reconnecting: boolean): Promise<void> {
    try {
      const {ticket} = await request<{ticket: string}>(this.baseUrl, "/stream-ticket",
          {method: "POST", auth: this.options.auth ?? defaultAuth()});
      if (this.stopped) {
        return;
      }
      const query = new URLSearchParams({ticket});
      if (this.options.replay && this.lastEventId) {
        query.set("lastEventId", this.lastEventId);
      }
      const source = new EventSource(`${this.baseUrl.replace(/\/+$/, "")}/stream?${query}`);
      this.source = source;
      source.onopen = () => {
        this.retry = 1000;
        if (reconnecting) {
          this.options.onReconnect?.();
        }
      };
      for (const [event, handler] of Object.entries(this.handlers)) {
        source.addEventListener(event, (e) => {
          const message = e as MessageEvent;
          if (message.lastEventId) {
            this.lastEventId = message.lastEventId;
          }
          handler(JSON.parse(message.data));
        });
      }
      source.onerror = () => {
        source.close();
        this.schedule();
      };
    } catch {
      this.schedule();
    }
  }

  private schedule(): void {
    if (this.stopped) {
      return;
    }
    this.timer = setTimeout(() => void this.connect(true), this.retry);
    this.retry = Math.min(this.retry * 2, 30000);
  }
}
