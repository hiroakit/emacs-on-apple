# 実装ロードマップ (作業手引き)

**目的: Emacs を最新 macOS のアプリライフサイクルに追従させる。**

このドキュメントは作業を引き継ぐ人 (人間・AI エージェントを問わない) が
Phase 0 から順に着手できるように書かれた手順書です。
背景の調査結果は次の 2 つに分けてあります。必要になった時点で参照してください。

| ドキュメント | 内容 | いつ読むか |
| --- | --- | --- |
| [`macos-lifecycle.md`](./macos-lifecycle.md) | Emacs 30.2 のライフサイクル実装状況の実測、欠けている API の一覧 | Phase 2 / 3 の着手前 |
| [`swift-migration.md`](./swift-migration.md) | Swift 化の調査記録。**現行計画ではない** | 「Swift でやるべきでは?」と思ったとき |

---

## 0. 作業を始める前に

### 0.1 前提となる結論 (再検討不要)

以下は調査済みの決定事項です。作業中にこれを覆さないでください。
理由が必要なら上表のドキュメントを参照してください。

- **Objective-C のまま進める。Swift 化はしない。**
  AppKit のライフサイクル API に Swift 専用のものは存在しない。
  Swift はコストのみでリターンがない。
- **NS レイヤの「素の C」部分 (約 18,700 行) には手を入れない。**
  `nsfns.m` の 98%、`nsfont.m` / `macfont.m` / `nsselect.m` の 100% は
  Emacs コアの一部であり、本件の対象外。
- **GNUstep を壊さない。** 新規コードは `#ifdef NS_IMPL_COCOA` で囲む。
  これを守れば上流 GNU Emacs に還元できる (§5 参照)。
- **Mac App Store 対応は後回し** (Phase 4)。
  `LSApplicationCategoryType`、サンドボックス、エンタイトルメントの見直しは
  Phase 3 まで終わってから着手する。

### 0.2 やってはいけないこと

- `src/nsterm.m` などの既存ロジックを「ついでに整理する」こと。
  上流との差分が増えるほど 30.3 / 31 系への追従が苦しくなる。**変更は最小限に。**
- チェックサムやバージョン番号を**推測で書くこと**。
  必ず実際に取得した値を使う (§1.2)。
- 本書中の行番号を検証せずに信じること。
  すべて `emacs-30.2` タグ時点の実測値だが、パッチ適用後はずれる。
  **必ず `grep` で現在位置を確認してから編集すること。**

### 0.3 Emacs 30.2 のソース取得

`ftp.gnu.org` は環境によってはネットワークポリシーで遮断されている。
その場合は GitHub ミラーを使う (調査時はこちらを使用した):

```sh
git clone --depth 1 --branch emacs-30.2 \
  https://github.com/emacs-mirror/emacs.git
```

ただし **ビルドには公式 tarball を使うこと**。git ツリーは `configure` が
未生成で、`autogen.sh` の実行が必要になり再現性が落ちる。
ミラーはコード調査用と割り切る。

---

## Phase 0: Emacs 30.2 へのリベース

**これが終わるまで Phase 1 以降は検証できない。最優先。**

現在の `build.sh` は Emacs 26.3 固定。パッチ 5 枚も 26.3 前提で、
30.2 にはほぼそのまま当たらない。

### 0-A. パッチの棚卸し

| ファイル | 対応 |
| --- | --- |
| `00-bump-copyright-year.patch` | **作り直し**。`configure.ac` の対象行が移動している |
| `01-remove-blessmail.patch` | **要再確認**。`Makefile.in` の構造が変化 |
| `02-provisional-emacs26.3-unexmacosx.c.patch` | **削除**。理由は下記 |
| `03-bump-emacs-version.patch` | **作り直し** |
| `04-macos-big-sur.patch` | **要再評価**。`src/macim.h` を新規追加するもので ns-inline-patch 前提 |
| `ns-inline-patch` (`emacs-25.2-inline.patch`) | **要再評価**。下記 |

