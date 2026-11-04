#!/usr/bin/env bash

set -euo pipefail

# Resolve the pinned tool metadata relative to this script.
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_directory/../.." && pwd -P)"
configuration="$project_root/repo/config/ci/dependencies/lute.toml"

read_setting() {
	local section=$1
	local key=$2
	awk -v wanted_section="[$section]" -v wanted_key="$key" '
		{ sub(/\r$/, "") }
		$0 == wanted_section { active = 1; next }
		/^\[/ { active = 0 }
		active && $1 == wanted_key {
			gsub(/"/, "", $3)
			print $3
			exit
		}
	' "$configuration"
}

version="$(read_setting lute version)"
if [[ -z $version ]]; then
	printf '%s\n' 'repo/config/ci/dependencies/lute.toml:1:1:2: error: missing lute.version' >&2
	exit 2
fi

# Pick the release archive for MSYS2 Windows or GitHub's Linux runner.
case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) platform_os=windows ;;
	Linux*) platform_os=linux ;;
	*)
		printf 'dependencies/lute/bootstrap.sh:1:1:2: error: unsupported Lute platform %s\n' "$(uname -s)" >&2
		exit 2
		;;
esac

machine="$(uname -m)"
case "$machine" in
	x86_64|amd64) platform_arch=x86_64 ;;
	*)
		printf 'dependencies/lute/bootstrap.sh:1:1:2: error: unsupported Lute architecture %s\n' "$machine" >&2
		exit 2
		;;
esac

platform="$platform_os-$platform_arch"
checksum="$(read_setting lute.checksums "$platform")"
if [[ -z $checksum ]]; then
	printf 'repo/config/ci/dependencies/lute.toml:1:1:2: error: no checksum for %s\n' "$platform" >&2
	exit 2
fi

binary_name=lute
if [[ $platform_os == windows ]]; then
	binary_name=lute.exe
fi
install_directory="$project_root/build/run/dependencies/artifacts/lute/$version"
binary="$install_directory/$binary_name"

# Download and verify the immutable versioned archive before extracting it.
install_lute() {
	local archive="$install_directory/lute.zip"
	mkdir -p "$install_directory"
	curl --silent --show-error --fail --location --retry 3 \
		"https://github.com/luau-lang/lute/releases/download/v$version/lute-$platform.zip" \
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
	else
		printf '%s\n' 'dependencies/lute/bootstrap.sh:1:1:2: error: install unzip or bsdtar to extract Lute' >&2
		return 1
	fi
	rm -f "$archive"
	if [[ $platform_os != windows ]]; then
		chmod +x "$binary"
	fi
}

# Keep a matching cached binary; reinstall if its reported version differs.
ensure_lute() {
	local actual_version=""
	if [[ -f $binary ]]; then
		actual_version="$("$binary" --version 2>/dev/null || true)"
	fi
	if [[ $actual_version != "$version" && $actual_version != "Lute $version" && $actual_version != "lute $version" ]]; then
		install_lute
		actual_version="$("$binary" --version 2>/dev/null || true)"
	fi
	if [[ $actual_version != "$version" && $actual_version != "Lute $version" && $actual_version != "lute $version" ]]; then
		printf 'dependencies/lute/bootstrap.sh:1:1:2: error: expected Lute %s, got %s\n' "$version" "${actual_version:-an unreadable binary}" >&2
		return 1
	fi
}

ensure_lute
case "${1:-}" in
	--install)
		if [[ -n ${GITHUB_PATH:-} ]]; then
			path="$install_directory"
			if [[ $platform_os == windows ]] && command -v cygpath >/dev/null 2>&1; then
				path="$(cygpath --windows "$path")"
			fi
			printf '%s\n' "$path" >>"$GITHUB_PATH"
		fi
		;;
	--print-path)
		printf '%s\n' "$binary"
		;;
	*)
		child_binary="$binary"
		if [[ $platform_os == windows ]] && command -v cygpath >/dev/null 2>&1; then
			child_binary="$(cygpath --windows "$binary")"
		fi
		exec "$child_binary" "$@"
		;;
esac
