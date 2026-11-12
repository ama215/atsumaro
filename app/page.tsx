"use client";

import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";

type Room = { id: string; name: string; code: string; start_date: string; end_date: string; created_at: string };
type Member = { id: string; display_name: string; user_id: string; joined_at: string };
type ResponseRow = { member_id: string; date: string; answer: "○" | "△" | "×" };

const fmt = (s: string) => new Date(`${s}T00:00:00`).toLocaleDateString("ja-JP", { month: "numeric", day: "numeric", weekday: "short" });
const dateRange = (start: string, end: string) => {
  const out: string[] = [];
  const d = new Date(`${start}T00:00:00`);
  const last = new Date(`${end}T00:00:00`);
  while (d <= last && out.length < 125) { out.push(d.toISOString().slice(0, 10)); d.setDate(d.getDate() + 1); }
  return out;
};

export default function Home() {
  const [ready, setReady] = useState(false);
  const [name, setName] = useState("");
  const [roomName, setRoomName] = useState("");
  const [start, setStart] = useState("2026-12-01");
  const [end, setEnd] = useState("2027-03-31");
  const [code, setCode] = useState("");
  const [room, setRoom] = useState<Room | null>(null);
  const [members, setMembers] = useState<Member[]>([]);
  const [responses, setResponses] = useState<ResponseRow[]>([]);
  const [myMemberId, setMyMemberId] = useState("");
  const [view, setView] = useState<"home" | "room">("home");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [month, setMonth] = useState("2026-12");
  const [filter, setFilter] = useState<"all" | "everyone" | "mine">("all");

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const invitedCode = params.get("code");
    if (invitedCode) setCode(invitedCode.toUpperCase());
    const init = async () => {
      if (!supabase) { setReady(true); return; }
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) await supabase.auth.signInAnonymously();
      setReady(true);
    };
    init();
  }, []);

  const loadRoom = async (roomId: string) => {
    if (!supabase) return;
    const { data: r } = await supabase.from("rooms").select("*").eq("id", roomId).single();
    if (!r) return;
    setRoom(r as Room);
    const [{ data: m }, { data: a }] = await Promise.all([
      supabase.from("room_members").select("*").eq("room_id", roomId).order("joined_at"),
      supabase.from("availability").select("*").eq("room_id", roomId)
    ]);
    setMembers((m || []) as Member[]);
    setResponses((a || []) as ResponseRow[]);
    const { data: { user } } = await supabase.auth.getUser();
    const mine = (m || []).find((x: Member) => x.user_id === user?.id);
    setMyMemberId(mine?.id || "");
    setMonth(r.start_date.slice(0, 7));
    setView("room");
    history.replaceState(null, "", `?code=${r.code}`);
  };

  const createRoom = async () => {
    if (!supabase) return setMessage("Supabaseの設定が必要です。READMEの手順を確認してください。");
    if (!roomName.trim() || !name.trim()) return setMessage("ルーム名とあなたの名前を入力してください。");
    if (start > end) return setMessage("終了日は開始日以降にしてください。");
    setBusy(true); setMessage("");
    const { data, error } = await supabase.rpc("create_room", { p_name: roomName.trim(), p_start: start, p_end: end, p_display_name: name.trim() });
    setBusy(false);
    if (error) return setMessage(error.message);
    await loadRoom(data.room_id);
  };

  const joinRoom = async () => {
    if (!supabase) return setMessage("Supabaseの設定が必要です。READMEの手順を確認してください。");
    if (!name.trim() || !code.trim()) return setMessage("名前とルームコードを入力してください。");
    setBusy(true); setMessage("");
    const { data, error } = await supabase.rpc("join_room", { p_code: code.trim().toUpperCase(), p_display_name: name.trim() });
    setBusy(false);
    if (error) return setMessage(error.message);
    await loadRoom(data.room_id);
  };

  useEffect(() => {
    if (!supabase || !room?.id) return;
    const channel = supabase.channel(`room-${room.id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "room_members", filter: `room_id=eq.${room.id}` }, () => loadRoom(room.id))
      .on("postgres_changes", { event: "*", schema: "public", table: "availability", filter: `room_id=eq.${room.id}` }, () => loadRoom(room.id))
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [room?.id]);

  const dates = useMemo(() => room ? dateRange(room.start_date, room.end_date) : [], [room]);
  const allAvailable = useMemo(() => dates.filter(d => members.length > 0 && members.every(m => responses.some(a => a.member_id === m.id && a.date === d && a.answer === "○"))), [dates, members, responses]);
  const monthDates = dates.filter(d => d.startsWith(month));
  const monthLabel = new Date(`${month}-01T00:00:00`).toLocaleDateString("ja-JP", { year: "numeric", month: "long" });
  const changeAnswer = async (date: string, answer: "○" | "△" | "×") => {
    if (!supabase || !myMemberId || !room) return;
    const old = responses.find(a => a.member_id === myMemberId && a.date === date);
    const next = old?.answer === answer ? null : answer;
    setResponses(prev => next ? [...prev.filter(a => !(a.member_id === myMemberId && a.date === date)), { member_id: myMemberId, date, answer: next }] : prev.filter(a => !(a.member_id === myMemberId && a.date === date)));
    const { error } = await supabase.rpc("set_availability", { p_room_id: room.id, p_date: date, p_answer: next });
    if (error) setMessage(error.message);
  };

  if (!ready) return <main className="loading">あつまろを準備しています…</main>;

  return <main className="shell">
    <header className="topbar"><a className="logo" onClick={() => { setView("home"); setRoom(null); history.replaceState(null, "", "/"); }}>あつまろ</a>
      {view === "room" && <nav><button onClick={() => setFilter("everyone")}>全員○の日</button><button onClick={() => setFilter("all")}>予定を入力</button></nav>}
    </header>

    {view === "home" ? <section className="hero">
      <div className="intro">
        <h1>予定調整は、<br/>コードを送るだけ。</h1>
        <div className="steps"><p><b>1</b>　幹事がルームを作成</p><p><b>2</b>　LINEでコードを共有</p><p><b>3</b>　参加者がルームに参加</p><p><b>4</b>　全員で予定を入力</p></div>
      </div>
      <div className="panel">
        <h2>ルームを作成</h2>
        <label>あなたの名前<input value={name} onChange={e=>setName(e.target.value)} placeholder="例：田中"/></label>
        <label>ルーム名<input value={roomName} onChange={e=>setRoomName(e.target.value)} placeholder="例：忘年会 2026"/></label>
        <div className="datefields"><label>候補期間（開始）<input type="date" value={start} onChange={e=>setStart(e.target.value)}/></label><label>候補期間（終了）<input type="date" value={end} onChange={e=>setEnd(e.target.value)}/></label></div>
        <button className="primary" disabled={busy} onClick={createRoom}>{busy ? "作成中…" : "ルームを作成する"}</button>
        <div className="or">またはコードで参加</div>
        <label>ルームコード<input value={code} onChange={e=>setCode(e.target.value.toUpperCase())} placeholder="例：K7QX-42M9"/></label>
        <button className="secondary" disabled={busy} onClick={joinRoom}>ルームに参加する</button>
        {message && <p className="message">{message}</p>}
      </div>
    </section> : room && <section className="roompage">
      <div className="roomhead"><div><p className="eyebrow">ROOM</p><h1>{room.name}</h1><p>{fmt(room.start_date)} 〜 {fmt(room.end_date)}</p></div><div className="invite"><span>招待コード</span><strong>{room.code}</strong><button onClick={()=>navigator.clipboard.writeText(`${location.origin}/?code=${room.code}`)}>招待リンクをコピー</button><button onClick={()=>{const u=`https://line.me/R/msg/text/?${encodeURIComponent(`あつまろに参加してね！\n${location.origin}/?code=${room.code}`)}`;location.href=u;}}>LINEで共有</button></div></div>
      <div className="summary"><h2>全員○の日 <strong>{allAvailable.length}日</strong></h2>{allAvailable.length ? <div className="availablelist">{allAvailable.map(d=><span key={d}>{fmt(d)}</span>)}</div> : <p>現在、全員○の日はありません。</p>}</div>
      <div className="calendar panel">
        <div className="calhead"><button onClick={()=>setMonth(m=>{const d=new Date(`${m}-01T00:00:00`);d.setMonth(d.getMonth()-1);return d.toISOString().slice(0,7)})}>‹</button><h2>{monthLabel}</h2><button onClick={()=>setMonth(m=>{const d=new Date(`${m}-01T00:00:00`);d.setMonth(d.getMonth()+1);return d.toISOString().slice(0,7)})}>›</button></div>
        <div className="days">{["日","月","火","水","木","金","土"].map(x=><b key={x}>{x}</b>)}</div>
        <div className="grid">{(() => { const first = new Date(`${month}-01T00:00:00`).getDay(); const count = new Date(Number(month.slice(0,4)),Number(month.slice(5,7)),0).getDate(); return [...Array(first).fill(null),...Array(count).fill(0).map((_,i)=>`${month}-${String(i+1).padStart(2,"0")}`)].map((d,i)=>{ if(!d || !dates.includes(d)) return <div className="emptyday" key={`e${i}`}/>; const yes=responses.filter(a=>a.date===d&&a.answer==="○").length; const mine=responses.find(a=>a.date===d&&a.member_id===myMemberId)?.answer; return <button key={d} className={`day ${allAvailable.includes(d)?"everyone":""}`} onClick={()=>setFilter("all")}><b>{Number(d.slice(-2))}</b><span>{allAvailable.includes(d)?"○":yes>0?`${yes}/${members.length}○`:"—"}</span><small>{mine || "未回答"}</small></button>; }); })()}</div>
      </div>
      <div className="panel response">
        <h2>メンバーの予定を入力</h2><p className="muted">○・△・×を選択すると、全員の画面に反映されます。</p>
        <div className="legend"><span>🟢 ○ 参加できる</span><span>🟠 △ 未定</span><span>🔴 × 参加できない</span></div>
        <div className="tablewrap"><table><thead><tr><th>メンバー</th>{monthDates.map(d=><th key={d}>{fmt(d)}</th>)}</tr></thead><tbody>{members.map(m=><tr key={m.id}><th>{m.display_name}{m.id===myMemberId?"（あなた）":""}</th>{monthDates.map(d=>{const a=responses.find(x=>x.member_id===m.id&&x.date===d)?.answer;return <td key={d}>{m.id===myMemberId?<div className="choices">{(["○","△","×"] as const).map(v=><button className={`choice ${a===v?"selected "+(v==="○"?"yes":v==="△"?"maybe":"no"):""}`} onClick={()=>changeAnswer(d,v)} key={v}>{v}</button>)}</div>:<span className={`answer ${a==="○"?"yes":a==="△"?"maybe":a==="×"?"no":""}`}>{a||"—"}</span>}</td>;})}</tr>)}</tbody></table></div>
      </div>
      <p className="roomfoot">参加者 {members.length}/10人　・　回答は自動で共有されます</p>
      {message && <p className="message">{message}</p>}
    </section>}
    <footer>あつまろ　© 2026</footer>
  </main>;
}
