#!/usr/bin/env python3
"""书山静态图标方案切换工具。

每个图标选项对应一组编译期默认图标资源（layered_image_<id> 与 icon.png）。
本脚本将指定方案设为编译期默认：修改 module.json5 中 EntryAbility 的
icon / startWindowIcon 引用，并将选中方案的图标复制为 icon.png。
重新构建 HAP 后侧载，桌面图标立即可见。

用法:
  python scripts/apply_static_icon.py list
  python scripts/apply_static_icon.py apply <icon_id>
  python scripts/apply_static_icon.py apply default   # 恢复默认图标
"""
import argparse
import re
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_JSON5 = REPO_ROOT / 'entry/src/main/module.json5'
MEDIA_DIR = REPO_ROOT / 'entry/src/main/resources/base/media'

# icon_id -> (title, 预览/图标媒体资源名)
OPTIONS = {
    'default': ('默认图标', 'icon'),
    'warm_book': ('纸书暖光', 'ic_app_warm_book'),
    'night_neon': ('夜读霓虹', 'ic_app_night_neon'),
    'minimal_line': ('极简线性', 'ic_app_minimal_line'),
    'ink_wash': ('水墨书山', 'ic_app_ink_wash'),
    'pixel_retro': ('像素复古', 'ic_app_pixel_retro'),
    'theme_classic_blue': ('经典蓝·书页', 'ic_app_theme_classic_blue'),
    'theme_warm_paper': ('暖纸·书笺', 'ic_app_theme_warm_paper'),
    'theme_forest_mist': ('林雾·叶语', 'ic_app_theme_forest_mist'),
    'theme_ink_wash': ('水墨·书山', 'ic_app_theme_ink_wash'),
    'theme_neon_night': ('霓虹·夜读', 'ic_app_theme_neon_night'),
}


def layered_ref(icon_id: str) -> str:
    if icon_id == 'default':
        return '$media:layered_image'
    return f'$media:layered_image_{icon_id}'


def apply(icon_id: str) -> None:
    if icon_id not in OPTIONS:
        raise SystemExit(
            f'未知方案 id: {icon_id}，可用: {", ".join(sorted(OPTIONS))}'
        )
    title, media = OPTIONS[icon_id]
    ref = layered_ref(icon_id)

    # 1. 修改 module.json5 中 EntryAbility 的 icon / startWindowIcon 引用
    text = MODULE_JSON5.read_text(encoding='utf-8')
    updated = re.sub(
        r'"icon": "\$media:[^"]+"',
        f'"icon": "{ref}"',
        text,
        count=1,
    )
    updated = re.sub(
        r'"startWindowIcon": "\$media:[^"]+"',
        f'"startWindowIcon": "{ref}"',
        updated,
        count=1,
    )
    if updated == text:
        raise SystemExit('module.json5 未发生变更，请检查引用格式')
    MODULE_JSON5.write_text(updated, encoding='utf-8')

    # 2. 方形图标 icon.png 替换为选中方案的图标
    if icon_id != 'default':
        src = MEDIA_DIR / f'{media}.png'
        if not src.exists():
            raise SystemExit(f'缺少资源文件: {src}')
        shutil.copy2(src, MEDIA_DIR / 'icon.png')
        print(f'  icon.png <- {media}.png')

    print(f'已应用静态图标方案 [{icon_id}] {title}')
    print(f'  module.json5 EntryAbility icon/startWindowIcon -> {ref}')
    print('请重新构建 HAP，侧载后桌面图标立即可见。')


def status() -> None:
    """打印当前 module.json5 图标引用与已应用的方案 id。"""
    text = MODULE_JSON5.read_text(encoding='utf-8')
    icon_match = re.search(r'"icon": "\$media:([^"]+)"', text)
    start_match = re.search(r'"startWindowIcon": "\$media:([^"]+)"', text)
    icon_ref = icon_match.group(1) if icon_match else '<未找到>'
    start_ref = start_match.group(1) if start_match else '<未找到>'
    print(f'module.json5 EntryAbility icon          -> $media:{icon_ref}')
    print(f'module.json5 EntryAbility startWindowIcon -> $media:{start_ref}')
    if icon_ref == 'layered_image' or start_ref == 'layered_image':
        print('当前为默认图标方案（未应用任何静态方案），桌面图标不会随设置页选择变化。')
    else:
        applied = next((icon_id for icon_id, (_, media) in OPTIONS.items()
                        if f'layered_image_{icon_id}' == icon_ref), None)
        print(f'当前已应用静态图标方案: {applied or icon_ref}')


def main() -> None:
    parser = argparse.ArgumentParser(description='书山静态图标方案切换工具')
    parser.add_argument('mode', choices=['list', 'apply', 'status'])
    parser.add_argument('icon_id', nargs='?', default='')
    args = parser.parse_args()

    if args.mode == 'list':
        for icon_id in sorted(OPTIONS):
            title, media = OPTIONS[icon_id]
            print(f'{icon_id:<24} {title:<12} -> {layered_ref(icon_id)} / {media}')
        return

    if args.mode == 'status':
        status()
        return

    if not args.icon_id:
        raise SystemExit('apply 模式需要 icon_id 参数（可用 apply default 恢复默认）')
    apply(args.icon_id)


if __name__ == '__main__':
    main()