**`02-...unexmacosx` を削除してよい根拠**:
30.2 は `--with-dumping=pdumper` が既定 (`configure.ac:467`)。
`unexmacosx.o` がリンクされるのは `--with-dumping=unexec` を明示した場合のみ
(`configure.ac:2252`)。`src/unexmacosx.c` はツリーに残っているが使われない。

**ns-inline-patch の再評価**:
30.2 本体に `NSTextInputClient` の実装がある (`nsterm.m:7081`–`7257`)。
`workingText` の管理 (`nsterm.m:7161`–`7205`)、`ns-working-text` の `DEFVAR`
(`nsterm.m:11072`)、Lisp 側のオーバーレイ表示 (`lisp/term/ns-win.el:307`–`317` の
`ns-put-working-text` / `ns-insert-working-text`) が揃っている。
**まず素の 30.2 をビルドして日本語入力の挙動を実機確認し、
パッチが本当に必要か判断すること。** 不要ならパッチごと削除でき、
`04-macos-big-sur.patch` も同時に不要になる。

### 0-B. `build.sh` に `emacs30` を追加

`build_emacs26()` を複製して `build_emacs30()` を作る。

1. `pkgver="30.2"`
2. **sha256 を実際に取得する。** 推測しないこと:
   ```sh
   curl -LO https://ftp.gnu.org/gnu/emacs/emacs-30.2.tar.xz
   shasum -a 256 emacs-30.2.tar.xz
   ```
   可能なら `.sig` での GPG 検証のほうが望ましい:
   ```sh
   curl -LO https://ftp.gnu.org/gnu/emacs/emacs-30.2.tar.xz.sig
   gpg --verify emacs-30.2.tar.xz.sig emacs-30.2.tar.xz
   ```
3. パッチ適用行を 0-A の結果に合わせて差し替える
4. 26.3 のコードパスを残すか消すかは判断に委ねる。
   維持コストを考えると**消してよい**と考えるが、消す場合は README の
   Supporting セクションも更新すること。

### 0-C. `configure` オプションの見直し

現行:

```
--with-ns --with-modules --without-x --without-selinux --without-makeinfo
--without-mail-unlink --without-mailhost --without-pop --without-mailutils
--without-jpeg --without-lcms2 --without-gnutls
```

30.2 の `configure.ac` に対して確認した結果:

- `--without-makeinfo` は **30.2 に存在しないオプション**。
  `MAKEINFO` は `AC_PATH_PROG` で探されるだけ (`configure.ac:2129`) で、
  制御するなら `MAKEINFO=true` のように環境変数で渡す。
  現状は autoconf に黙って無視されている no-op なので**削除する**。
- それ以外の 10 個は 30.2 でも有効。
- `--without-jpeg --without-lcms2 --without-gnutls` は issue #2 由来の回避策。
  **30.2 でも本当に必要か再検証すること。** 不要なら外して機能を戻す。

30.2 で新たに検討できるもの (いずれも任意、Phase 0 では**有効にしない**ことを推奨。
まず素の状態でビルドを通すのが先):

- `--with-native-compilation` — ビルド時間とバンドルサイズが大幅に増える
- `--with-tree-sitter`
- `--with-xwidgets` — `nsxwidget.m` が加わる
- `--with-json`

### 0-D. 完了条件

- [ ] `sh build.sh emacs30` が最後まで通る
- [ ] `pkg/Applications/Emacs/Emacs.app` が生成される
- [ ] `.app` が起動し、`M-x emacs-version` が 30.2 を返す
- [ ] 日本語入力の挙動を確認し、ns-inline-patch の要否を判断済み
- [ ] Bitrise CI が緑

---

## Phase 1: Info.plist の整備

**Emacs の C コードに一切触らない。`build.sh` のパッチ追加だけで完結する。**
工数対効果が最も高いのでここから。

### 1-A. 対象ファイル

テンプレート: `nextstep/templates/Info.plist.in`

生成先: `nextstep/Cocoa/Emacs.base/Contents/Info.plist`
(`configure.ac:7826` の `AC_CONFIG_FILES` で生成される)

