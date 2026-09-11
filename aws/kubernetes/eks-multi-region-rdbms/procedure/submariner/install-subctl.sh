#!/bin/bash
set -euo pipefail

# Installs the subctl CLI. Must be sourced so that the PATH change survives:
#
#   source ./install-subctl.sh
#
# Executed instead of sourced, the install would succeed and the PATH change
# would vanish with the subshell, which reads as a broken install rather than a
# misuse. Refuse that outright. `exit` is safe here precisely because this
# branch only runs when the script is NOT sourced.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "ERROR: source this script, do not execute it: . ${BASH_SOURCE[0]}" >&2
    echo "       Executed, subctl is installed but PATH is left unchanged." >&2
    exit 1
fi

# renovate: datasource=github-releases depName=submariner-io/releases
SUBCTL_VERSION=0.24.0

case "$(uname -s)-$(uname -m)" in
Darwin-x86_64) platform=darwin-amd64 ;;
Darwin-arm64) platform=darwin-arm64 ;;
Linux-x86_64) platform=linux-amd64 ;;
Linux-aarch64) platform=linux-arm64 ;;
*)
    echo "ERROR: unsupported platform $(uname -s)/$(uname -m)." >&2
    false
    ;;
esac

archive="subctl-v${SUBCTL_VERSION}-${platform}.tar.gz"
base_url="https://github.com/submariner-io/releases/releases/download/v${SUBCTL_VERSION}"

# The download runs in a subshell so the temporary directory is removed on every
# path out, including a failed curl, without a trap. Traps are the wrong tool in
# a sourced file: an EXIT trap would fire only when the CALLER's shell exits and
# would clobber the caller's own trap, and a RETURN trap also fires when this
# file returns, when the local below is already out of scope, which aborts a
# caller running under `set -u`.
camunda::_fetch_subctl() {
    local tmp_dir status=0
    tmp_dir="$(mktemp -d)"

    (
        set -euo pipefail

        curl -fLsS "$base_url/$archive" -o "$tmp_dir/$archive"
        curl -fLsS "$base_url/subctl-checksums.txt" -o "$tmp_dir/subctl-checksums.txt"

        expected_sha="$(grep " $archive$" "$tmp_dir/subctl-checksums.txt" | cut -d' ' -f1)"
        if command -v sha256sum >/dev/null 2>&1; then
            actual_sha="$(sha256sum "$tmp_dir/$archive" | cut -d' ' -f1)"
        else
            actual_sha="$(shasum -a 256 "$tmp_dir/$archive" | cut -d' ' -f1)"
        fi
        if [ -z "$expected_sha" ] || [ "$actual_sha" != "$expected_sha" ]; then
            echo "ERROR: checksum verification failed for $archive." >&2
            exit 1
        fi

        tar -xzf "$tmp_dir/$archive" -C "$tmp_dir"
        mkdir -p "$HOME/.local/bin"
        install -m 0755 "$tmp_dir/subctl-v${SUBCTL_VERSION}/subctl" "$HOME/.local/bin/subctl"
    ) || status=$?

    rm -rf "$tmp_dir"
    return "$status"
}

camunda::_fetch_subctl

# `$HOME` rather than `~`: the tilde does expand after a colon in an assignment,
# but the rule is obscure enough that every reader has to look it up, and in the
# profile line below `~` would be expanded when the line is WRITTEN, baking this
# machine's home into a file meant to be read on any.
export PATH="$HOME/.local/bin:$PATH"
# shellcheck disable=SC2016 # deliberate: $PATH and $HOME must expand when the
# profile is read, not when this line is written into it.
profile_line='export PATH="$HOME/.local/bin:$PATH"'
# Appended once. Re-running this script is normal, and every extra copy makes
# the profile a little longer and PATH a little more repetitive.
if ! grep -qxF "$profile_line" "$HOME/.profile" 2>/dev/null; then
    echo "$profile_line" >>"$HOME/.profile"
fi

subctl version
