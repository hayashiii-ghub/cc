# cc:

エージェントと資料や成果物を受け渡す、macOSの小さな棚。

AIが作ったファイルが深い一時フォルダにあり、CLIにはパスしか出てこない。
複数の資料を渡すたびにコピペが必要で、長いテキストはチャットに貼りづらい。
cc:は、そんな受け渡しを一か所にまとめます。

ファイル・フォルダ・画像・リンク・テキストを棚に集めて、CodexやClaude Codeに読むよう頼む。
成果物も「cc:に置いて」と頼めば、同じ棚で受け取り、開いたりまとめてドラッグしたりできます。

無料・オープンソース。macOS 26以降、Apple Silicon / Intel対応。
[サイト](https://cc.hayashiii-gpt.chatgpt.site) · [最新版をダウンロード](https://github.com/hayashiii-ghub/cc/releases/latest)

## 使い方

DMGまたはZIPから`cc.app`をApplicationsへ入れて起動します。
エージェント連携は、CodexやClaude Codeに次の文を渡して設定できます。

```text
https://github.com/hayashiii-ghub/cc
このリポジトリのAGENTS.mdを読んで、インストール済みのcc:のエージェント連携を設定して。
```

メニューバーの`cc:`から棚を開き、ドラッグや**Paste**で資料を追加します。
初期ショートカットは、Finderの選択項目を追加する**Option + Tab**と、棚を開閉する**Option + Shift + Tab**。
設定でキーや棚の位置（メニューバー／ノッチ）を変更できます。

## データと更新

資料はMac内にコピーして保存します。棚から削除しても元ファイルは残ります。
アカウント登録・クラウド同期・利用状況の収集はありません。

アプリの更新は**Settings → Check for Updates…**から。
エージェント連携の状態は**Settings → Agent Tools**で確認し、更新が必要ならエージェントに頼みます。
v0.4.0より前の版からは手動インストールとデータ・設定の移行が必要です。

Appleの公証は未対応です。初回起動がブロックされた場合は、macOSの**システム設定 → プライバシーとセキュリティ → このまま開く**を使います。
セットアップ・開発手順は[AGENTS.md](AGENTS.md)にあります。

## クレジット

ノッチの操作とサイトの表現は[CodexIsland](https://github.com/ericjypark/codex-island)を参考にしています。両者は独立したプロジェクトです。
[第三者ライセンス](THIRD_PARTY_NOTICES.md) · [MIT](LICENSE)
