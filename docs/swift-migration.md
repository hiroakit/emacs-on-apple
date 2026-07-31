# NSTerm の Swift 移行: 対応事項の洗い出し

対象: GNU Emacs 30.2 (`emacs-30.2` タグ) の NeXTstep バックエンド

本書は README の Objective 「Porting Objective-C code to Swift」を実際に着手可能な
粒度まで分解し、技術的ブロッカーと意思決定事項を列挙したもの。
以下の数値・行番号はすべて Emacs 30.2 のソースを実際に走査して得たもの。

---

## 0. 前提: 現リポジトリは Emacs 26.3 固定

`build.sh` は 26.3 を対象にしており、Swift 以前に 30.2 へのリベースが必要。

### 0.1 既存パッチの棚卸し

| パッチ | 30.2 での扱い |
| --- | --- |
| `00-bump-copyright-year.patch` | 対象行が移動。作り直し |
| `01-remove-blessmail.patch` | `Makefile.in` の構造が変化。要再確認 |
| `02-provisional-emacs26.3-unexmacosx.c.patch` | **不要**。30.2 は `--with-dumping=pdumper` が既定 (`configure.ac:467`)。`unexmacosx.o` は `--with-dumping=unexec` を明示した場合のみ使われる (`configure.ac:2252`) |
| `03-bump-emacs-version.patch` | 作り直し |
| `04-macos-big-sur.patch` | `src/macim.h` を新規追加するもので ns-inline-patch 前提。下記 0.2 と併せて再評価 |
| `takaxp/ns-inline-patch` (`emacs-25.2-inline.patch`) | **そのままでは適用不可**。30.2 本体に `workingText` / `NSTextInputClient` 実装がある (`nsterm.m:7081-7257`)。`ns-working-text` は DEFVAR 済み (`nsterm.m:11072`)、`lisp/term/ns-win.el:307-317` に `ns-put-working-text` / `ns-insert-working-text` がありオーバーレイで point 位置に表示される。パッチを維持する必要があるか改めて判定すべき |

### 0.2 configure オプションの見直し

`--without-jpeg --without-lcms2 --without-gnutls` は issue #2 由来の回避策。
30.2 では `--with-native-compilation`、`--with-tree-sitter`、`--with-xwidgets`、
`--with-json` など新規オプションが増えているため、方針を決め直す必要がある。
特に `--with-xwidgets` は `nsxwidget.o` を `NS_OBJC_OBJ` に追加する
(`configure.ac:4490`) ので、Swift 移行の対象範囲に直接影響する。

---

## 1. 規模の実測: 「NS レイヤ = Objective-C」ではない

移行計画で最初に押さえるべき事実。NS バックエンドの大半は Objective-C ではなく、
Emacs コアの C API を直接叩く**素の C** である。

| ファイル | 総行数 | ObjC (`@interface`/`@implementation` 内) | 素の C |
| --- | ---: | ---: | ---: |
| `src/nsterm.m` | 11,261 | 4,965 (44%) | 6,296 (55%) |
| `src/nsfns.m` | 4,070 | 69 (1%) | 4,001 (98%) |
| `src/macfont.m` | 4,257 | 0 (0%) | 4,257 (100%) |
| `src/nsmenu.m` | 2,039 | 1,045 (51%) | 994 (48%) |
| `src/nsfont.m` | 1,765 | 0 (0%) | 1,765 (100%) |
| `src/nsselect.m` | 825 | 0 (0%) | 825 (100%) |
| `src/nsxwidget.m` | 637 | 281 (44%) | 356 (55%) |
| `src/nsimage.m` | 610 | 353 (57%) | 257 (42%) |
| **合計** | **25,464** | **6,713 (26%)** | **18,751 (74%)** |

ヘッダを含めると 27,164 行 (`nsterm.h` 1,387 / `nsgui.h` 143 / `macfont.h` 88 / `nsxwidget.h` 82)。

