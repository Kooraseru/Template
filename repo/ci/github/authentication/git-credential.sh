#!/usr/bin/env bash

set -euo pipefail

# Git invokes this helper only while pushing the generated CI workflow branch.
if [[ ${1:-} != get ]]; then
	exit 0
fi

# Confirm the requested HTTPS host before sharing the scoped installation token.
protocol=""
host=""
while IFS='=' read -r key value; do
	if [[ -z $key ]]; then
		break
	fi
	case "$key" in
		protocol) protocol="$value" ;;
		host) host="$value" ;;
	esac
done

expected_host="${CI_GIT_SERVER_URL:-https://github.com}"
expected_host="${expected_host#https://}"
expected_host="${expected_host%%/*}"
if [[ $protocol != https || $host != "$expected_host" || -z ${CI_GIT_BOOTSTRAP_TOKEN:-} ]]; then
	exit 1
fi

# Send credentials through Git's stdin/stdout protocol, never through the remote URL.
printf 'username=x-access-token\npassword=%s\n\n' "$CI_GIT_BOOTSTRAP_TOKEN"
