# cc:

資料や成果物をエージェントと受け渡す、macOSの小さな棚。
ファイル・画像・リンク・テキストを集めて「棚の資料を読んで」「cc:に置いて」と頼めます。

macOS 26以降・Apple Silicon / Intel対応。無料・オープンソース。
[サイト](https://cc.shigoto.dev) · [ダウンロード](https://github.com/hayashiii-ghub/cc/releases/latest)

## 使い方

1. DMGまたはZIPの`cc.app`をApplicationsへ入れて起動します。
2. **Settings → AI Tools → Set Up**でCodex・Claude Code向けのCLIとスキルを設定します。更新は同じ画面の**Update**から。
3. メニューバーの`cc:`から棚を開き、ドラッグや**Paste**で資料を追加します。

初期ショートカットは、Finderの選択項目を追加する**Option + Tab**と、棚を開閉する**Option + Shift + Tab**。
開くアプリは**Settings → Open with**で選べます。AIにも棚の項目を開く・削除するよう頼めます。

資料はMac内にコピーして保存し、棚から削除しても元ファイルは残ります。
アカウント登録・クラウド同期・利用状況の収集はありません。
アプリの更新は**Settings → Updates…**から。v0.4.0より前の版は手動導入とデータ・設定の移行が必要です。

Appleの公証は未対応です。初回起動がブロックされた場合は、信頼できる配布版か確かめて、macOSの**プライバシーとセキュリティ → このまま開く**を使います。
セットアップ・開発・公開手順は[AGENTS.md](AGENTS.md)へ。

ノッチの操作とサイトの表現は[CodexIsland](https://github.com/ericjypark/codex-island)を参考にしています。独立したプロジェクトです。
[MIT](LICENSE) · [第三者ライセンス](THIRD_PARTY_NOTICES.md)