**編集するのはテンプレートのほう。** 生成物を直接いじっても
`configure` 実行で上書きされる。

### 1-B. 追加するキー

| キー | 値 | 理由 |
| --- | --- | --- |
| `LSMinimumSystemVersion` | 決定した最小 macOS | 未指定だと古い OS で起動して落ちる |
| `NSHighResolutionCapable` | `true` | Retina 対応の明示 |
| `NSSupportsSuddenTermination` | `false` | 未保存バッファがある以上、明示的に無効化する。既定も `false` だが意図を残す |
| `NSSupportsAutomaticTermination` | `false` | 同上 |
| `NSSupportsAutomaticGraphicsSwitching` | `true` | dGPU 搭載機での電力 |
| `CFBundleVersion` | ビルド番号 | 現在 `9.0` 固定。配布・notarization で問題になる |

**Phase 1 では追加しないもの** (Phase 4 に回す):
`LSApplicationCategoryType`、`NSUserActivityTypes` (Handoff)、
サンドボックス関連のエンタイトルメント。

`CFBundleURLTypes` への `org-protocol` / `emacs` スキーム追加は、
Phase 2 の `application:openURLs:` 実装と**対で入れる**こと。
片方だけでは動かない。

### 1-C. 進め方

`build.sh` のパッチとして追加する
(`05-info-plist-lifecycle.patch` のような名前)。
既存パッチと同じく `patch -p1 -i` で当たる形式にする。

### 1-D. 完了条件

- [ ] ビルド後の `Emacs.app/Contents/Info.plist` に上記キーが入っている
      (`plutil -p pkg/Applications/Emacs/Emacs.app/Contents/Info.plist` で確認)
- [ ] `.app` が起動する
- [ ] `codesign` と notarization が従来どおり通る

---

## Phase 2: 不足しているデリゲートメソッドの追加

純粋な Objective-C の追加。1 件あたり数十行。
編集対象は `src/nsterm.m` の `@implementation EmacsApp` ブロック
(`nsterm.m:5896`–`6544`) と `lisp/term/ns-win.el`。

**重要**: 30.2 は Cocoa 側で `NSNotificationCenter` の購読を
1 件しか行っていない (`NSAntialiasThresholdChangedNotification`,
`nsterm.m:6176`)。通知の購読は `applicationDidFinishLaunching:`
(`nsterm.m:6161`) に追記するのが既存の流儀。

**Lisp への通知方法**: 既存の `KEY_NS_POWER_OFF` と同じ流儀を踏襲する。
`-[EmacsApp terminate:]` (`nsterm.m:6248`) が非キーイベントを
`kbd_buffer_store_event` で投入し、`lisp/term/ns-win.el:174` で
`[ns-power-off]` にキーバインドされている。この形なら
`src/nsterm.m` と `lisp/term/ns-win.el` の中で完結するため、
`make-docfile` の制約 (`.c` と `.m` しか走査しない) に抵触しない。

### 着手順 (効果の大きい順)

#### 2-A. `applicationShouldHandleReopen:hasVisibleWindows:`
Dock アイコンをクリックしてもフレームが復活しない問題。
**体感的な効果が最も大きいのでここから。** 30.2 に実装は一切ない
(`Reopen` の出現数 0)。

#### 2-B. `applicationShouldTerminate:` の `NSTerminateLater` 化
**締切問題の本命。** 現状の終了パスには次の問題がある:

- `-[EmacsApp terminate:]` (`nsterm.m:6248`) が `NSApplication` の
  `terminate:` をオーバーライドし、**`[super terminate:]` を呼ばない**
  (実測: `super terminate` の出現数 0)
- `applicationShouldTerminate:` (`nsterm.m:6287`) も別に存在し、
  `ns-confirm-quit` を見て独自の `NSAlert` を出す
- **`NSTerminateLater` と `replyToApplicationShouldTerminate:` は
  どちらも出現数 0** — ログアウト時に「保存中なので待ってほしい」と
  AppKit に伝える正規の手段を使っていない

