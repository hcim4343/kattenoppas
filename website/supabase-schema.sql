-- Kattenoppas Logboek: database
-- Eenmalig door de developer uit te voeren: Supabase > SQL Editor > plak alles > Run.
--
-- Hoe het werkt:
--   * Iedereen maakt een account met naam + wachtwoord.
--   * Een eigenaar maakt in de app een "huis" aan en kiest zelf de huiscode.
--   * Oppassen worden lid van dat huis met die code.
--   * Elk huis ziet alleen zijn eigen leden en bezoeken.
--
-- Had je de vorige versie van dit script al uitgevoerd? Haal dan eerst de -- weg
-- voor de volgende regel (dit wist de oude tabellen):
-- drop table if exists public.visits, public.profiles, public.settings cascade;

create extension if not exists pgcrypto;

-- ── Tabellen ────────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 40),
  created_at timestamptz not null default now()
);

create table if not exists public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 60),
  invite_code text not null unique check (char_length(invite_code) between 4 and 40),
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.memberships (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner', 'sitter')),
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create table if not exists public.visits (
  id bigint generated always as identity primary key,
  household_id uuid not null references public.households(id) on delete cascade,
  who uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  arrived_at timestamptz not null default now(),
  left_at timestamptz,
  tasks text[] not null default '{}',
  note text not null default '' check (char_length(note) <= 500),
  closed_by uuid references public.profiles(id) on delete set null
);
create index if not exists visits_household_arrived on public.visits (household_id, arrived_at desc);

alter table public.profiles    enable row level security;
alter table public.households  enable row level security;
alter table public.memberships enable row level security;
alter table public.visits      enable row level security;

-- De huiscode is nooit rechtstreeks leesbaar; de eigenaar vraagt ze op via get_invite_code().
revoke select, update on public.households from anon, authenticated;
grant select (id, name, created_by, created_at) on public.households to authenticated;

-- ── Hulpfuncties ────────────────────────────────────────────────────────────
create or replace function public.is_member(hid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships where household_id = hid and user_id = auth.uid());
$$;

create or replace function public.is_owner(hid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships where household_id = hid and user_id = auth.uid() and role = 'owner');
$$;

create or replace function public.shares_household(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships a join memberships b on a.household_id = b.household_id
    where a.user_id = auth.uid() and b.user_id = other
  );
$$;

create or replace function public.norm_code(c text)
returns text language sql immutable as $$ select upper(regexp_replace(coalesce(c, ''), '\s+', '', 'g')) $$;

-- Eigenaar maakt een huis aan en kiest de huiscode.
create or replace function public.create_household(p_name text, p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare hid uuid; code text := norm_code(p_code);
begin
  if auth.uid() is null then raise exception 'not_logged_in'; end if;
  if char_length(code) < 4 then raise exception 'code_too_short'; end if;
  if exists (select 1 from households where invite_code = code) then raise exception 'code_taken'; end if;
  insert into households (name, invite_code, created_by) values (trim(p_name), code, auth.uid()) returning id into hid;
  insert into memberships (household_id, user_id, role) values (hid, auth.uid(), 'owner');
  return hid;
end; $$;

-- Oppas wordt lid met de huiscode.
create or replace function public.join_household(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare hid uuid;
begin
  if auth.uid() is null then raise exception 'not_logged_in'; end if;
  select id into hid from households where invite_code = norm_code(p_code);
  if hid is null then raise exception 'wrong_code'; end if;
  insert into memberships (household_id, user_id, role) values (hid, auth.uid(), 'sitter')
  on conflict do nothing;
  return hid;
end; $$;

-- Alleen de eigenaar ziet en verandert de huiscode.
create or replace function public.get_invite_code(hid uuid)
returns text language plpgsql stable security definer set search_path = public as $$
begin
  if not is_owner(hid) then raise exception 'not_owner'; end if;
  return (select invite_code from households where id = hid);
end; $$;

create or replace function public.set_invite_code(hid uuid, p_code text)
returns void language plpgsql security definer set search_path = public as $$
declare code text := norm_code(p_code);
begin
  if not is_owner(hid) then raise exception 'not_owner'; end if;
  if char_length(code) < 4 then raise exception 'code_too_short'; end if;
  if exists (select 1 from households where invite_code = code and id <> hid) then raise exception 'code_taken'; end if;
  update households set invite_code = code where id = hid;
end; $$;

-- Eigenaar verwijdert een oppas uit het huis (niet zichzelf).
create or replace function public.remove_member(hid uuid, uid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner(hid) then raise exception 'not_owner'; end if;
  if uid = auth.uid() then raise exception 'cannot_remove_self'; end if;
  delete from memberships where household_id = hid and user_id = uid;
end; $$;

-- Iemand verlaat zelf een huis.
create or replace function public.leave_household(hid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if is_owner(hid) then raise exception 'owner_cannot_leave'; end if;
  delete from memberships where household_id = hid and user_id = auth.uid();
end; $$;

revoke all on function public.create_household(text, text), public.join_household(text),
  public.get_invite_code(uuid), public.set_invite_code(uuid, text),
  public.remove_member(uuid, uuid), public.leave_household(uuid) from public, anon;
grant execute on function public.create_household(text, text), public.join_household(text),
  public.get_invite_code(uuid), public.set_invite_code(uuid, text),
  public.remove_member(uuid, uuid), public.leave_household(uuid) to authenticated;

-- ── Wie mag wat ─────────────────────────────────────────────────────────────
drop policy if exists "profiel: zichzelf en huisgenoten" on public.profiles;
create policy "profiel: zichzelf en huisgenoten" on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_household(id));
drop policy if exists "profiel: eigen aanmaken" on public.profiles;
create policy "profiel: eigen aanmaken" on public.profiles for insert to authenticated
  with check (id = auth.uid());
drop policy if exists "profiel: eigen wijzigen" on public.profiles;
create policy "profiel: eigen wijzigen" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "huis: leden zien het" on public.households;
create policy "huis: leden zien het" on public.households for select to authenticated
  using (public.is_member(id));
drop policy if exists "huis: eigenaar hernoemt" on public.households;
create policy "huis: eigenaar hernoemt" on public.households for update to authenticated
  using (public.is_owner(id)) with check (public.is_owner(id));
grant update (name) on public.households to authenticated;

drop policy if exists "leden: zien elkaar" on public.memberships;
create policy "leden: zien elkaar" on public.memberships for select to authenticated
  using (public.is_member(household_id));

drop policy if exists "bezoek: leden zien" on public.visits;
create policy "bezoek: leden zien" on public.visits for select to authenticated
  using (public.is_member(household_id));
drop policy if exists "bezoek: zelf inchecken" on public.visits;
create policy "bezoek: zelf inchecken" on public.visits for insert to authenticated
  with check (public.is_member(household_id) and who = auth.uid());
drop policy if exists "bezoek: afsluiten" on public.visits;
create policy "bezoek: afsluiten" on public.visits for update to authenticated
  using (public.is_member(household_id)) with check (public.is_member(household_id));

-- ── Live updates ────────────────────────────────────────────────────────────
do $$ begin alter publication supabase_realtime add table public.visits;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.memberships;
exception when duplicate_object then null; end $$;
