#!/usr/bin/env bash
# fnos-cli user-local installer for Linux and macOS (Bash 3.2+).
set -Eeuo pipefail

fail() { printf '\n安装失败：%s\n' "$*" >&2; exit 1; }
trap 'printf "\n安装失败，请根据上方错误提示处理后重新运行安装脚本。\n" >&2' ERR

[[ -n "${HOME:-}" && "$HOME" == /* ]] || fail 'HOME 环境变量必须是绝对路径。'
install_root="$HOME/.local/share/fnos-cli"
prefix="$install_root/npm"
bin_dir="$install_root/bin"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/fnos-install.XXXXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

download() {
  local attempt
  if command -v curl >/dev/null 2>&1; then
    for attempt in 1 2 3; do
      if curl --http1.1 --continue-at - --fail --progress-bar --show-error --location --connect-timeout 15 --max-time 600 "$1" -o "$2"; then return 0; fi
      printf '第 %s/3 次下载失败。\n' "$attempt" >&2
    done
    fail "无法下载 $1，请检查网络连接后重试。"
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet --timeout=30 --tries=3 "$1" -O "$2"
  else
    fail '请先安装 curl 或 wget，然后重新运行安装脚本。'
  fi
}

runtime_ok() {
  local version major minor npm_version
  command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 || return 1
  version="$(node --version 2>/dev/null)" || return 1
  version="${version#v}"
  IFS=. read -r major minor _ <<< "$version"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
  (( major > 18 || (major == 18 && minor >= 17) )) || return 1
  npm_version="$(npm --version 2>/dev/null)" || return 1
  [[ "$npm_version" =~ ^([0-9]+)\. ]] || return 1
  (( BASH_REMATCH[1] >= 8 ))
}

private_install=0
printf '正在检查 fnos-cli 安装环境……\n'
if ! runtime_ok; then private_install=1; fi
if ! runtime_ok && [[ -f "$install_root/node-path" ]]; then
  IFS= read -r runtime_dir < "$install_root/node-path"
  if [[ -x "$runtime_dir/bin/node" ]]; then export PATH="$runtime_dir/bin:$PATH"; fi
fi
if ! runtime_ok; then
  case "$(uname -s)" in
    Linux) platform=linux ;;
    Darwin) platform=darwin ;;
    *) fail '暂不支持当前操作系统，请使用 Windows 安装脚本或通过 npm 安装。' ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=x64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) fail '暂不支持当前处理器架构，自动安装仅支持 x64 和 ARM64。' ;;
  esac
  command -v tar >/dev/null 2>&1 || fail '请先安装 tar 和 gzip，然后重试。'
  if command -v sha256sum >/dev/null 2>&1; then
    hash_command=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    hash_command=(shasum -a 256)
  else
    fail '请先安装 sha256sum 或 shasum，然后重试。'
  fi
  printf '正在从 nodejs.org 下载 Node.js 24 长期支持版（包含 npm）……\n'
  download 'https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt' "$work_dir/SHASUMS256.txt"
  entry="$(awk -v suffix="-${platform}-${arch}.tar.gz" '$2 ~ /^node-v24\.[0-9]+\.[0-9]+-/ && substr($2, length($2)-length(suffix)+1) == suffix {print $1 " " $2; exit}' "$work_dir/SHASUMS256.txt")"
  read -r expected_hash archive <<< "$entry"
  [[ "${expected_hash:-}" =~ ^[a-fA-F0-9]{64}$ && "${archive:-}" =~ ^node-v24\.[0-9]+\.[0-9]+- ]] || fail 'Node.js 下载清单无效，请稍后重试。'
  version="${archive#node-}"
  version="${version%%-*}"
  download "https://nodejs.org/dist/$version/$archive" "$work_dir/node.tar.gz"
  actual_hash="$("${hash_command[@]}" "$work_dir/node.tar.gz")"
  [[ "${actual_hash%% *}" == "$expected_hash" ]] || fail 'Node.js 文件校验失败，请重新下载。'
  tar -xzf "$work_dir/node.tar.gz" -C "$work_dir"
  runtime_dir="$install_root/${archive%.tar.gz}"
  mkdir -p "$install_root"
  # Keep previous versions intact, and never reuse a partially installed runtime.
  if [[ -e "$runtime_dir" ]]; then
    runtime_dir="$(mktemp -d "$install_root/${archive%.tar.gz}.XXXXXXXX")"
    rmdir "$runtime_dir"
  fi
  mv "$work_dir/${archive%.tar.gz}" "$runtime_dir"
  export PATH="$runtime_dir/bin:$PATH"
  runtime_ok || fail 'Node.js 无法运行，请检查系统兼容性：Linux 需要兼容的 glibc，macOS 需要受支持的系统版本。'
  printf '%s\n' "$runtime_dir" > "$install_root/node-path"
fi

node_path="$(type -P node)"
case "$node_path" in "$install_root/"*) private_install=1 ;; esac

writable_directory() {
  local target="$1"
  while [[ ! -d "$target" ]]; do
    [[ ! -e "$target" && "$target" != / ]] || return 1
    target="$(dirname "$target")"
  done
  [[ -w "$target" && -x "$target" ]]
}

if (( ! private_install )); then
  global_prefix="$(npm prefix --global)" || fail '无法读取当前 npm 的全局安装目录。'
  global_root="$(npm root --global)" || fail '无法读取当前 npm 的全局模块目录。'
  [[ "$global_prefix" == /* && "$global_root" == /* ]] || fail '当前 npm 返回的全局目录无效。'
  if writable_directory "$global_prefix" && writable_directory "$global_root"; then
    prefix="$global_prefix"
    bin_dir="$prefix/bin"
    cli_path="$global_root/fnos-cli/bin/fnos"
  else
    existing_fnos="$(type -P fnos || true)"
    if [[ -f "$global_root/fnos-cli/package.json" || ( -n "$existing_fnos" && "$existing_fnos" != "$install_root/bin/fnos" ) ]]; then
      fail "已检测到 fnos，但当前 npm 全局目录不可写：${global_prefix}。请修复该目录的写入权限后重新运行，以更新原有安装。"
    fi
    printf '当前 npm 全局目录不可写，将安装到当前用户的独立目录。\n'
    private_install=1
  fi
fi

printf '正在通过 npm 安装最新版本的 fnos-cli……\n'
if (( private_install )); then
  npm install --global --prefix "$prefix" fnos-cli@latest || fail 'npm 安装失败，请根据上方错误提示处理后重试。'
  cli_path="$prefix/lib/node_modules/fnos-cli/bin/fnos"
  [[ -f "$cli_path" ]] || fail 'npm 未生成 fnos 可执行文件，请重新安装。'
  mkdir -p "$bin_dir"
  # %q quotes user paths, including spaces and apostrophes, for Bash.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'exec %q %q "$@"\n' "$node_path" "$cli_path"
  } > "$bin_dir/fnos"
  chmod +x "$bin_dir/fnos"
else
  printf '使用当前 npm 的全局安装目录：%s\n' "$prefix"
  npm install --global fnos-cli@latest || fail '当前 npm 环境安装或更新失败，请根据上方错误提示处理后重试；原安装位置保持不变。'
fi
[[ -f "$cli_path" && -x "$bin_dir/fnos" ]] || fail 'npm 未生成有效的 fnos 可执行文件，请检查 npm 的全局目录设置。'
"$bin_dir/fnos" --version || fail '安装的 fnos 无法运行，请检查当前 Node.js 环境。'

legacy_path_line='export PATH="$HOME/.local/share/fnos-cli/bin:$PATH"'
path_changed=0
if (( ! private_install )); then
  # Remove only the exact two-line block written by previous installers.
  fish_profile="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/fnos-cli.fish"
  fish_legacy_line="fish_add_path \"$install_root/bin\""
  fish_path_removed=0
  for profile in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.zshrc" "${ZDOTDIR:-$HOME}/.zshrc" "$fish_profile"; do
    [[ -f "$profile" ]] || continue
    rm -f "$work_dir/path-block-removed"
    ends_lf=0
    [[ -n "$(tail -c 1 "$profile")" ]] || ends_lf=1
    legacy_line="$legacy_path_line"
    if [[ "$profile" == "$fish_profile" ]]; then legacy_line="$fish_legacy_line"; fi
    awk -v legacy="$legacy_line" -v changed="$work_dir/path-block-removed" -v ends_lf="$ends_lf" '
      function emit(line) { if (emitted) printf "\n"; printf "%s", line; emitted=1; last_removed=0 }
      function flush_marker() { if (pending) emit("# fnos-cli"); pending=0 }
      $0 == "# fnos-cli" { flush_marker(); pending=1; next }
      pending && $0 == legacy { pending=0; last_removed=1; print 1 > changed; next }
      { flush_marker(); emit($0) }
      END { flush_marker(); if (emitted && (ends_lf || last_removed)) printf "\n" }
    ' "$profile" > "$work_dir/profile"
    if [[ -f "$work_dir/path-block-removed" ]]; then
      cat "$work_dir/profile" > "$profile"
      path_changed=1
      if [[ "$profile" == "$fish_profile" ]]; then fish_path_removed=1; fi
    fi
  done
  # fish_add_path may also persist the old directory in fish_user_paths.
  if [[ -f "$fish_profile" && "$(cat "$fish_profile")" == "$fish_legacy_line" ]]; then
    rm "$fish_profile"
    fish_path_removed=1
    path_changed=1
  fi
  if (( fish_path_removed )); then
    if command -v fish >/dev/null 2>&1; then
      fish -c 'set -U fish_user_paths (string match -v -- "$HOME/.local/share/fnos-cli/bin" $fish_user_paths)'
    fi
  fi
fi

if (( private_install )); then
  path_line="$legacy_path_line"
else
  printf -v path_line 'export PATH=%q:$PATH' "$bin_dir"
fi
add_path() {
  local profile="$1"
  if [[ ! -f "$profile" ]] || ! grep -Fqx "$path_line" "$profile"; then
    printf '\n# fnos-cli\n%s\n' "$path_line" >> "$profile"
    path_changed=1
  fi
}
path_needed=1
case ":$PATH:" in *":$bin_dir:"*) path_needed=0 ;; esac
if (( private_install || path_needed )); then
  case "${SHELL:-/bin/sh}" in
    */zsh)
      zsh_dir="${ZDOTDIR:-$HOME}"
      mkdir -p "$zsh_dir"
      add_path "$zsh_dir/.zshrc"
      ;;
    */bash)
      add_path "$HOME/.bashrc"
      if [[ -f "$HOME/.bash_profile" ]]; then
        add_path "$HOME/.bash_profile"
      elif [[ -f "$HOME/.bash_login" ]]; then
        add_path "$HOME/.bash_login"
      else
        add_path "$HOME/.profile"
      fi
      ;;
    */fish)
      fish_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d"
      mkdir -p "$fish_dir"
      printf -v fish_line 'fish_add_path "%s"' "$bin_dir"
      if [[ ! -f "$fish_dir/fnos-cli.fish" ]] || ! grep -Fqx "$fish_line" "$fish_dir/fnos-cli.fish"; then
        printf '\n# fnos-cli\n%s\n' "$fish_line" >> "$fish_dir/fnos-cli.fish"
        path_changed=1
      fi
      ;;
    *) add_path "$HOME/.profile" ;;
  esac
fi
print_activation() {
  case "${SHELL:-/bin/sh}" in
    */fish) printf '如需立即在当前终端使用本次安装的 fnos（fish），请运行：\n  fish_add_path "%s"\n' "$bin_dir" ;;
    *) printf '如需立即在当前终端使用本次安装的 fnos（bash/zsh），请运行：\n  %s\n' "$path_line" ;;
  esac
}
printf '\n安装完成！命令位置：%s\n' "$bin_dir/fnos"
active_launcher="$(type -P fnos || true)"
if (( path_changed )); then
  printf '终端路径配置已更新，请关闭并重新打开终端，然后运行：\n\n  fnos --help\n\n'
  print_activation
elif [[ -z "$active_launcher" || ! "$active_launcher" -ef "$bin_dir/fnos" ]]; then
  printf '当前终端的 PATH 尚未优先使用上述命令位置，请检查终端路径配置。\n'
  print_activation
else
  printf '当前环境可以直接使用，请运行：\n\n  fnos --help\n'
fi
