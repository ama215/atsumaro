import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "あつまろ｜みんなの日程調整",
  description: "ルームコードを共有するだけで、みんなの予定を簡単に調整できます。"
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ja"><body>{children}</body></html>;
}
