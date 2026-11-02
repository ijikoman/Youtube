# 百鬼夜行 YouTube 制作プロジェクト

海外FXトレーダーの公開手法を調査し、日本語のオリジナル解説動画を制作するための環境です。
現在は制作用CLIと6秒の技術デモです。調査済みの手法解説動画、EA、LINE連携はまだ実装していません。

## 実行

必要環境: Python 3.10以上、FFmpeg（libx264・drawtext）、ffprobe、Noto CJKフォント。
Debian/Ubuntuで不足する場合は `sudo apt-get update` と
`sudo apt-get install -y ffmpeg fonts-noto-cjk` を実行します。Python追加パッケージ・APIキーは不要です。

作業ディレクトリは `/workspace/Youtube`。

```sh
python3 tools/video.py check projects/demo/project.json
python3 tools/video.py render projects/demo/project.json
ffprobe -v error -show_entries format=duration -show_entries stream=codec_type,width,height -of json projects/demo/output/video.mp4
```

生成物は `projects/demo/output/` のMP4、SRT字幕、ナレーション原稿です。
デモは無音。各シーンに `audio` を指定すると収録した音声を組み込めます。
音声はシーン長で切られ、短い場合は無音で補完されます。公開前に必ず試聴して尺を調整してください。

## 新規企画

`projects/demo` を別名でコピーし、`project.json` を編集します。
各シーンに `title`、`duration`（秒）、`narration`、`caption` を指定します。
任意の `image` と `audio` はJSONからの相対ファイルパスです。
画像は1920×1080内に収まるよう余白付きで配置します。未指定なら単色背景です。
字幕・タイトルは自動折り返ししません。字幕は1行35文字程度、2行までを目安に改行してください。
出力は1920×1080、30fps、H.264/AAC。`--output /tmp/video-preview` で出力先を変更できます。
同じ出力先の生成物は上書きされます。

調査・台本・素材権利の管理は [制作手順](docs/workflow.md) を参照してください。
GitHubへのcommit/push、YouTube公開、LINE送信は自動実行しません。

## EA検証動画の準備

[MT5実行手順](mt5/README.md) と [仮説・調査状態](projects/gold-pullback/research.md) を参照。
`mt5/ResearchPullback.mq5` は独自のEMA/ATR仮説の初稿です。
Pau本人の手法の再現ではなく、コンパイル・バックテストも未実施です。
結果記録テンプレートと動画構成案を `projects/gold-pullback/` に保存しています。
