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

### 進捗 (2026-08-02)

macOS 実機 (Apple Silicon, Sequoia) 上で `sh build.sh emacs30` の実質相当
(configure/make bootstrap/make install を手動で分割実行) を最後まで走らせ、
`.app` の起動・日本語入力・`ns-inline-patch` の動作まで確認済み。
0-D はビルド本体については解消。残るのは Bitrise CI 上での確認のみ。

- 0-A: 完了。`00`/`01`/`03` を書き直し、`02` を削除。
  `04-macos-big-sur.patch` は**削除**(リポジトリから除去)。
  `ns-inline-patch` は **`emacs-29.1-inline.patch` を採用**して
  `build_emacs30()` に組み込んだ (下記参照)。
- 0-B: 完了。`build_emacs30()` を追加。sha256 は
  `ftp.gnu.org` が遮断されている環境向けに、Homebrew (`homebrew-core`) と
  FreeBSD ports の distinfo という独立した 2 つの配布物から同一の値
  (`b3f36f18a6dd2715713370166257de2fae01f9d38cfe878ced9b1e6ded5befd9`)
  を確認して採用した。**`.sig` の GPG 検証は今回も未実施のまま。**
- 0-C: 完了。`--without-makeinfo` を削除。
  `--without-jpeg` `--without-lcms2` `--without-gnutls` は
  issue #2 の再検証ができていないため、安全側に倒して維持したまま。
- 0-D: ビルド・起動・日本語入力は実機で検証済み (下記チェックリスト参照)。
  Bitrise CI での `emacs30` 実行は未検証。

**ns-inline-patch の判断 (0-A 再評価の結論)**:
30.2 本体の `NSTextInputClient` 実装だけでも日本語入力は問題なく動作した。
一方で `ns-inline-patch` が提供する `M-x mac-ime-toggle` 等のコマンドを
使いたいという要望があったため、`ns-inline-patch` は**採用**した。
ただし 30.x 向けは `emacs-25.2-inline.patch` ではなく
**`emacs-29.1-inline.patch`** が正しい版 (upstream README 記載)。
この版は `src/macim.h` / `src/macim.m` を自前で新規追加するため、
26.3 時代のように `04-macos-big-sur.patch` を先に当てて `macim.h` を
用意しておく必要がない。実機で `patch -p1 --dry-run` のクリーン適用と
`make bootstrap` の成功、`M-x mac-ime-toggle` の動作を確認済み。

**emacs26 コードパスの削除**:
`04-macos-big-sur.patch` の削除は `build_emacs26()` (旧 `emacs-25.2-inline.patch`
+ 同パッチ前提) を壊す。すでに `02-provisional-emacs26.3-unexmacosx.c.patch`
が削除済みで `build_emacs26()` は実際には動かない状態だったため、
維持コストに見合わないと判断し `build_emacs26()` と `emacs26` コマンドを
`build.sh` から削除した。`bitrise.yml` の `primary`/`release` workflow も
`build.sh emacs30` を呼ぶように追随済み (Bitrise 上での動作は未検証)。
README の Usage / Supporting セクションも更新済み。

### 0-A. パッチの棚卸し

| ファイル | 対応 |
| --- | --- |
| `00-bump-copyright-year.patch` | **作り直し**。`configure.ac` の対象行が移動している |
| `01-remove-blessmail.patch` | **要再確認**。`Makefile.in` の構造が変化 |
| `02-provisional-emacs26.3-unexmacosx.c.patch` | **削除**。理由は下記 |
| `03-bump-emacs-version.patch` | **作り直し** |
| `04-macos-big-sur.patch` | **削除済み**。`emacs-29.1-inline.patch` は `macim.h` を自前で追加するため不要 |
| `ns-inline-patch` (`emacs-29.1-inline.patch`) | **採用済み**。`emacs-25.2-inline.patch` は 26.3 系列専用。下記 |

