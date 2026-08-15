# Emacs を最新 macOS のアプリライフサイクルに追従させる

対象: GNU Emacs 30.2 (`emacs-30.2` タグ)

> **本書は調査結果 (何が足りないか) をまとめたもの。**
> 実際の作業手順は **[`roadmap.md`](./roadmap.md)** を参照。
> 着手する場合はそちらから読むこと。

## 結論を先に

**Objective-C のまま進められる。Swift は不要。**

- AppKit の API は Objective-C から 100% 利用できる。ライフサイクル系に
  Swift 専用 API は一つもない。すべて通常の ObjC メソッド / 通知である。
- Swift を挟むと `docs/swift-migration.md` に列挙したブロッカー
  (`lisp.h` が import 不能、`DEFUN` が `globals.h` から消える、`longjmp` が
  Swift フレームを飛び越える、GNUstep 放棄による恒久フォーク化) を
  **すべて背負ったうえで、得られる機能は増えない**。
- さらに重要な点として、ObjC で書けば **上流 GNU Emacs に還元できる**。
  Swift では原理的に不可能 (GNU プロジェクトは実装言語として C 系以外を
  受け付けない)。長期の追従コストが根本的に変わる。

そして本題。**最新ライフサイクルへの追従を阻んでいるのは言語ではなく、
Emacs のランループ構造である。** これは Swift 化しても 1 ミリも改善しない。

---

## 1. 本当の障害: Emacs は通常の AppKit ランループを回していない

### 1.1 実際の構造

- `NSApplicationMain` は使わない。`nsterm.m:5649` で `[EmacsApp sharedApplication]`
  を呼ぶだけ。
- イベント処理は Emacs 側が主導する。`ns_read_socket_1` (`nsterm.m:4743`) と
  `ns_select_1` (`nsterm.m:4835`) が **`[NSApp run]` を短時間だけ回して抜ける**
  という動作を繰り返す。
- 抜ける手段は自分宛に `NX_APPDEFINED` イベントを投げること
  (`ns_send_appdefined`, `nsterm.m:4663`)。これを `-[EmacsApp sendEvent:]`
  (`nsterm.m:5988`, 説明コメントは `nsterm.m:6035`) が捕まえてループを止める。
- `-[EmacsApp run]` のオーバーライド (`nsterm.m:5928`) は macOS 10.9 専用の
  回避策で、現行 macOS では `[super run]` に素通しされる。

### 1.2 何が起きるか

**AppKit のデリゲートコールバックと NSWorkspace 通知は、Emacs が
`[NSApp run]` の中にいる間しか配送されない。** つまり「入力待ちの間だけ」。

Lisp を実行している間 (長い font-lock、GC、同期プロセス、`sleep-for`、
Tramp のブロッキング I/O) は一切ポンプしないため、macOS からは
**応答なしのアプリに見える**。

これが効いてくるのが、**締切のあるライフサイクルイベント**である:

| イベント | 締切 | 現状 |
| --- | --- | --- |
| ログアウト / 再起動 / シャットダウン | 数秒〜十数秒 | 応答できないと「Emacs がログアウトを中断しました」または強制終了 |
| `applicationShouldTerminate:` への応答 | あり | `NSTerminateLater` + `replyToApplicationShouldTerminate:` を**使っていない** (下記 2.2) |
| App Nap 移行 | — | 抑止していないためバックグラウンドでタイマー・プロセスが絞られる |
| スリープ直前の後始末 | あり | そもそも通知を購読していない |

**この 1 節が作業の本丸で、かつ言語非依存。** ここに手を付けずにデリゲート
メソッドだけ足しても、肝心の場面 (ログアウト時、スリープ直前) で呼ばれない。

### 1.3 取りうる方針

1. **ポンプ頻度の底上げ** — Emacs の `Vinhibit_quit` / QUIT チェック地点や
   `atimer` から定期的に `ns_read_socket_1(..., YES)` 相当を回す。
   影響範囲は小さいが、根本解決にはならない。
2. **締切のあるイベントだけ別扱い**：`applicationShouldTerminate:` で
   `NSTerminateLater` を返し、Lisp 側の保存処理完了後に
   `replyToApplicationShouldTerminate:YES` を呼ぶ。
   ただし、2026-08-12 の実機試作では AppKit の終了待機ループから Lisp へ制御が戻らず、
   保存処理を開始できなかった。
   この方法はランループ改修と組み合わせる必要がある。
3. **App Nap を明示的に抑止** — `[[NSProcessInfo processInfo]
   beginActivityWithOptions:NSActivityUserInitiated reason:@"..."]`。
   数行で効果が出る。

推奨は 3 → 1 → 2 の順。