`applicationShouldTerminate:` で `NSTerminateLater` を返し、
Lisp 側の保存完了後に `replyToApplicationShouldTerminate:YES` を呼ぶ形にする。
これでログアウト・シャットダウン時の強制終了を回避できる。

**注意**: 2 つの終了パスが重複しているため、片方だけ直すと
Cmd-Q とログアウトで挙動が食い違う。両方の経路を実機で確認すること。

#### 2-C. `NSWorkspace` 通知の購読
`applicationDidFinishLaunching:` に追記する:

- `NSWorkspaceWillSleepNotification` / `NSWorkspaceDidWakeNotification`
- `NSWorkspaceWillPowerOffNotification`
- `NSWorkspaceSessionDidResignActiveNotification` (ファストユーザスイッチ)

**購読先は `[NSWorkspace sharedWorkspace] notificationCenter` であって
`[NSNotificationCenter defaultCenter]` ではない。** 間違えると通知が来ない。

#### 2-D. ダークモードの自動追従
30.2 は `-[EmacsWindow setAppearance]` (`nsterm.m:9867`) で
`ns-appearance` フレームパラメータから外観を**設定する**だけで、
システム側の変更を**観測していない**
(`viewDidChangeEffectiveAppearance` / `effectiveAppearance` ともに出現数 0)。

`viewDidChangeEffectiveAppearance` を実装して Lisp にフックを投げる。

#### 2-E. `application:openURLs:`
`application:openFile:` (`nsterm.m:6314`) 系 4 メソッドは
macOS 10.13 で非推奨。`application:openURLs:` を追加する。
Phase 1 で保留した `CFBundleURLTypes` の追加と**対で行う**。

既存の 4 メソッドは互換のため**残すこと** (古い OS と Apple Event 経由の
呼び出しが残る)。

#### 2-F. `applicationWillTerminate:`
終了直前の後始末フック。2-B と合わせて設計する。

### 完了条件 (各項目共通)

- [ ] `#ifdef NS_IMPL_COCOA` で囲まれており、GNUstep ビルドを壊さない
- [ ] 実機で該当イベントを発火させて動作確認済み
      (スリープ、ログアウト、Dock クリック、ダークモード切替)
- [ ] 上流に出せる粒度でコミットが分かれている (§5)

---

## Phase 3: ランループ — 本丸

**ここが本質的な問題。Phase 2 まで終えた状態で着手する。**

### 3-A. 何が問題か

Emacs は `NSApplicationMain` を使わない (`nsterm.m:5649` で
`[EmacsApp sharedApplication]` を呼ぶだけ)。
イベント処理は Emacs 側が主導し、`ns_read_socket_1` (`nsterm.m:4743`) と
`ns_select_1` (`nsterm.m:4835`) が **`[NSApp run]` を短時間だけ回して抜ける**
動作を繰り返す。抜ける手段は自分宛に `NX_APPDEFINED` を投げること
(`ns_send_appdefined`, `nsterm.m:4663`)。これを
`-[EmacsApp sendEvent:]` (`nsterm.m:5988`, 説明コメントは `nsterm.m:6035`)
が捕まえてループを止める。

結果:
**AppKit のデリゲートコールバックと NSWorkspace 通知は、
Emacs が `[NSApp run]` の中にいる間 (＝入力待ちの間) しか配送されない。**

Lisp 実行中 (長い font-lock、GC、同期プロセス、Tramp のブロッキング I/O) は
ポンプしないため、macOS からは応答なしのアプリに見える。
締切のあるイベント (ログアウト、シャットダウン、App Nap) で失敗するのはここ。

なお `-[EmacsApp run]` のオーバーライド (`nsterm.m:5928`) は
macOS 10.9 専用の回避策で、現行 macOS では `[super run]` に素通しされる。
**ここを触る必要はない。**

### 3-B. 取りうる方針 (推奨順)