**`02-...unexmacosx` を削除してよい根拠**:
30.2 は `--with-dumping=pdumper` が既定 (`configure.ac:467`)。
`unexmacosx.o` がリンクされるのは `--with-dumping=unexec` を明示した場合のみ
(`configure.ac:2252`)。`src/unexmacosx.c` はツリーに残っているが使われない。

**ns-inline-patch の再評価 (結論: 採用)**:
30.2 本体に `NSTextInputClient` の実装がある (`nsterm.m:7081`–`7257`)。
`workingText` の管理 (`nsterm.m:7161`–`7205`)、`ns-working-text` の `DEFVAR`
(`nsterm.m:11072`)、Lisp 側のオーバーレイ表示 (`lisp/term/ns-win.el:307`–`317` の
`ns-put-working-text` / `ns-insert-working-text`) が揃っている。
実機確認の結果、**素の 30.2 だけでも日本語入力は問題なく動く。**
それでも `M-x mac-ime-toggle` など `ns-inline-patch` 独自のコマンドを
使いたいという要望があったため、パッチ自体は採用することにした。
30.x 向けは upstream README に従い **`emacs-29.1-inline.patch`** を使う
(`emacs-25.2-inline.patch` は 26.3 系列専用)。この版は `src/macim.h` /
`src/macim.m` を自前で新規追加するため、`04-macos-big-sur.patch` は
不要と判断し削除した。

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
4. 26.3 のコードパスは**削除済み**。`02-provisional-emacs26.3-unexmacosx.c.patch`
   が既に削除されていて `build_emacs26()` は実際には動かない状態だったため、
   維持コストに見合わないと判断し `build_emacs26()` と `emacs26` コマンドを
   `build.sh` から除去した。README の Supporting / Usage セクションと
   `bitrise.yml` (`primary`/`release` の両 workflow) も追随済み。

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