**帰結**: 「NSTerm を Swift へ」の実作業対象は 25,464 行全体ではなく、
ObjC クラス実装の 6,713 行。残り 74% は Emacs コアの一部であり、
Swift 化しても利点がなく §2.3 / §2.4 のリスクだけが増える。**非目標とすべき。**

### 1.1 移行対象クラス一覧

`nsterm.h` が宣言するクラス (行番号は `nsterm.h`)、実装位置は `nsterm.m`:

| クラス | 宣言 | 実装 | 実装行数 |
| --- | ---: | ---: | ---: |
| `NSColor (EmacsColor)` | 357 | 151–200 | 49 |
| `NSString (EmacsString)` | 366 | — | — |
| `EmacsBell` | (`nsterm.m:1203`) | 1215–1300 | 85 |
| `EmacsApp` | 378 | 5896–6544 | 648 |
| `EmacsView` | 466 | 6671–9233 | 2,562 |
| `EmacsWindow` | 419 | 9243–10079 | 836 |
| `EmacsScroller` | 706 | 10089–10586 | 497 |
| `EmacsLayer` | 744 | 10597–10864 | 267 |
| `EmacsDocument` | 405 | 10872–10874 | 2 |
| `EmacsMenu` / `EmacsToolbar` / `EmacsDialogPanel` / `EmacsTooltip` / `EmacsFileDelegate` | 540/565/602/632/654 | `nsmenu.m` | 1,045 |
| `EmacsImage` | 670 | `nsimage.m` | 353 |
| `XwWebView` | (`nsxwidget.m:51`) | `nsxwidget.m` | 281 |

---

## 2. 技術的ブロッカー

### 2.1 `lisp.h` を Swift から import できない

- `src/lisp.h` には**関数形式マクロが 165 個、`INLINE` 関数が 282 個**ある。
- Swift の Clang importer は**関数形式マクロを一切取り込まない**。
  `XCAR` / `XCDR` / `CONSP` / `CHECK_STRING` / `make_fixnum` / `AREF` / `SDATA` /
  `BVAR` などが全滅する。
- `INLINE` は `conf_post.h:417,437` で `EXTERN_INLINE` (C99 `extern inline`) に
  展開される。`static inline` と違い定義の実体は 1 つの TU にしか出ないため、
  importer からの参照はリンク時解決に依存し不安定。

**対応**: Swift から使う Emacs C API だけを通常の (inline でない) 関数として
再公開する薄いシム層 `src/emacs_swift_shim.h` / `.c` を新設し、
bridging header ではそれだけを露出する。
これは実質「Swift 用 Emacs C API ラッパの新規実装」であり、移行コストの中心。
シムの API 面積を小さく保てるかが全体の成否を決める。

### 2.2 `DEFUN` / `DEFVAR` が Swift で書けない — かつビルド生成物から消える

`lisp.h:3471` の定義:

```c
#define DEFUN(lname, fnname, sname, minargs, maxargs, intspec, doc) \
  SUBR_SECTION_ATTRIBUTE                                            \
  static union Aligned_Lisp_Subr sname =                            \
     {{{ PVEC_SUBR << PSEUDOVECTOR_AREA_BITS },                     \
       { .a ## maxargs = fnname },                                  \
       minargs, maxargs, lname, {intspec}, lisp_h_Qnil}};           \
   Lisp_Object fnname
```

セクション属性付きの `static union` + 指定初期化子。Swift に等価物はない。

さらに深刻なのがビルド生成物への影響:

- `src/Makefile.in:712` — `GLOBAL_SOURCES = $(base_obj:.o=.c) $(NS_OBJC_OBJ:.o=.m)`
- `src/Makefile.in:714-719` — `GLOBAL_SOURCES` から `make-docfile -g` で `globals.h` を生成
- `src/Makefile.in:695-698` — 同じく `etc/DOC` を生成
- `lib-src/make-docfile.c:783,800` — スキャン対象は **`.c` と `.m` のみ**

