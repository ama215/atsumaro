-- あつまろ DB schema
-- Supabase SQL Editorで全体を実行してください。

create extension if not exists pgcrypto;

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
  foreign key(member_id, room_id) references public.room_members(id, room_id) on delete cascade
);

create index if not exists room_members_room_idx on public.room_members(room_id);
create index if not exists availability_room_date_idx on public.availability(room_id, date);

alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.availability enable row level security;

grant select on public.rooms, public.room_members, public.availability to anon, authenticated;

create or replace function public.is_room_member(p_room_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from room_members where room_id=p_room_id and user_id=auth.uid()) $$;

drop policy if exists "members can read rooms" on public.rooms;
create policy "members can read rooms" on public.rooms for select using (public.is_room_member(id));
drop policy if exists "members can read room members" on public.room_members;
create policy "members can read room members" on public.room_members for select using (public.is_room_member(room_id));
drop policy if exists "members can read availability" on public.availability;
create policy "members can read availability" on public.availability for select using (public.is_room_member(room_id));

create or replace function public.create_room(p_name text, p_start date, p_end date, p_display_name text)
returns json language plpgsql security definer set search_path = public
as $$
declare v_room rooms; v_code text; v_member room_members;
begin
  if auth.uid() is null then raise exception 'セッションを確認できません。'; end if;
  if length(trim(p_name))=0 or length(trim(p_display_name))=0 then raise exception '名前とルーム名を入力してください。'; end if;
  if p_end < p_start or p_end-p_start > 124 then raise exception '調整期間は1〜125日以内にしてください。'; end if;
  loop
    v_code := upper(substr(encode(gen_random_bytes(6),'hex'),1,4)) || '-' || upper(substr(encode(gen_random_bytes(6),'hex'),1,4));
    exit when not exists(select 1 from rooms where code=v_code);
  end loop;
  insert into rooms(name,code,start_date,end_date,created_by) values(trim(p_name),v_code,p_start,p_end,auth.uid()) returning * into v_room;
  insert into room_members(room_id,user_id,display_name) values(v_room.id,auth.uid(),trim(p_display_name)) returning * into v_member;
  return json_build_object('room_id',v_room.id,'code',v_room.code,'member_id',v_member.id);
end; $$;

create or replace function public.join_room(p_code text, p_display_name text)
returns json language plpgsql security definer set search_path = public
as $$
declare v_room rooms; v_member room_members; v_count integer;
begin
  if auth.uid() is null then raise exception 'セッションを確認できません。'; end if;
  if length(trim(p_display_name))=0 then raise exception '名前を入力してください。'; end if;
  select * into v_room from rooms where code=upper(trim(p_code));
  if not found then raise exception 'ルームコードが見つかりません。'; end if;
  select count(*) into v_count from room_members where room_id=v_room.id;
  select * into v_member from room_members where room_id=v_room.id and user_id=auth.uid();
  if not found then
    if v_count >= 10 then raise exception 'このルームは満員です（最大10人）。'; end if;
    insert into room_members(room_id,user_id,display_name) values(v_room.id,auth.uid(),trim(p_display_name)) returning * into v_member;
  else
    update room_members set display_name=trim(p_display_name) where id=v_member.id returning * into v_member;
  end if;
  return json_build_object('room_id',v_room.id,'member_id',v_member.id);
end; $$;

create or replace function public.set_availability(p_room_id uuid, p_date date, p_answer text)
returns void language plpgsql security definer set search_path = public
as $$
declare v_member room_members; v_room rooms;
begin
  select * into v_room from rooms where id=p_room_id;
  if not found then raise exception 'ルームが見つかりません。'; end if;
  if p_date < v_room.start_date or p_date > v_room.end_date then raise exception '調整期間外の日付です。'; end if;
  select * into v_member from room_members where room_id=p_room_id and user_id=auth.uid();
  if not found then raise exception 'このルームの参加者ではありません。'; end if;
  if p_answer is null then
    delete from availability where member_id=v_member.id and date=p_date;
  elsif p_answer in ('○','△','×') then
    insert into availability(room_id,member_id,date,answer) values(p_room_id,v_member.id,p_date,p_answer)
    on conflict(member_id,date) do update set answer=excluded.answer,updated_at=now();
  else raise exception '回答は○・△・×から選択してください。';
  end if;
end; $$;

grant execute on function public.create_room(text,date,date,text) to anon, authenticated;
grant execute on function public.join_room(text,text) to anon, authenticated;
grant execute on function public.set_availability(uuid,date,text) to anon, authenticated;
grant execute on function public.is_room_member(uuid) to anon, authenticated;

-- Realtime: Supabase Dashboard > Database > Replication で
-- rooms / room_members / availability をRealtime対象にしてください。