---

## 2. Emacs 30.2 の実装状況 (実測)

### 2.1 実装済みのデリゲートメソッド (`nsterm.m`)

| メソッド | 行 |
| --- | ---: |
| `applicationDidFinishLaunching:` | 6161 |
| `applicationSupportsSecureRestorableState:` | 6242 |
| `applicationShouldTerminate:` | 6287 |
| `application:openFile:` | 6314 |
| `application:openTempFile:` | 6323 |
| `application:openFileWithoutUI:` | 6332 |
| `application:openFiles:` | 6340 |
| `applicationDockMenu:` | 6357 |
| `applicationWillBecomeActive:` | 6364 |
| `applicationDidBecomeActive:` | 6370 |
| `applicationDidResignActive:` | 6384 |

`NSNotificationCenter` の購読は Cocoa では **1 件だけ**
(`NSAntialiasThresholdChangedNotification`, `nsterm.m:6176`)。
`nsterm.m:5918` の画面構成変更の購読は `#ifdef NS_IMPL_GNUSTEP` 限定で、
Cocoa は `CGDisplayRegisterReconfigurationCallback` (`nsterm.m:5475`) を使う。
これは妥当な代替なので対応不要。

### 2.2 終了パスが二重で、しかも現代的な作法を使っていない

- `-[EmacsApp terminate:]` (`nsterm.m:6248`) が `NSApplication` の `terminate:` を
  オーバーライドし、`KEY_NS_POWER_OFF` 非キーイベントを Emacs のキーバッファへ
  投入する。`lisp/term/ns-win.el:174` で `[ns-power-off]` →
  `save-buffers-kill-emacs` に束縛されている。
  **`[super terminate:]` は呼ばない** (実測: `super terminate` は 0 件)。
- 一方 `applicationShouldTerminate:` (`nsterm.m:6287`) も存在し、
  `ns-confirm-quit` を見て独自の `NSAlert` を出す。
- **`NSTerminateLater` と `replyToApplicationShouldTerminate:` はどちらも 0 件。**
  ログアウト時に「保存処理をしているので待ってほしい」と AppKit に伝える
  正規の手段を使っていない。
  ただし、通常の Quit Apple Event は既存の `KEY_NS_POWER_OFF` 経由で正常終了することを
  2026-08-12 に実機確認した。

この不足は §1.3 の方針 2 だけでは直せない。
`NSTerminateLater` の待機中に Lisp を実行できるよう、ランループ側の対応が先に必要になる。

### 2.3 未実装のもの (すべて実測で 0 件)

`applicationShouldHandleReopen:hasVisibleWindows:` も未実装だが、対応対象にはしない。
2026-08-11 の実機検証では、最小化したフレームは reopen Apple Event に対する
AppKit の標準動作で復帰した。
Emacs Lisp の `make-frame-invisible` で完全に不可視化したフレームが Dock アイコンの
クリックで復帰しないのは、明示的な不可視状態を維持する意図的な動作である。
このメソッドを追加して不可視フレームを自動的に可視化すると、呼び出し側の指定を
取り消してしまうため、対応タスクを中止した。

| API | 影響 |
| --- | --- |
| `application:openURLs:` | `application:openFile(s):` は macOS 10.13 で非推奨。URL スキーム (org-protocol 等) を受けられない |
| `applicationWillTerminate:` | 終了直前の後始末フックがない |
| `NSWorkspaceWillSleepNotification` / `DidWakeNotification` | スリープ・復帰を検知できない (タイマー、ネットワーク接続の張り直し) |
| `NSWorkspaceWillPowerOffNotification` | システム側のログアウト・電源断を検知できない |
| `NSWorkspaceSessionDidResignActiveNotification` | ファストユーザスイッチに追従できない |
| `viewDidChangeEffectiveAppearance` / `effectiveAppearance` の KVO | **ダークモードの自動切替が Lisp に伝わらない。** 30.2 は `ns-appearance` フレームパラメータから**設定する**だけ (`-[EmacsWindow setAppearance]`, `nsterm.m:9867`) で、システム側の変更を**観測していない** |
| `beginActivityWithOptions:` (App Nap) | バックグラウンドで絞られる |
| `disableSuddenTermination` | 既定が無効なので現状は安全側だが、明示すべき |
| `encodeRestorableStateWithCoder:` / `restoreStateWithCoder:` | `applicationSupportsSecureRestorableState:` は `YES` を返す (`nsterm.m:6242`) のに、**実際の状態復元は未実装**。macOS 14 の警告を黙らせているだけ |
| `applicationProtectedDataDidBecomeAvailable:` / `WillBecomeUnavailable:` | FileVault ロック中のファイルアクセスを扱えない |