つまり `.swift` に移した `DEFUN` / `DEFVAR` は `globals.h` にも `etc/DOC` にも
現れず、ビルドが壊れるか docstring が消える。

対象となる定義数: `nsfns.m` に `DEFUN` 45 個、`nsselect.m` 6 個、`nsmenu.m` 2 個、
加えて `nsterm.m` の `DEFVAR_LISP` 群。

**対応**: (a) `DEFUN` / `DEFVAR` と `syms_of_*` は C/ObjC 側に残す (推奨)、
または (b) `make-docfile.c` に `.swift` スキャナを追加し `Makefile.in` を改造する。
(a) なら §1 の「素の C は非目標」方針と自然に一致する。

### 2.3 `longjmp` による非局所脱出 — 最大の正当性リスク

- Emacs のエラー / `throw` は `sys_setjmp` / `sys_longjmp` (`lisp.h:2293-2304`)。
  実際の脱出点は `eval.c:1290`, `1361`, `1537`, `1604`, `1628`, `1655`。
- `error()`, `xsignal()`, `CHECK_*` など**極めて多くの Emacs C API が signal しうる**。
- Swift は setjmp/longjmp によるフレーム飛び越しを**未定義動作**としている。
  ARC の release、`defer`、`deinit` がすべてスキップされ、リークまたは二重解放になる。

**対応**: Swift フレームから Emacs C を呼ぶ境界を「絶対に signal しない関数」に
限定する。signal しうる呼び出しは `internal_condition_case_1` / `internal_catch`
で C 側にラップし、結果だけを Swift に返す。
この境界設計を怠ると再現困難なクラッシュになるため、シム層 (§2.1) の設計時点で
「signal しうる / しない」を型か命名規約で分離しておくこと。

### 2.4 GC の保守的スタックスキャン

- `alloc.c:5274` `mark_memory()` / `alloc.c:5493` がスタックを生スキャンし、
  `alloc.c:5456` 付近の `__builtin_unwind_init` でレジスタを退避する。
- Swift のローカル変数に置いた `Lisp_Object` (実体は `Lisp_Word`、`lisp.h:586,592`)
  は原則スキャンされる。しかし Swift がその値を**エスケープするクロージャの
  コンテキストや箱としてヒープに置いた場合、GC の走査対象外**となり回収される。

**対応**: `Lisp_Object` を Swift のエスケープするクロージャ / プロパティ / 配列に
保持しない。保持が必要なら `staticpro` するか、Lisp 側のデータ構造に持たせる
(Emacs は `GCPRO` を廃止済みなので代替手段はこの 2 つ)。
Swift 側では `Lisp_Object` を「短命な不透明値としてのみ扱う」規約を明文化する。

### 2.5 GNUstep サポートを落とすことになる = 恒久フォーク

- `NS_IMPL_GNUSTEP` / `NS_IMPL_COCOA` の条件分岐は **237 箇所**
  (`nsterm.m` 137、`nsfns.m` 42、`nsterm.h` 30、`nsmenu.m` 23、`nsselect.m` 3、`nsimage.m` 2)。
- Swift に C プリプロセッサはない。`#if` は Swift の条件コンパイル (`-D`) に
  置き換えられるが、そもそも **GNUstep 環境に AppKit 付きの Swift Foundation がない**。
- 結果として GNUstep サポートは事実上放棄となる。

**帰結**: この作業は上流 GNU Emacs に還元できない。加えて GNU プロジェクトは
実装言語として C 以外を受け付けず、著作権譲渡も必要。
**上流マージを想定しない恒久フォーク**として計画すべき。
上流の 30.3 / 31 系への追従コストを誰がどう払うかを先に決めること。

### 2.6 ObjC ↔ Swift 相互運用とヘッダの循環

- Swift クラスを ObjC から使うには `NSObject` 継承 + `@objc` が必要。
  `EmacsView : NSView` 等はこれを満たすので Swift 側での定義自体は可能。
