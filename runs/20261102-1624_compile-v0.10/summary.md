# コンパイル記録: ResearchPullback v0.10

- 実行日時: 2026-11-02 16:24 JST
- コンパイラ: easyMarkets MetaTrader 5 build 6230 のMetaEditor64(ポータブル版 `MT5_EMTester`、`/portable /compile`)
- ソース: `mt5/ResearchPullback.mq5`(コミット 972a61f)を無改変でコピーした
- SHA256: `64e5637585804df2a6668bcdb8d9ff5e2d00e6fd7539744bbbbe09a1b28e0572`(Windowsでチェックアウトした際にCRLFへ変換された作業ファイルの値。コンパイルしたのはこのファイル)
- 同じ内容のGit上の値(LF、コミット972a61f): `f7fe0e2058f99737c7c77728703b2cb52766d38de21bf4bd1c69832a7eb279b3`。違いは改行コードだけ
- 結果: **エラー0、警告1**
  - `warning 68: version '0.10' is incompatible with MQL5 Market, must be xxx.yyy`
    MQL5 Market向けの書式に関する警告で、売買には影響しない。ソースは変更していない。
- MetaEditorの終了コードは1。CLIでのコンパイルでは通常の値で、ログ上は成功している。
- ログ: `compile_log_utf8.txt`(進捗行を除き、パスを伏せたUTF-8版)。UTF-16の原本は `local_raw/`(Git対象外)