1. **App Nap の明示的抑止** — 数行で効果が出る。まずこれ。
   ```objc
   [[NSProcessInfo processInfo]
     beginActivityWithOptions:NSActivityUserInitiated
                       reason:@"..."];
   ```
   返り値のトークンを保持し続ける必要がある点に注意。
2. **締切のあるイベントの別扱い** — Phase 2-B の `NSTerminateLater` 化が
   これに当たる。Phase 2 で済んでいれば大きな山は越えている。
3. **ポンプ頻度の底上げ** — Emacs の `atimer` などから定期的に
   `ns_read_socket_1(..., YES)` 相当を回す。
   **影響範囲が広く、根本解決にもならない。最後の手段。**
   ここに手を出す前に、1 と 2 で実用上十分かを実機で測ること。

### 3-C. 完了条件

- [ ] 長い Lisp 処理 (例: 大きなファイルの font-lock) の最中に
      ログアウトを試み、強制終了されないこと
- [ ] バックグラウンドでタイマーが絞られないこと
- [ ] Cmd-Q、Dock からの終了、ログアウトの 3 経路すべてで
      未保存バッファの確認が正しく出ること

---

## Phase 4: 後回しにしたもの

Phase 3 まで完了してから検討する。着手順は未定。

- **Mac App Store 配布** — `LSApplicationCategoryType`、サンドボックス、
  エンタイトルメントの全面見直し。Emacs はサブプロセスを起動するため
  サンドボックス化の難易度が高い。実現性の調査から始めること
- **状態復元** — `encodeRestorableStateWithCoder:` /
  `restoreStateWithCoder:`。30.2 は
  `applicationSupportsSecureRestorableState:` で `YES` を返す
  (`nsterm.m:6242`) のに実際の復元は未実装、という不整合がある。
  ただし Emacs の `desktop.el` と役割が重複するため設計判断が必要
- `applicationProtectedDataDidBecomeAvailable:` (FileVault)
- Handoff (`NSUserActivityTypes`)
- **iPadOS** — AppKit は iOS に存在しないため、本ロードマップの延長線上にない。
  UIKit バックエンドの新規実装であり別プロジェクト規模。
  参考にすべきは `nsterm` ではなく Emacs 30 の `androidterm.c`
- **Swift 化** — [`swift-migration.md`](./swift-migration.md) 参照。
  やるとしても `EmacsBell` (`nsterm.m:1215`–`1300`、85 行、
  Lisp にも `struct frame` にも触らない) のような葉のクラスでの実験に留める

---

## 5. コミットの分け方 (重要)

Phase 1〜3 の成果は **上流 GNU Emacs に還元しうる**。
Swift 化との決定的な違いがここにあり、長期の追従コストを大きく下げる。

そのため、最初から次の 2 系統を**別コミットに分けて**おくこと:

| 系統 | 内容 | 行き先 |
| --- | --- | --- |
| 上流に出せるもの | `src/nsterm.m` のデリゲートメソッド、ランループ、`lisp/term/ns-win.el`、`nextstep/templates/Info.plist.in` | `emacs-devel` に提案 |
| 本リポジトリ固有 | `build.sh`、パッケージング、署名・notarization、`package*.xml` | ここで抱える |

上流に出す条件:

- GNUstep を壊さない (`#ifdef NS_IMPL_COCOA` で囲む)
- 15 行を超える変更には FSF への著作権譲渡 (copyright assignment) が必要
- 提案先は `bug-gnu-emacs` (バグ) または `emacs-devel` (機能追加)

フォークとして抱え続けるコストと比べれば、譲渡手続きのほうが安い。

---

## 付録: 調査時の実測値について

本書および関連ドキュメント中の行番号・行数は、すべて `emacs-30.2` タグの
ソースツリーに対する実測値です (調査日: 2026-07-31)。

パッチ適用後や上流の更新でずれるため、**編集前に必ず `grep` で
現在位置を確認してください。** 例:

```sh
grep -n 'applicationShouldTerminate' src/nsterm.m
grep -n '@implementation EmacsApp' src/nsterm.m
```
