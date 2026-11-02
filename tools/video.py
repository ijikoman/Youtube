#!/usr/bin/env python3
"""Offline storyboard renderer. Python stdlib + system FFmpeg only."""
import argparse
import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile

FONT = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'


def load(path):
    data = json.loads(path.read_text(encoding='utf-8'))
    scenes = data.get('scenes')
    if not isinstance(scenes, list) or not scenes:
        raise ValueError('scenes は空でない配列が必要です')
    for i, scene in enumerate(scenes, 1):
        duration = scene.get('duration')
        if isinstance(duration, bool) or not isinstance(duration, (int, float)) or not math.isfinite(duration) or duration <= 0:
            raise ValueError(f'シーン{i}: duration は正の秒数を指定してください')
        for key in ('title', 'narration', 'caption'):
            if not isinstance(scene.get(key), str) or not scene[key].strip():
                raise ValueError(f'シーン{i}: {key} が必要です')
        for key in ('image', 'audio'):
            if scene.get(key) and not (path.parent / scene[key]).is_file():
                raise ValueError(f'シーン{i}: {key} が見つかりません')
    return data


def run(args):
    subprocess.run(args, check=True)


def stamp(seconds):
    ms = round(seconds * 1000)
    return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'


def render(path, data, output):
    output.mkdir(parents=True, exist_ok=True)
    elapsed = 0
    subtitles = []
    narration = []
    with tempfile.TemporaryDirectory(prefix='youtube-render-') as tmp:
        work = Path(tmp)
        clips = []
        for i, scene in enumerate(data['scenes'], 1):
            duration = scene['duration']
            subtitles.append(f'{i}\n{stamp(elapsed)} --> {stamp(elapsed+duration)}\n{scene["caption"]}\n')
            narration.append(f'## {i}. {scene["title"]}\n\n{scene["narration"]}\n')
            elapsed += duration
            title = work / f'title{i}.txt'
            caption = work / f'caption{i}.txt'
            title.write_text(scene['title'], encoding='utf-8')
            caption.write_text(scene['caption'], encoding='utf-8')
            clip = work / f'{i}.mp4'
            cmd = ['ffmpeg', '-v', 'error', '-y']
            if scene.get('image'):
                cmd += ['-loop', '1', '-i', str((path.parent / scene['image']).resolve())]
            else:
                cmd += ['-f', 'lavfi', '-i', 'color=c=0x101c30:s=1920x1080:r=30']
            if scene.get('audio'):
                cmd += ['-i', str((path.parent / scene['audio']).resolve())]
            else:
                cmd += ['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo']
            vf = (f'scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,'
                  f'drawtext=fontfile={FONT}:textfile={title}:expansion=none:fontsize=64:fontcolor=white:x=100:y=160,'
                  f'drawtext=fontfile={FONT}:textfile={caption}:expansion=none:fontsize=44:fontcolor=white:box=1:boxcolor=black@0.65:boxborderw=20:x=100:y=820')
            cmd += ['-map', '0:v:0', '-map', '1:a:0', '-vf', vf, '-af', 'apad', '-t', str(duration), '-r', '30', '-c:v', 'libx264', '-preset', 'fast', '-threads', '2', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-ar', '48000', '-ac', '2', str(clip)]
            run(cmd)
            clips.append(clip)
        listing = work / 'clips.txt'
        listing.write_text(''.join(f"file '{p}'\n" for p in clips))
        run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', str(listing), '-c', 'copy', '-movflags', '+faststart', str(output / 'video.mp4')])
    (output / 'subtitles.srt').write_text('\n'.join(subtitles), encoding='utf-8')
    (output / 'narration.md').write_text('\n'.join(narration), encoding='utf-8')
    print(f'生成完了: {output / "video.mp4"} ({elapsed}秒)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['check', 'render'])
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        data = load(args.project)
        for tool in ('ffmpeg', 'ffprobe'):
            if not shutil.which(tool):
                raise ValueError(f'{tool} をインストールしてください')
        if not Path(FONT).is_file():
            raise ValueError('fonts-noto-cjk が必要です')
        print(f'確認成功: {len(data["scenes"])}シーン')
        if args.command == 'render':
            render(args.project, data, args.output or args.project.parent / 'output')
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'エラー: {error}\n')


if __name__ == '__main__':
    main()