- 問題は `nsterm.h` の `struct ns_output` が ObjC 型を直接メンバに持つこと:

  ```c
  struct ns_output {
  #ifdef __OBJC__
    EmacsView *view;
    ...
    EmacsToolbar *toolbar;
  #else
    void *view;
    ...
  #endif
  ```

- ここで include が循環する:
  - Swift は bridging header 経由で `nsterm.h` (`struct ns_output`, `struct frame`) を必要とする
  - `nsterm.h` は `EmacsView` (= Swift 生成ヘッダ `Emacs-Swift.h`) を必要とする

**対応**: `@class EmacsView;` の前方宣言だけを別ヘッダに切り出す、
または当該メンバを `void *` に統一して Swift 側で `Unmanaged` 経由で扱う。
いずれにせよ **2 フェーズビルド** (`swiftc -emit-objc-header-path` →
生成ヘッダを include して `clang`) を Makefile に組み込む必要がある。

- 併せて、旧 API `NSTextInput` 準拠が 6 箇所残っている
  (`nsterm.h:466-468`, `nsterm.m:7041-7067`)。
  Swift で非推奨プロトコルを採用するのは扱いが面倒なので、
  `NSTextInputClient` への一本化を前提条件とする。

### 2.7 ビルドシステム: autotools に Swift サポートがない

- `src/Makefile.in:455` — `.SUFFIXES: .c .m .cc`。**`.swift` はない。**
- 暗黙ルールは `.m.o:` (`Makefile.in:458`) のみ。
- Swift は whole-module compilation が前提で、**1 ファイル = 1 オブジェクトという
  make のモデルと噛み合わない**。

必要な作業:
- `configure.ac` に `swiftc` 検出 (`AC_CHECK_TOOL`)、`SWIFT_OBJ` / `SWIFTFLAGS` /
  `AC_SUBST` を追加
- `src/Makefile.in` に Swift モジュールを 1 オブジェクトにまとめるルールと
  `-emit-objc-header-path` を追加
- 依存関係生成 (Swift は `-MD` 相当が C ほど成熟していない) と
  `make bootstrap` / `make -j` との整合
- Bitrise CI の Xcode バージョン固定 (現状 badge のみで設定内容は本リポジトリ外)

**Swift ランタイム**: macOS 10.14.4 以降は ABI 安定により OS 同梱。
それ以降をターゲットにすれば `.app` への埋め込みは不要で、
既存の `codesign --deep` / notarization フローに追加作業は生じない。
10.14.3 以前を切るかどうかがバンドル構成の分岐点。

### 2.8 pdumper との相互作用

- 30.2 の既定は `--with-dumping=pdumper` (`configure.ac:467`)。
- **Swift のグローバル変数は `swift_once` による遅延初期化**。
  pdumper は C ヒープをダンプ・復元するため、Swift ランタイム管理下の状態を
  ダンプ越しに持ち越すと不整合を起こす。
- NS 側には既に pdumper フックがある: `syms_of_nsfont_for_pdumper` (`nsfont.m:1762`)。

**対応**: Swift 側にグローバル可変状態を置かない。状態はすべて C の struct
(`ns_display_info` / `ns_output`) 側に持たせる。
temacs のダンプ時は GUI が初期化されないため通常は顕在化しないが、
規約として明文化しておかないと後から踏む。

### 2.9 スレッドと Swift Concurrency

- `ns_select` (`nsterm.m:5002`, 実体は `ns_select_1` `nsterm.m:4835`) が
  NSApp のランループと Emacs の `thread_select` / `pselect` を統合している
  (`nsterm.m:4873-4883`)。
- `ns_read_socket` (`nsterm.m:4828`) が入力イベントを Emacs 側へ渡す。
- Emacs Lisp スレッドは協調的で、AppKit コールバックはメインスレッド前提。

**対応**: Swift 化部分で `async` / `await` / `actor` を使わない。
暗黙のスレッドホップが起きると「メインスレッド以外から Lisp を触らない」という
Emacs コアの前提を壊す。使うのは `@MainActor` の明示のみに留める。

