#!/usr/bin/env bash
# https://github.com/olivergondza/bash-strict-mode
set -eEuo pipefail
trap 's=$?; echo >&2 "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"

function main() {
    if [[ $# -ne 2 ]]; then
        echo >&2 "Usage: $0 [IMAGE_A] [IMAGE_B]"
        exit 1
    fi
    local img_a=$1
    local img_b=$2

    inv_a="$(mktemp -d gitops-must-gather-A-XXXX)"
    inv_b="$(mktemp -d gitops-must-gather-B-XXXX)"
    trap "rm -rf '${inv_a}' '${inv_b}'" EXIT

    gather "$img_a" "$inv_a"
    gather "$img_b" "$inv_b"

    diff --color=auto --recursive \
        --ignore-matching-lines="resourceVersion: " \
        "${inv_a}" "${inv_b}"
}

function gather() {
    image=$1
    dir=$2

    if ! oc adm must-gather --image="$image" --dest-dir="${dir}" 2>&1 | tee "${dir}/oc-adm-output.log"; then
        echo >&2 "Failed gathering for $image"
        return 1
    fi

    sanitize "$image" "$dir"
}

function sanitize() {
    image=$1
    dir=$2

    # Unify names of the directories its name is based on image name
    mv "$dir"/*-sha256-* "$dir/__RESOURCES__"

    # In log files, drop image name, generated resource names, timestamp, line numbers, and transfer metrics
    sed -i -r \
        -e "s~${image}~__IMAGE_TAG__~g" \
        -e "s~must-gather-[a-z0-9]{5}~must-gather-XXXXX~g" \
        -e 's~[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z~__TIMESTAMP__~g' \
        -e 's~gather_gitops:[0-9]+~gather_gitops:LL~g' \
        -e '/total size is .* speedup is .*/d' \
        -e '/sent .* received .* bytes\/sec/d' \
        "$dir/oc-adm-output.log" "$dir/must-gather.logs" "$dir/__RESOURCES__/gather.logs" "$dir/__RESOURCES__/gather_gitops.log"

    # Timestamps are not going to match, just test there is the same number of them
    wc -l < "$dir/timestamp" > "$dir/timestamp"
    wc -l < "$dir/__RESOURCES__/timestamp" > "$dir/__RESOURCES__/timestamp"
}

main "$@"
