import {AuthAdapter, defaultAuth} from "./auth.js";

// A service's error, with the `{code, message}` body every commons service returns.
export class ServiceError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
    this.name = "ServiceError";
  }
}

export interface RequestOptions {
  method?: string;
  body?: unknown;
  query?: Record<string, string | number | boolean | undefined | null>;
  auth?: AuthAdapter;
}

// Calls a commons service and returns its JSON (or undefined for 204).
export async function request<T>(baseUrl: string, path: string, options: RequestOptions = {}): Promise<T> {
  const auth = options.auth ?? defaultAuth();
  const headers: Record<string, string> = {...(await auth.headers())};
  let body: BodyInit | undefined;
  if (options.body !== undefined) {
    headers["content-type"] = "application/json";
    body = JSON.stringify(options.body);
  }
  const response = await fetch(joinUrl(baseUrl, path, options.query), {method: options.method ?? "GET", headers, body});
  if (response.status === 401) {
    auth.onUnauthorized?.();
  }
  if (!response.ok) {
    let code = "HTTP_" + response.status;
    let message = response.statusText;
    try {
      const parsed = await response.json() as {code?: string; message?: string};
      code = parsed.code ?? code;
      message = parsed.message ?? message;
    } catch {
      // Not a commons error body.
    }
    throw new ServiceError(response.status, code, message);
  }
  return (response.status === 204 ? undefined : await response.json()) as T;
}

export function joinUrl(baseUrl: string, path: string,
    query?: Record<string, string | number | boolean | undefined | null>): string {
  const url = baseUrl.replace(/\/+$/, "") + (path.startsWith("/") ? path : "/" + path);
  const params = Object.entries(query ?? {}).filter(([, v]) => v !== undefined && v !== null && v !== "");
  return params.length ? `${url}?${new URLSearchParams(params.map(([k, v]) => [k, String(v)]))}` : url;
}
