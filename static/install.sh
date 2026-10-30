#!/usr/bin/env bash
# fnos-cli user-local installer for Linux and macOS (Bash 3.2+).
set -Eeuo pipefail

fail() { printf '\nInstallation failed: %s\n' "$*" >&2; exit 1; }
trap 'printf "\nInstallation failed. Check the error above and run the installer again.\n" >&2' ERR

[[ -n "${HOME:-}" && "$HOME" == /* ]] || fail 'HOME must be an absolute path.'
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
      printf 'Download attempt %s/3 failed.\n' "$attempt" >&2
    done
    fail "Could not download $1. Check your network and try again."
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet --timeout=30 --tries=3 "$1" -O "$2"
  else
    fail 'Please install curl or wget, then run this installer again.'
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

printf 'Installing fnos-cli for the current user...\n'
if ! runtime_ok && [[ -f "$install_root/node-path" ]]; then
  IFS= read -r runtime_dir < "$install_root/node-path"
  if [[ -x "$runtime_dir/bin/node" ]]; then export PATH="$runtime_dir/bin:$PATH"; fi
fi
if ! runtime_ok; then
  case "$(uname -s)" in
    Linux) platform=linux ;;
    Darwin) platform=darwin ;;
    *) fail 'Unsupported OS. Use the Windows installer or install with npm.' ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=x64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) fail 'Unsupported architecture. Automatic installation supports x64 and ARM64.' ;;
  esac
  command -v tar >/dev/null 2>&1 || fail 'Please install tar and gzip, then try again.'
  if command -v sha256sum >/dev/null 2>&1; then
    hash_command=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    hash_command=(shasum -a 256)
  else
    fail 'Please install sha256sum or shasum, then try again.'
  fi
  printf 'Downloading Node.js 24 LTS (includes npm) from nodejs.org...\n'
  download 'https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt' "$work_dir/SHASUMS256.txt"
  entry="$(awk -v suffix="-${platform}-${arch}.tar.gz" '$2 ~ /^node-v24\.[0-9]+\.[0-9]+-/ && substr($2, length($2)-length(suffix)+1) == suffix {print $1 " " $2; exit}' "$work_dir/SHASUMS256.txt")"
  read -r expected_hash archive <<< "$entry"
  [[ "${expected_hash:-}" =~ ^[a-fA-F0-9]{64}$ && "${archive:-}" =~ ^node-v24\.[0-9]+\.[0-9]+- ]] || fail 'Invalid Node.js download manifest.'
  version="${archive#node-}"
  version="${version%%-*}"
  download "https://nodejs.org/dist/$version/$archive" "$work_dir/node.tar.gz"
  actual_hash="$("${hash_command[@]}" "$work_dir/node.tar.gz")"
  [[ "${actual_hash%% *}" == "$expected_hash" ]] || fail 'Node.js checksum mismatch. Please retry the download.'
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
  runtime_ok || fail 'Node.js could not run. Check OS support (Linux needs compatible glibc; macOS needs a supported version).'
  printf '%s\n' "$runtime_dir" > "$install_root/node-path"
fi

node_path="$(type -P node)"
printf 'Installing the latest fnos-cli from npm...\n'
npm install --global --prefix "$prefix" fnos-cli@latest
cli_path="$prefix/lib/node_modules/fnos-cli/bin/fnos"
[[ -f "$cli_path" ]] || fail 'npm did not create the fnos executable.'
"$node_path" "$cli_path" --version

mkdir -p "$bin_dir"
# %q quotes user paths, including spaces and apostrophes, for Bash.
{
  printf '#!/usr/bin/env bash\n'
  printf 'exec %q %q "$@"\n' "$node_path" "$cli_path"
} > "$bin_dir/fnos"
chmod +x "$bin_dir/fnos"
"$bin_dir/fnos" --version

path_line='export PATH="$HOME/.local/share/fnos-cli/bin:$PATH"'
add_path() {
  local profile="$1"
  if [[ ! -f "$profile" ]] || ! grep -Fqx "$path_line" "$profile"; then
    printf '\n# fnos-cli\n%s\n' "$path_line" >> "$profile"
  fi
}
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
    printf 'fish_add_path "%s"\n' "$bin_dir" > "$fish_dir/fnos-cli.fish"
    ;;
  *) add_path "$HOME/.profile" ;;
esac
printf '\nInstallation complete! Close and reopen your terminal, then run:\n\n  fnos --help\n\n'
printf 'To use fnos in this terminal immediately (bash/zsh):\n  %s\n' "$path_line"
