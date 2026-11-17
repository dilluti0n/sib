# Copyright 2026 Hee-Suk Kim <hskim@dilluti0n.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Sourced by every t/tNNNN-*.sh after it sets test_description. Each
# test file gets its own empty SIB_DIR and runtime, prints TAP, and
# ends with test_done. Run a test file with --help to see what it tests.
#
# Environment:
#   SIB_SOURCE_DIR=/path/to/sib/source
#   TEST_KEEP=1   keep the test directory
#

set -Eeuo pipefail

case ${1:-} in
    -h|--help)
        printf '%s\n' "$test_description"
        exit 0
        ;;
esac

SOURCE_DIR="${SIB_SOURCE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sib-test.XXXXXX")
RUNTIME="$TMPDIR_ROOT/runtime"
export SIB_DIR="$TMPDIR_ROOT/store"

# Don't inherit the caller's plm configuration
unset $(compgen -v PLM_ || true)

tests=0

cleanup() {
    local status=$?

    if [[ -n ${TEST_KEEP:-} || $status -ne 0 ]]; then
        printf '\n%s: test directory preserved at:\n  %s\n' "$0" "$TMPDIR_ROOT" >&2
    else
        rm -rf "$TMPDIR_ROOT"
    fi

    exit "$status"
}
trap cleanup EXIT

fail() {
    printf 'not ok %d - %s\n' "$((tests + 1))" "$*"
    exit 1
}

pass() {
    tests=$((tests + 1))
    printf 'ok %d - %s\n' "$tests" "$1"
}

assert_eq() {
    local expected=$1
    local actual=$2
    local description=${3:-values are equal}

    if [[ $actual != "$expected" ]]; then
        printf '\nExpected:\n%s\n\nActual:\n%s\n' \
            "$expected" "$actual" >&2
        fail "$description"
    fi

    pass "$description"
}

assert_ne() {
    local left=$1
    local right=$2
    local description=${3:-values are different}

    [[ $left != "$right" ]] ||
        fail "$description: both values were $left"

    pass "$description"
}

assert_contains() {
    local haystack=$1
    local needle=$2
    local description=${3:-output contains expected text}

    [[ $haystack == *"$needle"* ]] || {
        printf '\nExpected output to contain:\n%s\n\nActual:\n%s\n' \
            "$needle" "$haystack" >&2
        fail "$description"
    }

    pass "$description"
}

expect_fail() {
    local description=$1
    shift

    if "$@" >/dev/null 2>&1; then
        fail "$description: command unexpectedly succeeded"
    fi

    pass "$description"
}

expect_input_fail() {
    local description=$1
    local input=$2
    shift 2

    if printf '%s' "$input" | "$@" >/dev/null 2>&1; then
        fail "$description: command unexpectedly succeeded"
    fi

    pass "$description"
}

head_hash() {
    sib rev-parse HEAD
}

field() {
    local key=$1
    local chain=${2:-HEAD}

    sib show -k "$key" "$chain"
}

parent_of() {
    local chain=$1

    sib ls-chain "$chain" |
        awk '$1 == "parent" { print $2; exit }'
}

commit_count() {
    local chain=${1:-HEAD}

    sib rev-list "$chain" | awk 'END { print NR }'
}

assert_direct_head() {
    local description=$1

    if sib symbolic-ref HEAD >/dev/null 2>&1; then
        fail "$description: HEAD is symbolic"
    fi

    sib rev-parse HEAD >/dev/null ||
        fail "$description: HEAD does not resolve"

    pass "$description"
}

assert_symbolic_head() {
    local expected=$1
    local description=$2
    local actual

    actual=$(sib symbolic-ref HEAD 2>/dev/null) ||
        fail "$description: HEAD is not symbolic"

    if [[ $actual != "$expected" ]]; then
        printf '\nExpected symbolic HEAD:\n%s\n\nActual:\n%s\n' \
            "$expected" "$actual" >&2
        fail "$description"
    fi

    pass "$description"
}

assert_match() {
    local value=$1
    local pattern=$2
    local description=${3:-value matches pattern}

    if [[ ! $value =~ $pattern ]]; then
        printf '\nExpected pattern:\n%s\n\nActual:\n%s\n' \
            "$pattern" "$value" >&2
        fail "$description"
    fi

    pass "$description"
}

