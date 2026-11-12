
-- =========================================
-- あつまろ データベース構築SQL
-- Supabase SQL Editorで全体を実行
-- =========================================

create extension if not exists pgcrypto;

-- 1. テーブル作成

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  code text not null unique,
  start_date date not null,
  end_date date not null,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  check (end_date >= start_date),
  check (end_date - start_date <= 124)
);

create table if not exists public.room_members (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null,
  display_name text not null check (char_length(display_name) between 1 and 30),
  joined_at timestamptz not null default now(),
  unique(room_id, user_id),
  unique(id, room_id)
);

create table if not exists public.availability (
  room_id uuid not null references public.rooms(id) on delete cascade,
  member_id uuid not null,
  date date not null,
  answer text check (answer in ('○','△','×')),
  updated_at timestamptz not null default now(),
  primary key(member_id, date),
  foreign key(member_id, room_id)
    references public.room_members(id, room_id)
    on delete cascade
);

-- 2. インデックス

create index if not exists room_members_room_idx
on public.room_members(room_id);

create index if not exists availability_room_date_idx
on public.availability(room_id, date);

-- 3. RLS（行レベルセキュリティ）

alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.availability enable row level security;

-- クライアントからの直接操作権限を制限
revoke all on public.rooms from public, anon, authenticated;
revoke all on public.room_members from public, anon, authenticated;
revoke all on public.availability from public, anon, authenticated;

grant select on public.rooms to anon, authenticated;
grant select on public.room_members to anon, authenticated;
grant select on public.availability to anon, authenticated;

-- 4. ルーム参加確認関数

create or replace function public.is_room_member(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.room_members
    where room_id = p_room_id
      and user_id = auth.uid()
  );
$$;

-- 5. 読み取りポリシー

drop policy if exists "members can read rooms"
on public.rooms;

create policy "members can read rooms"
on public.rooms
for select
using (public.is_room_member(id));

drop policy if exists "members can read room members"
on public.room_members;

create policy "members can read room members"
on public.room_members
for select
using (public.is_room_member(room_id));

drop policy if exists "members can read availability"
on public.availability;

create policy "members can read availability"
on public.availability
for select
using (public.is_room_member(room_id));

-- 6. ルーム作成関数

create or replace function public.create_room(
  p_name text,
  p_start date,
  p_end date,
  p_display_name text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms;
  v_code text;
  v_member public.room_members;
begin
  if auth.uid() is null then
    raise exception 'セッションを確認できません。';
  end if;

  if p_name is null
    or char_length(trim(p_name)) not between 1 and 80
    or p_display_name is null
    or char_length(trim(p_display_name)) not between 1 and 30
  then
    raise exception 'ルーム名は1〜80文字、参加者名は1〜30文字で入力してください。';
  end if;

  if p_start is null or p_end is null
    or p_end < p_start
    or p_end - p_start > 124
  then
    raise exception '調整期間は1〜125日以内にしてください。';
  end if;

  loop
    v_code :=
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4))
      || '-'
      || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));

    exit when not exists (
      select 1 from public.rooms where code = v_code
    );
  end loop;

  insert into public.rooms (
    name, code, start_date, end_date, created_by
  )
  values (
    trim(p_name), v_code, p_start, p_end, auth.uid()
  )
  returning * into v_room;

  insert into public.room_members (
    room_id, user_id, display_name
  )
  values (
    v_room.id, auth.uid(), trim(p_display_name)
  )
  returning * into v_member;

  return json_build_object(
    'room_id', v_room.id,
    'code', v_room.code,
    'member_id', v_member.id
  );
end;
$$;

-- 7. ルーム参加関数

create or replace function public.join_room(
  p_code text,
  p_display_name text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms;
  v_member public.room_members;
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'セッションを確認できません。';
  end if;

  if p_display_name is null
    or char_length(trim(p_display_name)) not between 1 and 30
  then
    raise exception '参加者名は1〜30文字で入力してください。';
  end if;

  select * into v_room
  from public.rooms
  where code = upper(trim(p_code))
  for update;

  if not found then
    raise exception 'ルームコードが見つかりません。';
  end if;

  select count(*) into v_count
  from public.room_members
  where room_id = v_room.id;

  select * into v_member
  from public.room_members
  where room_id = v_room.id
    and user_id = auth.uid();

  if not found then
    if v_count >= 10 then
      raise exception 'このルームは満員です（最大10人）。';
    end if;

    insert into public.room_members (
      room_id, user_id, display_name
    )
    values (
      v_room.id, auth.uid(), trim(p_display_name)
    )
    returning * into v_member;
  else
    update public.room_members
    set display_name = trim(p_display_name)
    where id = v_member.id
    returning * into v_member;
  end if;

  return json_build_object(
    'room_id', v_room.id,
    'member_id', v_member.id
  );
end;
$$;

-- 8. 日程回答関数

create or replace function public.set_availability(
  p_room_id uuid,
  p_date date,
  p_answer text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.room_members;
  v_room public.rooms;
begin
  if auth.uid() is null then
    raise exception 'セッションを確認できません。';
  end if;

  select * into v_room
  from public.rooms
  where id = p_room_id;

  if not found then
    raise exception 'ルームが見つかりません。';
  end if;

  if p_date is null
    or p_date < v_room.start_date
    or p_date > v_room.end_date
  then
    raise exception '調整期間外の日付です。';
  end if;

  select * into v_member
  from public.room_members
  where room_id = p_room_id
    and user_id = auth.uid();

  if not found then
    raise exception 'このルームの参加者ではありません。';
  end if;

  if p_answer is null then
    delete from public.availability
    where member_id = v_member.id
      and date = p_date;

  elsif p_answer in ('○','△','×') then
    insert into public.availability (
      room_id, member_id, date, answer
    )
    values (
      p_room_id, v_member.id, p_date, p_answer
    )
    on conflict (member_id, date)
    do update set
      answer = excluded.answer,
      updated_at = now();

  else
    raise exception '回答は○・△・×から選択してください。';
  end if;
end;
$$;

-- 9. 関数の実行権限

revoke all on function public.create_room(text,date,date,text)
from public;

revoke all on function public.join_room(text,text)
from public;

revoke all on function public.set_availability(uuid,date,text)
from public;

revoke all on function public.is_room_member(uuid)
from public;

grant execute on function public.create_room(text,date,date,text)
to anon, authenticated;

grant execute on function public.join_room(text,text)
to anon, authenticated;

grant execute on function public.set_availability(uuid,date,text)
to anon, authenticated;

grant execute on function public.is_room_member(uuid)
to anon, authenticated;

-- =========================================
-- SQL構築完了
-- Realtime設定はDashboardで別途行います。
-- =========================================
