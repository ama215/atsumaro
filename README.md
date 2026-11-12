# あつまろ — Netlify公開準備版

Next.js 15 + Supabaseの日程調整Webアプリです。NetlifyではGitHub連携で公開します。

## GitHubへのアップロード
1. ZIPを展開します。
2. GitHubで空のPrivate repository（例: atsumaro）を作成します。
3. `atsumaro`フォルダの中身をGitHubの `Add file` → `Upload files` からアップロードします。
4. リポジトリ直下に `package.json`、`app`、`lib`、`supabase` が並ぶことを確認します。

## Supabase
1. Supabaseでプロジェクトを作成します。
2. AuthenticationでAnonymous Sign-Insを有効にします。
3. SQL Editorで `supabase/schema.sql` 全体を実行します。
4. Realtime対象に `room_members` と `availability` を追加します。
5. Project URLとanon/publishable keyを控えます。service_roleキーは使わないでください。

## Netlify
1. Netlifyで `Add new project` → `Import an existing project` を選び、GitHubを接続します。
2. `atsumaro`リポジトリを選択します。
3. Build commandは `npm run build`。Base directoryは空欄。Next.jsの自動検出・自動設定を優先し、Publish directoryに `dist` / `out` を指定しません。
4. Environment variablesに以下を設定します。
   - `NEXT_PUBLIC_SUPABASE_URL` = Supabase Project URL
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY` = Supabase anon / publishable key
5. Deployし、環境変数を後から追加した場合は再デプロイします。

## 注意
このZIPは公開準備用の初期版です。公開前に複数端末でルーム作成・参加・回答同期を確認してください。画面上は名前だけですが、裏側ではSupabase匿名認証を使用します。ブラウザデータ消去などで匿名セッションが失われると、同じ参加者として復帰できない場合があります。招待コードを知る人は参加できるため、共有範囲に注意してください。