assert_json_eq() {
    local expected=$1
    local actual=$2
    local description=${3:-JSON values are equal}
    local expected_normalized actual_normalized

    expected_normalized=$(jq -S -c . <<<"$expected") ||
        fail "$description: expected value is not valid JSON"

    actual_normalized=$(jq -S -c . <<<"$actual") ||
        fail "$description: actual value is not valid JSON"

    assert_eq "$expected_normalized" "$actual_normalized" "$description"
}

#
# Build an isolated runtime.
#
# The copied runtime ensures our mock plm-wrap/plm-send take precedence
# over programs installed on the developer's machine.
#

mkdir -p "$RUNTIME"

[[ -f "$SOURCE_DIR/sib" ]] || {
    printf 'Bail out! cannot find %s/sib\n' "$SOURCE_DIR"
    exit 1
}

cp "$SOURCE_DIR/sib" "$RUNTIME/"

for program in "$SOURCE_DIR"/sib-*; do
    [[ -f $program ]] || continue
    cp "$program" "$RUNTIME/"
done

chmod +x "$RUNTIME"/sib "$RUNTIME"/sib-*

export PATH="$RUNTIME:$PATH"

#
# Mock PLM programs
#

cat >"$RUNTIME/plm-wrap" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

from=
to=
role=

while (($#)); do
    case "$1" in
        -f)
            from=$2
            shift 2
            ;;
        -t)
            to=$2
            shift 2
            ;;
        -r)
            role=$2
            shift 2
            ;;
        *)
            echo "mock plm-wrap: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

case "$from:$to" in
    text:plm)
        jq -Rsc \
            --arg role user \
            --arg model "${PLM_MODEL:-mock-model}" \
            '{
                type: "message",
                role: $role,
                content: .,
                "sib:model": $model
            }'
        ;;

    plm:plm)
        cat
        ;;

    plm:request)
        # The mock provider does not care about the request format.
        cat
        ;;

    response:plm)
        # Consume the provider response.
        cat >/dev/null

        if [[ -n ${MOCK_FUNCTION_CALL_ONCE:-} && ! -e $MOCK_FUNCTION_CALL_ONCE ]]; then
            : >"$MOCK_FUNCTION_CALL_ONCE"
            jq -nc --arg name "${MOCK_FC_NAME:-echo_args}" --arg args "${MOCK_FC_ARGS:-"{}"}" \
                '{type: "function_call", call_id: "call_once", name: $name, content: $args}'
            exit
        fi

        if [[ -n ${MOCK_FUNCTION_CALL:-} ]]; then
            jq -nc '{type: "function_call", call_id: "call_1", name: "f", content: "{}"}'
            exit
        fi

        jq -nc \
            --arg role "${role:-assistant}" \
            --arg content "mock assistant" \
            --arg model "${PLM_MODEL:-mock-model}" \
            '{
                type: "message",
                role: $role,
                content: $content,
                "sib:model": $model
            }'
        ;;

    *)
        echo "mock plm-wrap: unsupported conversion: $from -> $to" >&2
        exit 2
        ;;
esac
EOF

cat >"$RUNTIME/plm-send" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat >/dev/null

if [[ -n ${MOCK_PLM_FAIL:-} ]]; then
    echo 'mock provider failure' >&2
    exit 42
fi

# fd 3 is Sib's human-readable streaming output.
printf 'mock assistant\n' >&3
printf '{"output":"mock assistant"}\n'
EOF

cat >"$RUNTIME/test-editor" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Accept flags like `code -w'
while [[ ${1-} == -* ]]; do shift; done

[[ $# -eq 1 ]] || {
    echo 'test-editor expects one file' >&2
    exit 2
}

: "${EDIT_CONTENT:?EDIT_CONTENT is required}"
printf '%s' "$EDIT_CONTENT" >"$1"
EOF

chmod +x \
    "$RUNTIME/plm-wrap" \
    "$RUNTIME/plm-send" \
    "$RUNTIME/test-editor"

#
# Dependency checks
#

for dependency in bash git jq awk sed grep sort uniq; do
    command -v "$dependency" >/dev/null || {
        printf 'Bail out! missing dependency: %s\n' "$dependency"
        exit 1
    }
done

test_done() {
    printf '1..%d\n' "$tests"
}