### 2.10 iPadOS 対応 (README の目標) には直結しない

- **AppKit は iOS/iPadOS に存在しない。** NSTerm の Swift 化は iPadOS 対応の
  前段にならない。必要なのは UIKit バックエンドの新規実装であり、別プロジェクト規模。
- 参考にすべきは `nsterm` ではなく、Emacs 30 に既にある非デスクトップ
  バックエンド `androidterm.c` / `androidfns.c` (`src/Makefile.in:502`)。
- README の目標としては維持してよいが、本移行のスコープからは外すべき。

---

## 3. 推奨する進め方

### Phase 0: 30.2 ベースのビルド復旧 (Swift 以前)
§0 の全項目。パッチ再作成、`configure` オプション見直し、CI 更新。
**ここが終わらないと以降の検証手段がない。** 最優先。

### Phase 1: 境界の整備 (Swift ファイル 0 個)
- `emacs_swift_shim.h/.c` 導入 (§2.1)、signal 境界の規約決定 (§2.3)
- `nsterm.h` から ObjC クラス宣言を分離し include 循環を解消 (§2.6)
- `configure.ac` / `Makefile.in` に 2 フェーズビルドを導入 (§2.7)
- この状態で `make bootstrap` が通ることを確認する

### Phase 2: 葉のクラスから移行 (依存の少ない順)
1. **`EmacsBell`** (`nsterm.m:1215-1300`, 85 行) — 純粋な `NSImageView`。
   Lisp にも `struct frame` にも触らないことを確認済み。**最初の 1 本に最適。**
2. `EmacsLayer` (267 行) — `CALayer`、描画バッファのみ
3. `EmacsScroller` (497 行) — Lisp との接点は少量
4. `EmacsImage` (`nsimage.m`, 353 行)

### Phase 3
`EmacsWindow` (836 行)、`EmacsMenu` / `EmacsToolbar` ほか (`nsmenu.m`, 1,045 行)

### Phase 4 (最難関)
`EmacsApp` (648 行)、`EmacsView` (2,562 行)。
`EmacsView` は `NSTextInputClient`・描画・イベント処理のすべてが Lisp と密結合。

### 非目標
素の C 部分 18,751 行 (§1)。特に `nsfns.m` (98% が C)、`nsfont.m` / `macfont.m` /
`nsselect.m` (100% が C) は Swift 化の対象外とする。
`ns_redisplay_interface` の関数テーブル (`nsterm.m:5437-5471`, 27 スロット) も同様。

---

## 4. 先に決めるべき意思決定事項

1. **上流還元を諦めるか** — GNUstep 放棄と GPLv3 フォーク維持を受け入れるか (§2.5)。
   受け入れる場合、上流 30.3 / 31 系への追従方針を併せて決める
2. **最小 macOS バージョン** — 10.14.4 が Swift ランタイム同梱の境界 (§2.7)
3. **ns-inline-patch を維持するか** — 30.2 上流の `ns-working-text` に寄せるか (§0.1)
4. **Xcode プロジェクト化するか autotools を拡張するか** —
   README の "Support Xcode" 目標との関係 (§2.7)
5. **ObjC を完全に無くすのか** — §2.2 の理由から、`DEFUN` / `syms_of_*` 用の
   薄い `.m` を残すのが現実的
6. **`--with-xwidgets` を有効にするか** — `nsxwidget.m` (281 行の ObjC) が
   移行対象に加わる (§0.2)

---

## 5. 調査に使った環境

Emacs 30.2 のソースは `ftp.gnu.org` が本作業環境のネットワークポリシーで
遮断されていたため、GitHub ミラーの `emacs-30.2` タグから取得した:

```sh
git clone --depth 1 --branch emacs-30.2 https://github.com/emacs-mirror/emacs.git
```

本書中の行番号・行数はこのツリーに対する実測値。
