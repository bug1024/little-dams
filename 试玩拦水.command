#!/bin/zsh
set -e
cd -- "${0:A:h}"

if [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
    godot_bin=/Applications/Godot.app/Contents/MacOS/Godot
elif (( $+commands[godot4] )); then
    godot_bin=${commands[godot4]}
elif (( $+commands[godot] )); then
    godot_bin=${commands[godot]}
else
    print -u2 '需要 Godot 4。也可以用 Godot 导入同目录的 project.godot，再按 F5 运行项目。'
    exit 1
fi

if [[ ! -d .godot/imported || ! -f .godot/uid_cache.bin ]]; then
    "$godot_bin" --headless --path . --import
fi

if [[ "${1:-}" == --classic ]]; then
    shift
    exec "$godot_bin" --path . res://game/creek.tscn "$@"
fi

exec "$godot_bin" --path . "$@"