### 2.4 Info.plist の不足 (`nextstep/templates/Info.plist.in`)

**Emacs の C コードに一切触らずに直せる領域。最も安上がり。**

現状あるもの: `NSPrincipalClass=EmacsApp`、`CFBundleURLTypes` (`mailto` のみ)、
`NSAppleScriptEnabled`、各種 UsageDescription、`NSAppTransportSecurity`。

不足しているもの:

| キー | 用途 |
| --- | --- |
| `LSMinimumSystemVersion` | 最小 macOS の明示。未指定だと古い OS で起動して落ちる |
| `NSHighResolutionCapable` | Retina 対応の明示 |
| `NSSupportsAutomaticTermination` | 明示 (既定 NO のまま維持でよいが意図を残す) |
| `NSSupportsSuddenTermination` | 同上。未保存バッファがある以上 NO を明示すべき |
| `NSSupportsAutomaticGraphicsSwitching` | dGPU 搭載機での電力 |
| `CFBundleVersion` | 現在 `9.0` 固定。ビルド番号になっておらず配布・notarization で問題 |
| `CFBundleURLTypes` の拡充 | `org-protocol` / `emacs` スキーム。§2.3 の `openURLs:` と対で入れる |

後回し (`roadmap.md` の Phase 4):
`LSApplicationCategoryType` (Mac App Store 配布に必須)、
`NSUserActivityTypes` (Handoff)、サンドボックス関連のエンタイトルメント。

---

## 3. 進め方

**作業手順は [`roadmap.md`](./roadmap.md) に分離した。** 着手する場合はそちらを見ること。
ここでは全体像だけ示す。

| Phase | 内容 | 根拠 |
| --- | --- | --- |
| 0 | Emacs 30.2 へのリベース | `swift-migration.md` §0 |
| 1 | Info.plist の整備 (Emacs のコードに触らない) | §2.4 |
| 2 | 不足しているデリゲートメソッドの追加 | §2.3 |
| 3 | ランループ — 本丸 | §1 |
| 4 | 後回し: Mac App Store、状態復元、Handoff、iPadOS、Swift | §2.3, §2.4 |

Phase 2 の Lisp への通知は既存の `KEY_NS_POWER_OFF` と同じ流儀
(`nsterm.m:6248` の非キーイベント投入 + `ns-win.el` でのキーバインド) を踏襲するか、
`DEFVAR_LISP` でフック変数を追加する。
**いずれも `nsterm.m` / `ns-win.el` 内で完結するため、`swift-migration.md` §2.2 で
問題にした `make-docfile` の制約には抵触しない。**

## 4. 上流還元について

Phase 1〜3 は **すべて上流 GNU Emacs に還元しうる**。
Swift 移行との決定的な違いがここにある:

- GNUstep を壊さない (`#ifdef NS_IMPL_COCOA` で囲めば済む)
- 実装言語が Objective-C のまま
- 機能追加として筋が通っており、`bug-gnu-emacs` / `emacs-devel` で議論可能

条件として、15 行を超える変更には FSF への著作権譲渡 (copyright assignment) が
必要になる。フォークとして抱え続けるコストと比べれば安い。

方針として、**本リポジトリ固有にすべきもの** (Info.plist、パッケージング、
署名・notarization) と、**上流に出すもの** (デリゲートメソッド、ランループ)
を最初から分けてコミットしておくと後が楽になる。

---

## 5. Swift について

`docs/swift-migration.md` に詳細を残してある。要点のみ:

- NS レイヤ 25,464 行のうち ObjC クラス実装は 6,713 行 (26%) しかなく、
  残り 74% は Emacs コアの C。移行対象は思ったより小さいが、
- `lisp.h` は Swift から import できない (関数形式マクロ 165 個、
  `extern inline` 282 個)
- `DEFUN` / `DEFVAR` を `.swift` に移すと `globals.h` と `etc/DOC` から消える
  (`make-docfile` は `.c` と `.m` しか走査しない)
- Emacs のエラーは `longjmp` で飛ぶ (`eval.c:1290` ほか)。Swift フレームを
  跨ぐ `longjmp` は未定義動作で、ARC の release と `defer` がスキップされる
- GNUstep 条件分岐 237 箇所を落とすことになり、恒久フォーク化する

**本件の目的 (最新ライフサイクルへの追従) に対して、Swift はコストのみで
リターンがない。** 将来 Swift 化を検討するとしても、Phase 0〜3 を
Objective-C で終えた後、`EmacsBell` (85 行、Lisp にも `struct frame` にも
触らない) のような葉のクラスで実験する程度に留めるのが妥当。
