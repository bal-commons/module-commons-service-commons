import {css} from "lit";

// Design tokens every component reads. Override them on any ancestor, e.g. `:root { --bc-accent: #7c3aed; }`.
export const tokens = css`
  :host {
    --_font: var(--bc-font, system-ui, -apple-system, "Segoe UI", sans-serif);
    --_fg: var(--bc-fg, #1d2330);
    --_muted: var(--bc-muted, #6b7280);
    --_bg: var(--bc-bg, #ffffff);
    --_surface: var(--bc-surface, #f5f6f8);
    --_border: var(--bc-border, #e3e6eb);
    --_accent: var(--bc-accent, #2563eb);
    --_accent-soft: var(--bc-accent-soft, #e8efff);
    --_info: var(--bc-info, #2563eb);
    --_warning: var(--bc-warning, #d97706);
    --_error: var(--bc-error, #dc2626);
    --_success: var(--bc-success, #059669);
    --_radius: var(--bc-radius, 8px);
    font-family: var(--_font);
    color: var(--_fg);
  }
  @media (prefers-color-scheme: dark) {
    :host {
      --_fg: var(--bc-fg, #e6e8ec);
      --_muted: var(--bc-muted, #9aa3b2);
      --_bg: var(--bc-bg, #171b23);
      --_surface: var(--bc-surface, #0f1218);
      --_border: var(--bc-border, #2a303b);
      --_accent: var(--bc-accent, #6ea0ff);
      --_accent-soft: var(--bc-accent-soft, #1d2940);
    }
  }
`;

// "3 min ago", "yesterday"; the exact time is left to a title attribute.
export function relativeTime(iso: string, now: number = Date.now()): string {
  const seconds = Math.round((now - new Date(iso).getTime()) / 1000);
  const format = new Intl.RelativeTimeFormat(undefined, {numeric: "auto"});
  const steps: [number, Intl.RelativeTimeFormatUnit][] = [[60, "second"], [60, "minute"], [24, "hour"], [7, "day"],
    [4.35, "week"], [12, "month"], [Number.POSITIVE_INFINITY, "year"]];
  let value = seconds;
  for (const [size, unit] of steps) {
    if (Math.abs(value) < size) {
      return format.format(-Math.round(value), unit);
    }
    value /= size;
  }
  return iso;
}
