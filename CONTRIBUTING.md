# Contributing

このリポジトリへの変更は Pull Request 経由で行う。

## PR のサイズ

**レビューできる大きさに保つこと。** 差分が大きい PR はレビューに時間がかかり、
判断に自信を持てないまま承認するか、放置されるかのどちらかになる。
1回あたり 200〜400 行を超えると欠陥の検出率が落ちるという
[SmartBear: Best Practices for Code Review](https://smartbear.com/learn/code-review/best-practices-for-peer-code-review/)
が根拠。Cisco で 10か月・2,500件のレビュー・320万行を分析した調査に基づく
（[Code Review at Cisco Systems](https://static0.smartbear.co/support/media/resources/cc/book/code-review-cisco-case-study.pdf)）。
本リポジトリの上限は 300 行とする。

### ルール

1. **差分は 300 行以内**（追加 + 削除）。超えると CI が失敗する。
2. **1つの PR は1つの目的に絞る。** パッチの追加とビルドスクリプトの整理、
   ドキュメントの更新と設定変更を同時にやらない。

### 集計の対象

| 区分 | 対象 | 扱い |
| --- | --- | --- |
| 集計する | 下記以外のすべて（`*.patch`, `build.sh`, `*.plist`, `entitlements.plist`, `.github/` など） | **300 行超で失敗** |
| 集計しない | [.github/pr-size-ignore](.github/pr-size-ignore) に列挙したパス | 数えない |

除外しているのは、行数がレビュー負荷を表さないもの:

- **`docs/` の調査記録・作業手引き** — 長文になるのが正常
- `LICENSE`（上流のライセンス全文）
- 画像・デザインファイル・フォント
- Xcode / SwiftPM の生成物（`*.pbxproj`, `xcuserdata/`, `Package.resolved` など）

**パッチとビルドスクリプトは集計する。** ここが本リポジトリの本体であり、
行数がそのままレビュー負荷になる。

除外の追加・変更は [.github/pr-size-ignore](.github/pr-size-ignore) に1行足すだけでよい。
書式は `.gitignore` と同じ（先頭 `/` でルート固定、末尾 `/` でディレクトリ、
`*` `**` `?`、`!` で取り消し、`#` でコメント）。
判定ロジックと閾値は [.github/scripts/pr-size-limit.js](.github/scripts/pr-size-limit.js) にある。

### 300 行を超えてしまったら

分割する。分割の切り口の例:

- 準備のためのリファクタリング → 本体の変更
- パッチの追加 → ビルドスクリプトからの適用
- 署名・パッケージング周りの変更 → ビルド手順の変更

分割が本質的に不可能な場合（上流バージョンの一括追従など）は、
PR の説明にその理由と、レビュー時に重点的に見てほしい箇所を書くこと。

## ローカルでの確認

macOS 上でビルドが通ることを確認してから PR を出す。

```sh
sh build.sh emacs26
```

パッチを追加・変更した場合は、適用が失敗しないこと、
`build.sh` の該当箇所からも呼ばれていることを確認する。
