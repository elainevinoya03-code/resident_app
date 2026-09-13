-- ============================================================================
-- CPSS resident_app — home dashboard schema
-- ----------------------------------------------------------------------------
-- Run this in the Supabase SQL editor (or as a migration).
--
-- Depends on the existing `users`, `reports`, `report_photos`,
-- `report_videos` and `report_status_updates` tables already being in place.
-- This file only adds the two tables the home screen reads from:
--   * public.hotlines       -> emergency hotline pills
--   * public.notifications  -> alert badge count / Alerts tab
-- ============================================================================

-- 1. Emergency hotlines shown on the home screen -----------------------------
create table if not exists public.hotlines (
  id          uuid        primary key default gen_random_uuid(),
  label       text        not null,
  number      text        not null,
  sort_order  integer     not null default 0,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now()
);

comment on table public.hotlines is
  'Emergency hotlines rendered as pills on the resident home screen.';

-- Seed only when empty so the script is safe to re-run.
insert into public.hotlines (label, number, sort_order)
select * from ( values
  ('BFP',    '911',        1),
  ('PNP',    '911',        2),
  ('TSEMSD', '(02) 8922-7000', 3),
  ('NDRRMO', '911',        4)
) as seed (label, number, sort_order)
where not exists (select 1 from public.hotlines);

-- 2. System alert broadcasts ------------------------------------------------
create table if not exists public.notifications (
  id            uuid        primary key default gen_random_uuid(),
  title         text        not null,
  body          text        not null,
  severity      text        not null default 'medium'
                check (severity in ('critical', 'high', 'medium', 'low')),
  acknowledged  boolean     not null default false,
  published_at  timestamptz not null default now(),
  created_at    timestamptz not null default now()
);

comment on table public.notifications is
  'Broadcast alerts shown in the Alerts tab; the acknowledged flag powers the home badge count.';

insert into public.notifications (title, body, severity, published_at)
select * from ( values
  (
    'Typhoon Aghon - Signal No. 2 Raised (Quezon City)',
    'PAGASA has raised Tropical Storm Warning Signal No. 2 over the entirety of Quezon City. Expect strong winds (75-100 kph) and heavy rainfall. Residents in low-lying and flood-prone areas are advised to evacuate immediately. Emergency shelters: Quezon City High School, Batasan Hills National High School, Commonwealth Elementary School.',
    'critical',
    now() - interval '6 hours'
  ),
  (
    'Flood Warning - Tullahan River Level Rising',
    'Tullahan River is now at critical level and rising. Residents near riverbanks in Brgy. Tandang Sora, Culiat, and Sauyo are advised to pre-emptively evacuate.',
    'high',
    now() - interval '5 hours'
  ),
  (
    'Road Closure - Mindanao Ave. Northbound',
    'Mindanao Ave. northbound is closed from Tandang Sora Ave. to Sauyo Rd. due to flooding and emergency response operations. Use alternate routes via Quirino Highway or Congressional Ave.',
    'medium',
    now() - interval '1 day'
  ),
  (
    'Scheduled Power Interruption - Brgy. Tandang Sora',
    'Meralco will conduct system maintenance on June 15, 2025 from 8:00 AM to 5:00 PM. Affected: selected streets within Tandang Sora including areas near Visayas Ave. and Congressional Ave.',
    'low',
    now() - interval '2 days'
  )
) as seed (title, body, severity, published_at)
where not exists (select 1 from public.notifications);

-- 3. Row Level Security -----------------------------------------------------
-- The mobile app talks to these tables with the anon key, so grant public
-- read access; any resident may acknowledge/update (globally, per broadcast).
alter table public.hotlines enable row level security;
drop policy if exists "home_hotlines_select" on public.hotlines;
create policy "home_hotlines_select"
  on public.hotlines for select
  using (true);

alter table public.notifications enable row level security;
drop policy if exists "home_notifications_select" on public.notifications;
create policy "home_notifications_select"
  on public.notifications for select
  using (true);
drop policy if exists "home_notifications_update" on public.notifications;
create policy "home_notifications_update"
  on public.notifications for update
  using (true)
  with check (true);