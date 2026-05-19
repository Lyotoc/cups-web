#!/bin/bash
# cups-web 容器入口脚本
#
# 职责：在 Go 二进制 /cups-web 启动前执行一次性初始化逻辑。
# 当前包含：
#   1. 扫描仪网络配置——读取 /scan/config.json，向 SANE 后端配置文件写入 net <ip>
#
# 设计说明：
#   - 本脚本由 Dockerfile ENTRYPOINT 指定，PID 1 由 exec 接管给 /cups-web，
#     确保 Go 进程正确接收 SIGTERM 等信号（Docker stop 优雅退出）。
#   - /scan/config.json 通过 docker-compose.yml 的 volume 挂载提供（运行时可改），
#     也可在构建时 COPY 进镜像作为默认值。
#   - 扫描仪配置写入 /etc/sane.d/*.conf 需要 root 权限；docker-compose.yml
#     已设置 user: root，直接 docker run 时需传 --user root。
#   - 配置写入是原子性的：用标记注释（SCAN_MARKER）标识托管块，每次启动时
#     先清除所有旧的托管块，再写入当前 config.json 的内容。修改配置后重启
#     容器即可生效，旧配置不会残留。
#   - SANE 配置解析器不支持行尾注释（# 只在行首有效），因此标记注释必须
#     独占一行，紧随其后的 net <ip> 行一起构成一个托管块，清理时成对删除。
#   - 后续如有其他初始化逻辑（环境变量处理、目录准备等），追加到 exec 之前即可。

set -e

# ── 扫描仪网络配置 ──────────────────────────────────────────────────
# SANE 的网络扫描仪需要在对应后端配置文件（如 /etc/sane.d/epsonds.conf）中
# 添加 `net <ip>` 行，scanimage -L 才能发现设备。
# 不同后端配置文件名不同（epsonds.conf、epson2.conf、fujitsu.conf 等），
# 由 config.json 的 backend 字段指定，脚本自动映射到 /etc/sane.d/<backend>.conf。
# 同时向 /etc/sane.d/net.conf（通用网络后端）追加相同条目，确保兼容性。

CONFIG="/scan/config.json"
# 标记注释：独占一行，紧随其后的 net <ip> 行构成一个托管块。
# 清理时用 sed 删除标记行 + 下一行（即 net 行），实现成对移除。
SCAN_MARKER="# managed by cups-web entrypoint"

# cleanManagedBlocks <file>
# 移除指定文件中所有由本脚本托管的块（标记注释行 + 紧随的 net 行）。
# sed '/pattern/{N;d}' 匹配标记行后读取下一行（N），然后一起删除（d）。
cleanManagedBlocks() {
  local file="$1"
  if [ -f "$file" ]; then
    local tmp="${file}.tmp"
    sed '/^# managed by cups-web entrypoint$/{N;d}' "$file" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$file"
    echo "[scan] cleaned managed blocks from $file"
  fi
}

if [ -f "$CONFIG" ] && command -v jq >/dev/null 2>&1; then
  count=$(jq '.scanners | length' "$CONFIG" 2>/dev/null || echo 0)
  if [ "$count" -gt 0 ] 2>/dev/null; then
    echo "[scan] configuring $count scanner(s) from $CONFIG"

    # 收集本次配置涉及的所有后端，用于清理对应的 conf 文件
    backends=()
    for i in $(seq 0 $((count - 1))); do
      backend=$(jq -r ".scanners[$i].backend // empty" "$CONFIG")
      if [ -n "$backend" ]; then
        backends+=("$backend")
      fi
    done

    # 去重后端列表
    unique_backends=($(printf '%s\n' "${backends[@]}" | sort -u))

    # 第一步：清除所有相关 conf 文件中的旧托管块
    for backend in "${unique_backends[@]}"; do
      cleanManagedBlocks "/etc/sane.d/${backend}.conf"
    done
    cleanManagedBlocks "/etc/sane.d/net.conf"

    # 第二步：写入当前配置
    for i in $(seq 0 $((count - 1))); do
      backend=$(jq -r ".scanners[$i].backend // empty" "$CONFIG")
      ip=$(jq -r ".scanners[$i].ip // empty" "$CONFIG")

      # 跳过字段不完整的条目
      if [ -z "$backend" ] || [ -z "$ip" ]; then
        echo "[scan] skipping entry $i: missing backend or ip"
        continue
      fi

      conf="/etc/sane.d/${backend}.conf"
      net_line="net ${ip}"

      # 写入后端配置文件（如 /etc/sane.d/epsonds.conf）
      # 标记注释独占一行，net 行紧随其后，构成一个托管块
      if [ -f "$conf" ]; then
        printf '%s\n%s\n' "$SCAN_MARKER" "$net_line" >> "$conf"
        echo "[scan] appended '$net_line' to $conf"
      else
        # 后端配置文件不存在时主动创建，SANE 仍能识别
        echo "[scan] warning: $conf not found, creating it"
        printf '%s\n%s\n' "$SCAN_MARKER" "$net_line" > "$conf"
        echo "[scan] created $conf with '$net_line'"
      fi

      # 同步写入 net.conf（通用网络后端），确保 scanimage -L 能通过 net 后端发现
      net_conf="/etc/sane.d/net.conf"
      if [ -f "$net_conf" ]; then
        printf '%s\n%s\n' "$SCAN_MARKER" "$net_line" >> "$net_conf"
        echo "[scan] appended '$net_line' to $net_conf"
      fi
    done
  else
    echo "[scan] no scanners configured in $CONFIG"
    # 配置为空时也要清理旧的托管块
    if [ -d /etc/sane.d ]; then
      for f in /etc/sane.d/*.conf; do
        cleanManagedBlocks "$f"
      done
    fi
  fi
else
  # config.json 缺失或 jq 未安装时静默跳过，不影响服务启动
  if [ ! -f "$CONFIG" ]; then
    echo "[scan] $CONFIG not found, skipping scanner configuration"
  else
    echo "[scan] jq not available, skipping scanner configuration"
  fi
fi

# ── 启动 Go 服务 ────────────────────────────────────────────────────
# exec 替换当前进程，使 /cups-web 成为 PID 1，正确接收容器停止信号。
exec /cups-web "$@"