- [x] `sh build.sh emacs30` が最後まで通る (2026-08-02、macOS Sequoia 実機で確認。
      configure/make bootstrap/make install を手動で分割実行する形での検証。
      **注意**: この Mac では `pkgx` が `/usr/local/lib/libz*` を独自の
      `@rpath` 参照付き zlib に差し替えており、そのままでは `temacs` が
      `dyld: Library not loaded` で落ちた。`LDFLAGS=-L/opt/homebrew/opt/zlib/lib`
      `CPPFLAGS=-I/opt/homebrew/opt/zlib/include` を `configure` に渡すことで
      回避した。**この回避策は `build.sh` に反映しないことにした**
      (このマシン固有の環境汚染であり、汎用スクリプトに混ぜない判断)。
      pkgx 等でシステムの `/usr/local/lib` が汚染されている環境では
      同じ問題に当たる可能性がある。
- [x] `pkg/Applications/Emacs/Emacs.app` が生成される
- [x] `.app` が起動し、`M-x emacs-version` が 30.2 を返す
- [x] 日本語入力の挙動を確認し、ns-inline-patch の要否を判断済み
      (`emacs-29.1-inline.patch` を採用、`04-macos-big-sur.patch` は削除。詳細は上記)
- [x] Bitrise CI が緑 (2026-08-02。`primary`/`release` 両ワークフローの
      `bash build.sh emacs30` が Bitrise の macOS ランナー上で複数回成功
      (PR #12, #13)。ビルド直後にバイナリを `--batch` 起動して
      `emacs-version`/`mac-ime-toggle` を検証するスモークテストも追加済み。
      `primary` は成果物を Bitrise 標準のアーティファクトストレージへ、
      `release` は GitHub Releases へ公開する形に変更した
      (元は Azure Blob Storage だったが、Azure AD の MFA 強制化で
      `az login -u/-p` が壊れたため移行。詳細は各 PR 参照)。
      nightly ビルドのダウンロード後に Gatekeeper が
      "Emacs.app は壊れています" と表示する問題も発見・修正済み
      (バンドル全体が未署名だったのが原因。無料のアドホック
      `codesign --force --deep --sign -` で解消。PR #13)。
      同一 PR への連続 push でビルドが二重に起動していた問題も
      `trigger_map` の見直しで解消済み (PR #14)。

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
| `LSMinimumSystemVersion` | `15.0` (Sequoia) | 未指定だと古い OS で起動して落ちる。README の「Supporting: macOS Sequoia」に厳密に合わせ、実機検証済みの OS のみを保証する最も安全な選択とした |
| `NSHighResolutionCapable` | `true` | Retina 対応の明示 |
| `NSSupportsSuddenTermination` | `false` | 未保存バッファがある以上、明示的に無効化する。既定も `false` だが意図を残す |
| `NSSupportsAutomaticTermination` | `false` | 同上 |
| `NSSupportsAutomaticGraphicsSwitching` | `true` | dGPU 搭載機での電力 |

**`CFBundleVersion` はこの表から除外した**: 当初 Phase 1 の対象として挙げていたが、
`05-info-plist-lifecycle.patch` を実タグボールに適用検証する過程で、
既存の `03-bump-emacs-version.patch` (由来: 別セッションのコミット
`ad16df0f4d1 Enabled to change CFBundleVersion dynamically in configure.ac`)
が既に `<string>9.0</string>` → `<string>@build_number@</string>` と書き換え、
`configure.ac` 側の `AC_SUBST([build_number], [1])` と組み合わせてビルド番号化
していることが判明したため。コメント `<!-- This SHOULD be a build number. -->`
が示す通り `CFBundleVersion` は `CFBundleShortVersionString` (マーケティング
バージョン、`@version@` = "30.2") とは別物で、両者を混同しない。
実ビルドでの検証値は `CFBundleVersion` = `"1"`、`CFBundleShortVersionString` =
`"30.2"` (`plutil -p` で確認、2026-08-05)。値が常に固定 `1` である
(ビルドのたびに増加しない) 点は Phase 1 のスコープ外の既存事項として残す。

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

- [x] ビルド後の `Emacs.app/Contents/Info.plist` に上記キーが入っている
      (2026-08-05、macOS Sequoia 実機で `sh build.sh emacs30` を最後まで実行し
      `plutil -p pkg/Applications/Emacs/Emacs.app/Contents/Info.plist` で確認。
      `LSMinimumSystemVersion => "15.0"`、`NSHighResolutionCapable => 1`、
      `NSSupportsSuddenTermination => 0`、`NSSupportsAutomaticTermination => 0`、
      `NSSupportsAutomaticGraphicsSwitching => 1` をすべて確認)
- [x] `.app` が起動する (2026-08-05。`--batch --eval` での `emacs-version`/
      `mac-ime-toggle` チェックに加え、`open` での実 GUI 起動・プロセス確認・
      終了まで実施)
- [x] `codesign` と notarization が従来どおり通る (2026-08-05。
      `codesign --force --deep --sign -` (アドホック、Bitrise CI と同じ手順) で
      `valid on disk` / `satisfies its Designated Requirement` を確認。
      `Info.plist entries` はキー追加前の 23 から 28 に増加しており、
      新規キーがシール対象に含まれていることも確認済み。notarization
      (Apple 提出) 自体は Phase 0 と同様に未実施 — 無料のアドホック署名運用の
      ため対象外)

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

#### 2-A. `applicationShouldHandleReopen:hasVisibleWindows:` (対応中止)

30.2 にこのメソッドがないことだけを根拠に、不具合と判断していた。
2026-08-11 の実機検証では、Dock アイコンのクリックに対応する reopen Apple Event
だけで、最小化したフレームが AppKit の標準動作によって復帰した。

Emacs Lisp の `make-frame-invisible` で完全に不可視化したフレームは、Dock アイコンを
クリックしても復帰しない。
これは明示的に不可視化した状態を維持する意図的な動作であり、Dock からの再選択で
自動的に可視化すると呼び出し側の指定を取り消してしまう。

したがって、このメソッドは追加しない。
2-B を保留し、Phase 2 の実装は 2-C から開始した。
2-C は完了しているため、次は 2-D に着手する。

#### 2-B. `applicationShouldTerminate:` の `NSTerminateLater` 化 (Phase 3 まで保留)

現状の終了パスには次の問題がある:

- `-[EmacsApp terminate:]` (`nsterm.m:6248`) が `NSApplication` の
  `terminate:` をオーバーライドし、**`[super terminate:]` を呼ばない**
  (実測: `super terminate` の出現数 0)
- `applicationShouldTerminate:` (`nsterm.m:6287`) も別に存在し、
  `ns-confirm-quit` を見て独自の `NSAlert` を出す
- **`NSTerminateLater` と `replyToApplicationShouldTerminate:` は
  どちらも出現数 0** — ログアウト時に「保存中なので待ってほしい」と
  AppKit に伝える正規の手段を使っていない

2026-08-12 に macOS 15.7.9、Emacs 30.2、Apple Silicon の実機で、
Quit Apple Event を PID 指定で送信して検証した。
変更前の Emacs は `NSTerminateNow` を返した後、既存の
`KEY_NS_POWER_OFF` 経由で `save-buffers-kill-emacs` を実行し、正常終了した。

一方、`applicationShouldTerminate:` で `NSTerminateLater` を返し、
`KEY_NS_POWER_OFF` と `NX_APPDEFINED` を投入する試作では、AppKit の終了待機ループから
Emacs の Lisp ループへ制御が戻らず、保存処理を開始できなかった。
`replyToApplicationShouldTerminate:` を呼ぶ Lisp コード自体が実行されないため、
この方法だけでは終了待ちを完了できない。

したがって、`NSTerminateLater` 化は Phase 2 の独立タスクとして実装しない。
Phase 3 でランループを改修し、AppKit の終了待機中にも Lisp 処理を進められる構造を
用意してから再検討する。

**注意**: 2 つの終了パスが重複しているため、片方だけ直すと
Cmd-Q とログアウトで挙動が食い違う。両方の経路を実機で確認すること。

#### 2-C. `NSWorkspace` 通知の購読
`applicationDidFinishLaunching:` に追記する:

- `NSWorkspaceWillSleepNotification` / `NSWorkspaceDidWakeNotification`
- `NSWorkspaceWillPowerOffNotification`
- `NSWorkspaceSessionDidResignActiveNotification` (ファストユーザスイッチ)

**購読先は `[NSWorkspace sharedWorkspace] notificationCenter` であって
`[NSNotificationCenter defaultCenter]` ではない。** 間違えると通知が来ない。

**完了 (2026-08-15)**: 4 通知を Lisp hook に変換するパッチを追加した。
macOS 15.7.9 (24G830)、Apple Silicon、Emacs 30.2 で、スリープと復帰、
別ユーザーへのファストユーザスイッチ、通常のログアウトを実施し、
各通知が記録されることを確認した。
通知は `emacs_event` の有効期間に依存させず、`kbd_buffer_store_event` へ
直接格納する。前者ではログアウト通知が失われることを実機で確認したためである。
再現手順とログは `docs/ns-workspace-lifecycle-test.org` を参照する。

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
      (スリープ、ログアウト、ダークモード切替)
- [ ] 上流に出せる粒度でコミットが分かれている (§5)

---

## Phase 3: ランループ

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
2. **ポンプ頻度の底上げ**：Emacs の `atimer` などから定期的に
   `ns_read_socket_1(..., YES)` 相当を回す。
   影響範囲が広いため、AppKit の終了待機ループと Lisp の実行を接続できる
   最小の変更範囲を先に特定する。
3. **締切のあるイベントの別扱い**：2 の接続を用いて Phase 2-B の
   `NSTerminateLater` 化を再試験する。
   保存の完了とキャンセルの両方で `replyToApplicationShouldTerminate:` が
   呼ばれることを確認する。

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
