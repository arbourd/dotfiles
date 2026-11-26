#!/bin/sh
set -eu

if [ "$(uname -s)" != Darwin ]; then
	printf '%s\n' 'install.sh only supports macOS' >&2
	exit 1
fi

case "$(uname -m)" in
	arm64) arch=arm64 ;;
	x86_64) arch=amd64 ;;
	*) printf 'unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

archive="dot_darwin_${arch}.tar.gz"
base_url=https://github.com/arbourd/dotfiles/releases/latest/download
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

if [ -n "${DOT_INSTALL_FROM:-}" ]; then
	cp "$DOT_INSTALL_FROM/$archive" "$tmp_dir/$archive"
	cp "$DOT_INSTALL_FROM/checksums.txt" "$tmp_dir/checksums.txt"
else
	curl -fsSL "$base_url/$archive" -o "$tmp_dir/$archive"
	curl -fsSL "$base_url/checksums.txt" -o "$tmp_dir/checksums.txt"
fi

if ! awk -v name="$archive" '$2 == name { print; found = 1 } END { if (!found) exit 1 }' \
	"$tmp_dir/checksums.txt" > "$tmp_dir/archive-checksum.txt"; then
	printf 'checksum entry not found for %s\n' "$archive" >&2
	exit 1
fi

(cd "$tmp_dir" && shasum -a 256 -c archive-checksum.txt)
tar -xzf "$tmp_dir/$archive" -C "$tmp_dir"
mkdir -p "$HOME/.local/bin"
cp "$tmp_dir/dot" "$HOME/.local/bin/dot"
chmod 755 "$HOME/.local/bin/dot"

case ":${PATH:-}:" in
	*":$HOME/.local/bin:"*) ;;
	*) printf 'Add %s/.local/bin to your PATH to run dot directly.\n' "$HOME" ;;
esac

"$HOME/.local/bin/dot" init "$@"
