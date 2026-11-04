import { z } from 'zod';

/**
 * Opt-in usage events (Backend plan → Diagnostics). Only these names and
 * properties are kept; anything else is dropped before it reaches BigQuery,
 * so a health value can't slip in by mistake. Counts and bands, never values.
 */
const coverageBand = z.enum(['none', 'under_50', '50_to_90', 'over_90']);
const plan = z.enum(['monthly', 'yearly', 'lifetime']);
const entry = z.enum(['onboarding', 'coach', 'goal', 'trends', 'longevity', 'week_review', 'settings', 'other']);

export const eventSchemas = {
  app_open: z.object({}),
  onboarding_step: z.object({ step: z.enum(['welcome', 'connect', 'first_read', 'about_you', 'goal', 'morning_call', 'done']) }),
  permission_result: z.object({ kind: z.string().regex(/^[a-z_]{2,40}$/), granted: z.boolean() }),
  first_scores: z.object({ minutes_to_first: z.number().int().min(0).max(100_000) }),
  source_check: z.object({
    has_stages: z.boolean(),
    has_hrv: z.boolean(),
    hr_coverage: coverageBand,
    writer_count: z.number().int().min(0).max(50),
  }),
  writer_seen: z.object({ writer: z.string().regex(/^[A-Za-z0-9 ._-]{1,60}$/) }),
  morning_ready: z.object({ before_open: z.boolean() }),
  paywall_view: z.object({ entry }),
  trial_start: z.object({ plan }),
  purchase: z.object({ plan, store: z.enum(['apple', 'google']) }),
  restore: z.object({ found: z.boolean() }),
  sync_result: z.object({ ok: z.boolean(), reason: z.enum(['none', 'offline', 'auth', 'quota', 'conflict', 'crypto', 'server', 'other']) }),
} as const;

export type EventName = keyof typeof eventSchemas;

const envelope = z.object({
  install_id: z.string().regex(/^[0-9a-f-]{36}$/),
  app_version: z.string().max(32),
  platform: z.enum(['ios', 'android']),
  events: z
    .array(z.object({ name: z.string(), at: z.number().int(), props: z.record(z.unknown()).default({}) }))
    .max(200),
});

export interface EventRow {
  install_id: string;
  app_version: string;
  platform: 'ios' | 'android';
  name: EventName;
  at: string;
  props: string;
}

/** Validates a batch; returns the rows to keep and how many were dropped. */
export function sanitiseEvents(body: unknown, now: number): { rows: EventRow[]; dropped: number } {
  const env = envelope.parse(body);
  const rows: EventRow[] = [];
  let dropped = 0;
  for (const e of env.events) {
    const schema = (eventSchemas as Record<string, z.ZodTypeAny>)[e.name];
    // Not in the future, not older than 30 days.
    if (!schema || e.at > now + 5 * 60_000 || e.at < now - 30 * 86_400_000) {
      dropped++;
      continue;
    }
    const props = schema.safeParse(e.props);
    if (!props.success || Object.keys(e.props).some((k) => !(k in (props.data as object)))) {
      dropped++;
      continue;
    }
    rows.push({
      install_id: env.install_id,
      app_version: env.app_version,
      platform: env.platform,
      name: e.name as EventName,
      at: new Date(e.at).toISOString(),
      props: JSON.stringify(props.data),
    });
  }
  return { rows, dropped };
}
