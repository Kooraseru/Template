#!/usr/bin/env bash

set -euo pipefail

# Resolve the pinned tool metadata relative to this script.
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_directory/../../../../" && pwd -P)"
configuration="$project_root/.vscode/luau/lute/runtime.toml"
foreman_configuration="$project_root/.vscode/luau/lute/foreman.toml"

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

version="$(sed -n 's/^[[:space:]]*lute[[:space:]]*=[[:space:]]*{.*version[[:space:]]*=[[:space:]]*"=\([^"]*\)".*}.*/\1/p' "$foreman_configuration")"
if [[ -z $version ]]; then
	printf '%s\n' '.vscode/luau/lute/foreman.toml:1:1:2: error: missing exact Lute version' >&2
	exit 2
fi

# Pick the release archive for MSYS2 Windows or GitHub's Linux runner.
case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) platform_os=windows ;;
	Linux*) platform_os=linux ;;
	*)
		printf '.github/ci/tooling/lute/bootstrap.sh:1:1:2: error: unsupported Lute platform %s\n' "$(uname -s)" >&2
		exit 2
		;;
esac

machine="$(uname -m)"
case "$machine" in
	x86_64|amd64) platform_arch=x86_64 ;;
	aarch64|arm64)
		if [[ $platform_os == windows ]]; then
			# Lute ships only a Windows x64 build; Windows ARM64 runs it through x64 emulation.
			platform_arch=x86_64
		else
			platform_arch=aarch64
		fi
		;;
	*)
		printf '.github/ci/tooling/lute/bootstrap.sh:1:1:2: error: unsupported Lute architecture %s\n' "$machine" >&2
		exit 2
		;;
esac

platform="$platform_os-$platform_arch"
checksum="$(read_setting lute.checksums "$platform")"
executable_checksum="$(read_setting lute.executables "$platform")"
if [[ -z $checksum || -z $executable_checksum ]]; then
	printf '.vscode/luau/lute/runtime.toml:1:1:2: error: no checksum for %s\n' "$platform" >&2
	exit 2
fi

binary_name=lute
if [[ $platform_os == windows ]]; then
	binary_name=lute.exe
fi
install_directory="$project_root/build/run/dependencies/lute/$version"
binary="$install_directory/$binary_name"

verify_checksum() {
	local expected=$1
	local path=$2
	if command -v sha256sum >/dev/null 2>&1; then
		printf '%s  %s\n' "$expected" "$path" | sha256sum --check --status
	else
		printf '%s  %s\n' "$expected" "$path" | shasum -a 256 --check --status
	fi
}

# Download and verify the immutable versioned archive before extracting it.
install_lute() {
	local archive="$install_directory/lute.zip"
	mkdir -p "$install_directory"
	curl --silent --show-error --fail --location --retry 3 \
		"https://github.com/luau-lang/lute/releases/download/v$version/lute-$platform.zip" \
		--output "$archive"
	verify_checksum "$checksum" "$archive"
	if command -v unzip >/dev/null 2>&1; then
		unzip -o "$archive" -d "$install_directory" >/dev/null
	elif command -v bsdtar >/dev/null 2>&1; then
		bsdtar -xf "$archive" -C "$install_directory"
	else
		printf '%s\n' '.github/ci/tooling/lute/bootstrap.sh:1:1:2: error: install unzip or bsdtar to extract Lute' >&2
		return 1
	fi
	rm -f "$archive"
	if [[ $platform_os != windows ]]; then
		chmod +x "$binary"
	fi
}

# Nightly binaries report only their base version, so verify the executable bytes.
ensure_lute() {
	if [[ ! -f $binary ]] || ! verify_checksum "$executable_checksum" "$binary"; then
		install_lute
	fi
	if ! verify_checksum "$executable_checksum" "$binary"; then
		printf '.github/ci/tooling/lute/bootstrap.sh:1:1:2: error: Lute %s executable checksum mismatch\n' "$version" >&2
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
