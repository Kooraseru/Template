#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_directory/../../../.." && pwd)"
configuration="$root/repo/config/ci/dependencies/lune.toml"

read_setting() {
	local section=$1
	local key=$2
	awk -v wanted_section="[$section]" -v wanted_key="$key" '
		$0 == wanted_section { active = 1; next }
		/^\[/ { active = 0 }
		active && $1 == wanted_key {
			gsub(/"/, "", $3)
			print $3
			exit
		}
	' "$configuration"
}

version="$(read_setting lune version)"
if [[ -z $version ]]; then
	printf '%s\n' "repo/config/ci/dependencies/lune.toml:1:1:2: error: missing lune.version" >&2
	exit 2
fi

platform=""
case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) platform_os=windows ;;
	Darwin*) platform_os=macos ;;
	Linux*)
		if [[ -n ${USERPROFILE:-} && -n ${MSYSTEM:-} ]]; then
			platform_os=windows
		else
			platform_os=linux
		fi
		;;
	*)
		printf 'repo/ci/dependencies/lune/bootstrap.sh:1:1:2: error: unsupported Lune platform %s\n' "$(uname -s)" >&2
		exit 2
		;;
esac

machine="$(uname -m)"
if [[ ${MSYSTEM:-} == CLANGARM64 ]]; then
	machine=aarch64
fi
case "$machine" in
	x86_64|amd64) platform_arch=x86_64 ;;
	aarch64|arm64) platform_arch=aarch64 ;;
	*)
		printf 'repo/ci/dependencies/lune/bootstrap.sh:1:1:2: error: unsupported Lune architecture %s\n' "$machine" >&2
		exit 2
		;;
esac

platform="$platform_os-$platform_arch"
checksum="$(read_setting lune.checksums "$platform")"
if [[ -z $checksum ]]; then
	printf 'repo/config/ci/dependencies/lune.toml:1:1:2: error: no checksum for %s\n' "$platform" >&2
	exit 2
fi

binary_name=lune
if [[ $platform_os == windows ]]; then
	binary_name=lune.exe
fi
install_directory="$root/build/tools/lune/$version"
binary="$install_directory/$binary_name"

install_lune() {
	local archive="$install_directory/lune.zip"
	mkdir -p "$install_directory"
	curl --silent --show-error --fail --location --retry 3 \
		"https://github.com/lune-org/lune/releases/download/v$version/lune-$version-$platform.zip" \
		--output "$archive"
	if command -v sha256sum >/dev/null 2>&1; then
		printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --status
	else
		printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 --check --status
	fi
	if command -v unzip >/dev/null 2>&1; then
		unzip -o "$archive" -d "$install_directory" >/dev/null
	elif command -v bsdtar >/dev/null 2>&1; then
		bsdtar -xf "$archive" -C "$install_directory"
	elif command -v tar >/dev/null 2>&1; then
		tar -xf "$archive" -C "$install_directory"
	else
		printf '%s\n' 'repo/ci/dependencies/lune/bootstrap.sh:1:1:2: error: install unzip or bsdtar to extract the pinned Lune release' >&2
		return 1
	fi
	rm -f "$archive"
	if [[ $platform_os != windows ]]; then
		chmod +x "$binary"
	fi
}

ensure_lune() {
	local actual_version=""
	if [[ -f $binary ]]; then
		actual_version="$("$binary" --version 2>/dev/null || true)"
	fi
	if [[ $actual_version != "lune $version" ]]; then
		install_lune
		actual_version="$("$binary" --version 2>/dev/null || true)"
	fi
	if [[ $actual_version != "lune $version" ]]; then
		printf 'repo/ci/dependencies/lune/bootstrap.sh:1:1:2: error: expected Lune %s, got %s\n' "$version" "${actual_version:-an unreadable binary}" >&2
		return 1
	fi
}

case "${1:-}" in
	--install)
		ensure_lune
		if [[ -n ${GITHUB_PATH:-} ]]; then
			path="$install_directory"
			if [[ $platform_os == windows ]] && command -v cygpath >/dev/null 2>&1; then
				path="$(cygpath --windows "$path")"
			fi
			printf '%s\n' "$path" >>"$GITHUB_PATH"
		fi
		;;
	--print-path)
		ensure_lune
		printf '%s\n' "$binary"
		;;
	*)
		ensure_lune
		child_binary="$binary"
		if [[ $platform_os == windows ]] && command -v cygpath >/dev/null 2>&1; then
			child_binary="$(cygpath --windows "$binary")"
		fi
		CI_LUNE="$child_binary"
		export CI_LUNE
		exec "$binary" "$@"
		;;
esac
