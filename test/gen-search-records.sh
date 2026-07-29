#!/usr/bin/env bash
# Generate tab-separated search benchmark records: line_no<TAB>script_name (Chinese names).
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT=${1:-"$ROOT/data/search-records.tsv"}
COUNT=${2:-100000}

usage() {
  echo "Usage: $(basename "$0") [output_path] [line_count]" >&2
  echo "  default: data/search-records.tsv 100000" >&2
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  usage
  exit 0
fi

if ! [[ $COUNT =~ ^[0-9]+$ ]] || (( COUNT < 1 )); then
  echo "gen-search-records: invalid line count: $COUNT" >&2
  exit 1
fi

# 中文脚本名池（与 script-hub 能力相近的实用工具名）
pool=(
  当前目录占用
  查找大文件
  当前时间戳
  时间戳
  开放端口检测
  随机十六进制
  批量重命名
  清理临时文件
  压缩日志归档
  同步远程目录
  统计代码行数
  监听端口占用
  生成随机密码
  转换文件编码
  合并拆分文本
)

pool_size=${#pool[@]}

pad=8
if (( COUNT >= 100000000 )); then
  pad=9
elif (( COUNT >= 10000000 )); then
  pad=8
elif (( COUNT >= 1000000 )); then
  pad=7
elif (( COUNT >= 100000 )); then
  pad=6
fi

mkdir -p "$(dirname "$OUT")"
: >"$OUT"

for ((i = 1; i <= COUNT; i++)); do
  idx=$(((i - 1) % pool_size))
  base=${pool[idx]}
  case $((i % 5)) in
    0) name=$base ;;
    1) name="${base}-$((i % 1000))" ;;
    2) name="脚本工具-$((i % 10000))" ;;
    3) name="${base}-附加-$((i % 100))" ;;
    4) name="小工具-${base}" ;;
  esac
  printf '%0*d\t%s\n' "$pad" "$i" "$name" >>"$OUT"
done

bytes=$(wc -c <"$OUT" | tr -d ' ')
echo "gen-search-records: wrote $COUNT lines to $OUT (${bytes} bytes)" >&2
