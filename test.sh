# Copyright 2026 Hee-Suk Kim <hskim@dilluti0n.com>
# SPDX-License-Identifier: GPL-3.0-only

set -Eeuo pipefail

#
# Sib v0.1 release test
#
# Environment:
#   SIB_SOURCE_DIR=/path/to/sib/source bash test.sh
#   TEST_KEEP=1 bash test.sh
#

SOURCE_DIR="${SIB_SOURCE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"

TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sib-test.XXXXXX")
RUNTIME="$TMPDIR_ROOT/runtime"
export SIB_DIR="$TMPDIR_ROOT/store"

tests=0

cleanup() {
    local status=$?

    if [[ -n ${TEST_KEEP:-} || $status -ne 0 ]]; then
        printf '\nTest directory preserved at:\n  %s\n' "$TMPDIR_ROOT" >&2
    else
        rm -rf "$TMPDIR_ROOT"
    fi

    exit "$status"
}
trap cleanup EXIT

fail() {
    printf '\nnot ok %d - %s\n' "$((tests + 1))" "$*" >&2
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

#
# Build an isolated runtime.
#
# The copied runtime ensures our mock plm-wrap/plm-send take precedence
# over programs installed on the developer's machine.
#

mkdir -p "$RUNTIME"

[[ -f "$SOURCE_DIR/sib" ]] ||
    fail "cannot find $SOURCE_DIR/sib"

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
            jq -nc '{type: "function_call", call_id: "call_once", name: "echo_args", content: "{}"}'
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
    command -v "$dependency" >/dev/null ||
        fail "missing dependency: $dependency"
done

pass "dependencies are available"

#
# 1. Initialization
#

sib init >/dev/null 2>&1

[[ -d $SIB_DIR ]] ||
    fail "sib init did not create the store"
pass "sib init creates the store"

initial_head=$(sib symbolic-ref HEAD)
assert_eq \
    "refs/conv/scratch" \
    "$initial_head" \
    "fresh store uses the internal unborn ref"

expect_fail \
    "fresh store has no scratch ref" \
    sib show-ref refs/conv/scratch

expect_fail \
    "fresh unborn HEAD does not resolve to a chain" \
    sib rev-parse HEAD

status=$(sib status)
assert_contains "$status" "(unborn)" \
    "status reports unborn HEAD"

#
# 2. Trace and JSONL plumbing
#

trace=$(
    printf '%s' '{"role":"user","content":"hello","model":"mock"}' |
        sib mktrace-json
)

assert_eq "hello" "$(sib ls-trace-json "$trace" | jq -r .content)" \
    "trace JSON round-trips string content"

expect_input_fail \
    "trace rejects a nested object value" \
    '{"content":{"nested":true}}' \
    sib mktrace-json

expect_input_fail \
    "trace rejects an array value" \
    '{"content":["one","two"]}' \
    sib mktrace-json

expect_input_fail \
    "trace rejects a numeric value" \
    '{"content":123}' \
    sib mktrace-json

expect_input_fail \
    "trace rejects a null value" \
    '{"content":null}' \
    sib mktrace-json

jsonl_chain=$(
    printf '%s\n' \
        '{"role":"user","content":"one"}' \
        '{"role":"assistant","content":"two"}' |
        sib chain-jsonl
)

assert_eq "2" "$(commit_count "$jsonl_chain")" \
          "chain-jsonl creates a multi-turn chain"

assert_eq \
    $'one\ntwo' \
    "$(sib rev-jsonl "$jsonl_chain" | jq -r .content)" \
    "rev-jsonl reconstructs turns in root-to-tip order"

#
# 3. First turn
#

printf 'first turn' | sib ask -c >/dev/null

first=$(head_hash)

assert_eq "" "$(parent_of "$first")" \
    "first turn is a root commit"

assert_eq "user" "$(field role "$first")" \
    "first turn has user role"

assert_eq "first turn" "$(field content "$first")" \
    "first turn preserves content"

#
# 4. Save
#

sib save work >/dev/null 2>&1

assert_eq "$first" "$(sib rev-parse work)" \
    "save creates refs/conv/<name>"

saved_names=$(sib save -l)
assert_contains "$saved_names" "work" \
    "save -l lists saved conversations"

sib save -- -h >/dev/null 2>&1

assert_eq "$first" "$(sib rev-parse conv/-h)" \
    "save supports -- before a dash-prefixed name"

sib save -d -- -h >/dev/null 2>&1

expect_fail \
    "save -d deletes a dash-prefixed name" \
    sib rev-parse conv/-h

expect_fail \
    "save rejects an invalid ref name" \
    sib save 'bad..name'

# expect_fail \
#     "save -l rejects positional arguments" \
#     sib save -l unexpected

#
# 5. Symbolic switch and ask
#
#
#   sib switch <chain-ish>  -> direct HEAD
#   sib switch -f <ref>     -> symbolic HEAD
#

sib switch -f work

assert_symbolic_head \
    "refs/conv/work" \
    "switch -f makes HEAD follow a ref"

work_before=$(sib rev-parse work)

printf 'followed turn' | sib ask -c >/dev/null

work_after=$(sib rev-parse work)

assert_ne "$work_before" "$work_after" \
    "ask advances the followed conversation ref"

assert_eq "$work_after" "$(head_hash)" \
    "symbolic HEAD resolves to the advanced ref"

assert_symbolic_head \
    "refs/conv/work" \
    "ask preserves explicit symbolic mode"

assert_eq "$work_before" "$(parent_of "$work_after")" \
    "followed turn is chained onto the previous tip"

#
# 6. Explicit detach
#

sib switch HEAD

assert_direct_head \
    "switch HEAD detaches at the current position"

assert_eq "$work_after" "$(head_hash)" \
    "switch HEAD preserves the current chain position"

assert_eq "$work_after" "$(sib rev-parse work)" \
    "detaching does not move the followed ref"

#
# 7. Start a new root
#

old_head=$(head_hash)

printf 'new root' | sib ask -n -c >/dev/null

new_root=$(head_hash)

assert_ne "$old_head" "$new_root" \
    "ask -n moves HEAD to a new conversation"

assert_direct_head \
    "ask -n leaves HEAD direct"

assert_eq "" "$(parent_of "$new_root")" \
    "ask -n creates a root commit"

assert_eq "new root" "$(field content "$new_root")" \
    "ask -n stores the new root content"

assert_eq "$work_after" "$(sib rev-parse work)" \
    "ask -n does not taint an existing saved ref"

#
# 8. Full successful ask
#

before_full_ask=$(head_hash)

printf 'normal request' | sib ask >/dev/null

after_full_ask=$(head_hash)
assistant_parent=$(parent_of "$after_full_ask")

assert_eq "assistant" "$(field role "$after_full_ask")" \
    "normal ask leaves an assistant turn at HEAD"

assert_eq "user" "$(field role "$assistant_parent")" \
    "normal ask creates a user turn before the assistant turn"

assert_eq "normal request" "$(field content "$assistant_parent")" \
    "normal ask preserves user request content"

assert_eq "$before_full_ask" "$(parent_of "$assistant_parent")" \
    "normal ask chains both new turns correctly"

#
# 9. Editing and descendant replay
#

printf 'edit one' | sib ask -n -c >/dev/null
edit_root=$(head_hash)

printf 'edit two' | sib ask -c >/dev/null
edit_middle=$(head_hash)

printf 'edit three' | sib ask -c >/dev/null
edit_tip=$(head_hash)

assert_eq "3" "$(commit_count HEAD)" \
    "edit fixture contains three turns"

EDIT_CONTENT='edited root' \
EDITOR="$RUNTIME/test-editor" \
    sib edit "$edit_root" >/dev/null

mapfile -t edit_commits < <(sib rev-list HEAD)

assert_eq "3" "${#edit_commits[@]}" \
    "editing a root replays all descendants"

assert_eq "edited root" "$(field content "${edit_commits[0]}")" \
    "root edit replaces root content"

assert_eq "edit two" "$(field content "${edit_commits[1]}")" \
    "root edit preserves first descendant trace"

assert_eq "edit three" "$(field content "${edit_commits[2]}")" \
    "root edit preserves second descendant trace"

middle_after_root_edit=${edit_commits[1]}

EDIT_CONTENT='edited middle' \
EDITOR="$RUNTIME/test-editor" \
    sib edit "$middle_after_root_edit" >/dev/null

mapfile -t edit_commits < <(sib rev-list HEAD)

assert_eq "3" "${#edit_commits[@]}" \
    "editing a middle turn preserves chain length"

assert_eq "edited root" "$(field content "${edit_commits[0]}")" \
    "middle edit preserves its parent"

assert_eq "edited middle" "$(field content "${edit_commits[1]}")" \
    "middle edit replaces target content"

assert_eq "edit three" "$(field content "${edit_commits[2]}")" \
    "middle edit replays its descendant"

#
# 10. Editing through symbolic HEAD
#

sib save editwork >/dev/null 2>&1
sib switch -f editwork

symbolic_edit_before=$(sib rev-parse editwork)

EDIT_CONTENT='edited tip' \
EDITOR="$RUNTIME/test-editor" \
    sib edit HEAD >/dev/null

symbolic_edit_after=$(sib rev-parse editwork)

assert_ne "$symbolic_edit_before" "$symbolic_edit_after" \
    "editing advances a followed ref"

assert_symbolic_head \
    "refs/conv/editwork" \
    "editing preserves symbolic HEAD"

assert_eq "edited tip" "$(field content HEAD)" \
    "tip edit replaces content"

assert_eq "$symbolic_edit_after" "$(head_hash)" \
    "symbolic HEAD resolves to the edited tip"

#
# 11. Direct switch from a saved shorthand
#

sib switch work

assert_direct_head \
    "ordinary switch always produces direct HEAD"

assert_eq "$(sib rev-parse work)" "$(head_hash)" \
    "switch resolves refs/conv shorthand"

#
# 12. Core command robustness
#

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
# 12.1 init and dispatcher argument handling
#

head_before_reinit=$(sib git rev-parse HEAD)
model_before_reinit=$(sib config get sib.model)
endpoint_before_reinit=$(sib config get sib.endpoint)

sib init >/dev/null 2>&1

assert_eq "$head_before_reinit" "$(sib git rev-parse HEAD)" \
    "reinitialization preserves HEAD"

assert_eq "$model_before_reinit" "$(sib config get sib.model)" \
    "reinitialization preserves model configuration"

assert_eq "$endpoint_before_reinit" "$(sib config get sib.endpoint)" \
    "reinitialization preserves endpoint configuration"

expect_fail \
    "init rejects unexpected positional arguments" \
    sib init unexpected

expect_fail \
    "dispatcher rejects an unknown command" \
    sib command-that-does-not-exist

expect_fail \
    "commands reject a non-Sib SIB_DIR" \
    env SIB_DIR="$TMPDIR_ROOT/not-a-store" "$RUNTIME/sib" status

mkdir -p "$TMPDIR_ROOT/not-a-store"

expect_fail \
    "commands reject an existing non-Git SIB_DIR" \
    env SIB_DIR="$TMPDIR_ROOT/not-a-store" "$RUNTIME/sib" status

#
# 12.2 raw trace construction
#

raw_blob=$(
    printf '%s' 'raw payload' |
        sib git hash-object -w --stdin
)

raw_trace=$(
    printf '%s\tcontent\n' "$raw_blob" | sib mktrace
)

assert_match "$raw_trace" '^[0-9a-f]{40,64}$' \
    "mktrace prints a valid object ID"

assert_eq "raw payload" \
    "$(sib ls-trace-json "$raw_trace" | jq -r .content)" \
    "mktrace accepts the documented key/hash format"

empty_trace=$(sib mktrace </dev/null)

assert_json_eq '{}' "$(sib ls-trace-json "$empty_trace")" \
    "mktrace creates an empty logical trace"

expect_input_fail \
    "mktrace rejects duplicate keys" \
    "$(printf 'content\t%s\ncontent\t%s\n' "$raw_blob" "$raw_blob")" \
    sib mktrace

expect_input_fail \
    "mktrace rejects a line without an object ID" \
    'content' \
    sib mktrace

expect_input_fail \
    "mktrace rejects a line with extra fields" \
    "$(printf 'content\t%s\textra\n' "$raw_blob")" \
    sib mktrace

expect_input_fail \
    "mktrace rejects an empty key" \
    "$(printf '\t%s\n' "$raw_blob")" \
    sib mktrace

expect_input_fail \
    "mktrace rejects an invalid object ID" \
    'content	not-an-object-id' \
    sib mktrace

expect_input_fail \
    "mktrace rejects a missing object" \
    'content	0000000000000000000000000000000000000001' \
    sib mktrace

expect_input_fail \
    "mktrace rejects unexpected positional arguments" \
    "$(printf 'content\t%s\n' "$raw_blob")" \
    sib mktrace unexpected

#
# 12.3 JSON trace fidelity and validation
#

rich_json='{
    "role": "user",
    "content": "line 1\nline\t2: 안녕 😀",
    "empty": ""
}'

rich_trace=$(
    printf '%s' "$rich_json" |
        sib mktrace-json
)

assert_json_eq "$rich_json" "$(sib ls-trace-json "$rich_trace")" \
    "JSON trace preserves multiline, tab, Unicode, and empty strings"

expect_input_fail \
    "mktrace-json rejects invalid JSON" \
    '{"content":' \
    sib mktrace-json

expect_input_fail \
    "mktrace-json rejects a top-level string" \
    '"content"' \
    sib mktrace-json

expect_input_fail \
    "mktrace-json rejects an empty key" \
    '{"":"value"}' \
    sib mktrace-json

expect_input_fail \
    "mktrace-json rejects a whitespace-containing key" \
    '{"bad key":"value"}' \
    sib mktrace-json

expect_input_fail \
    "mktrace-json rejects a tab-containing key" \
    '{"bad\tkey":"value"}' \
    sib mktrace-json

expect_input_fail \
    "mktrace-json rejects a slash-containing key" \
    '{"bad/key":"value"}' \
    sib mktrace-json

colon_json='{"sib:model":"m","content":"x"}'
assert_json_eq "$colon_json" \
    "$(sib ls-trace-json "$(printf '%s' "$colon_json" | sib mktrace-json)")" \
    "mktrace-json accepts a colon-containing key"

expect_input_fail \
    "mktrace-json rejects a key starting with colon" \
    '{":model":"value"}' \
    sib mktrace-json

expect_input_fail \
    "mktrace-json rejects unexpected positional arguments" \
    '{"content":"value"}' \
    sib mktrace-json unexpected

#
# 12.4 trace schema and object integrity
#

expect_fail \
    "ls-trace rejects a blob object" \
    sib ls-trace "$raw_blob"

expect_fail \
    "ls-trace rejects a nonexistent object" \
    sib ls-trace 0000000000000000000000000000000000000001

expect_fail \
    "ls-trace requires exactly one argument" \
    sib ls-trace "$raw_trace" "$empty_trace"

expect_fail \
    "ls-trace-json requires exactly one argument" \
    sib ls-trace-json "$raw_trace" "$empty_trace"

#
# 12.5 chain construction and deterministic commits
#

deterministic_root_a=$(sib chain-trace "$raw_trace")
deterministic_root_b=$(sib chain-trace "$raw_trace")

assert_eq "$deterministic_root_a" "$deterministic_root_b" \
    "identical root trace construction is deterministic"

deterministic_child_a=$(
    sib chain-trace -p "$deterministic_root_a" "$rich_trace"
)

deterministic_child_b=$(
    sib chain-trace -p "$deterministic_root_a" "$rich_trace"
)

assert_eq "$deterministic_child_a" "$deterministic_child_b" \
    "identical child trace construction is deterministic"

assert_eq "$deterministic_root_a" \
    "$(parent_of "$deterministic_child_a")" \
    "chain-trace installs the exact requested parent"

assert_eq "999999999" \
    "$(sib git show -s --format=%at "$deterministic_root_a")" \
    "chain-trace uses the fixed author timestamp"

assert_eq "999999999" \
    "$(sib git show -s --format=%ct "$deterministic_root_a")" \
    "chain-trace uses the fixed committer timestamp"

assert_eq "Sibyl <sib@local>" \
    "$(sib git show -s --format='%an <%ae>' "$deterministic_root_a")" \
    "chain-trace uses the fixed author identity"

assert_eq "Sibyl <sib@local>" \
    "$(sib git show -s --format='%cn <%ce>' "$deterministic_root_a")" \
    "chain-trace uses the fixed committer identity"

assert_eq "$raw_trace" \
    "$(sib ls-chain "$deterministic_root_a" |
        awk '$1 == "trace" { print $2; exit }')" \
    "ls-chain exposes the commit trace"

expect_fail \
    "chain-trace rejects a blob as a trace" \
    sib chain-trace "$raw_blob"

expect_fail \
    "chain-trace rejects incomplete -p arguments" \
    sib chain-trace -p "$deterministic_root_a"

expect_fail \
    "chain-trace rejects extra arguments" \
    sib chain-trace "$raw_trace" unexpected

expect_fail \
    "ls-chain rejects a non-commit object" \
    sib ls-chain "$raw_trace"

expect_fail \
    "ls-chain requires exactly one argument" \
    sib ls-chain "$deterministic_root_a" unexpected

#
# 12.6 JSONL failure behavior and traversal
#

jsonl_with_blanks=$(
    printf '\n%s\n\n%s\n\n' \
        '{"role":"user","content":"blank one"}' \
        '{"role":"assistant","content":"blank two"}' |
        sib chain-jsonl
)

assert_eq "2" "$(commit_count "$jsonl_with_blanks")" \
    "chain-jsonl ignores blank lines"

assert_eq \
    $'blank one\nblank two' \
    "$(sib rev-jsonl "$jsonl_with_blanks" | jq -r .content)" \
    "blank-line JSONL preserves nonblank turn order"

expect_input_fail \
    "chain-jsonl rejects empty input" \
    '' \
    sib chain-jsonl

expect_input_fail \
    "chain-jsonl rejects whitespace-only input" \
    $' \n\t\n' \
    sib chain-jsonl

expect_input_fail \
    "chain-jsonl rejects malformed JSON at any line" \
    $'{"content":"good"}\n{"content":\n' \
    sib chain-jsonl

expect_input_fail \
    "chain-jsonl rejects non-string values at any line" \
    $'{"content":"good"}\n{"content":42}\n' \
    sib chain-jsonl

expect_input_fail \
    "chain-jsonl rejects unexpected positional arguments" \
    '{"content":"value"}' \
    sib chain-jsonl unexpected

jsonl_appended=$(
    printf '%s\n' \
        '{"role":"user","content":"three"}' \
        '{"role":"assistant","content":"four"}' |
        sib chain-jsonl -p "$jsonl_chain"
)

assert_eq "4" "$(commit_count "$jsonl_appended")" \
    "chain-jsonl -p appends to an existing chain"

assert_eq \
    $'one\ntwo\nthree\nfour' \
    "$(sib rev-jsonl "$jsonl_appended" | jq -r .content)" \
    "chain-jsonl -p keeps parent turns first"

assert_eq "$jsonl_chain" \
    "$(parent_of "$(parent_of "$jsonl_appended")")" \
    "chain-jsonl -p installs the exact requested parent"

expect_input_fail \
    "chain-jsonl rejects incomplete -p arguments" \
    '{"content":"value"}' \
    sib chain-jsonl -p

expect_input_fail \
    "chain-jsonl rejects an invalid parent" \
    '{"content":"value"}' \
    sib chain-jsonl -p revision-that-does-not-exist

expect_fail \
    "rev-jsonl rejects an invalid revision" \
    sib rev-jsonl revision-that-does-not-exist

expect_fail \
    "rev-jsonl requires exactly one argument" \
    sib rev-jsonl "$jsonl_with_blanks" unexpected

#
# 12.7 rev-parse resolution and option safety
#

sib update-ref \
    -m "test: core shorthand" \
    refs/conv/core-short \
    "$deterministic_root_a"

assert_eq "$deterministic_root_a" "$(sib rev-parse core-short)" \
    "rev-parse resolves refs/conv shorthand"

sib update-ref \
    -m "test: named HEAD" \
    refs/conv/HEAD \
    "$deterministic_root_a"

current_head_for_resolution=$(sib git rev-parse HEAD)

assert_eq "$current_head_for_resolution" "$(sib rev-parse HEAD)" \
    "rev-parse gives real HEAD priority over refs/conv/HEAD"

assert_eq "$deterministic_root_a" "$(sib rev-parse conv/HEAD)" \
    "rev-parse can explicitly resolve refs/conv/HEAD"

expect_fail \
    "rev-parse refuses revision options as chain names" \
    sib rev-parse --all

expect_fail \
    "rev-parse refuses end-of-options injection" \
    sib rev-parse --end-of-options

expect_fail \
    "rev-parse rejects multiple arguments" \
    sib rev-parse HEAD HEAD

#
# 12.8 ref plumbing and compare-and-swap
#

sib update-ref \
    -m "test: create CAS ref" \
    refs/conv/core-cas \
    "$deterministic_root_a"

expect_fail \
    "update-ref rejects a compare-and-swap mismatch" \
    sib update-ref \
        -m "test: bad CAS" \
        refs/conv/core-cas \
        "$deterministic_child_a" \
        0000000000000000000000000000000000000000

assert_eq "$deterministic_root_a" \
    "$(sib show-ref refs/conv/core-cas)" \
    "failed compare-and-swap leaves the ref unchanged"

sib update-ref \
    -m "test: good CAS" \
    refs/conv/core-cas \
    "$deterministic_child_a" \
    "$deterministic_root_a"

assert_eq "$deterministic_child_a" \
    "$(sib show-ref refs/conv/core-cas)" \
    "update-ref supports compare-and-swap updates"

expect_fail \
    "show-ref rejects a missing exact ref" \
    sib show-ref refs/conv/core-missing

expect_fail \
    "show-ref requires exactly one argument" \
    sib show-ref refs/conv/core-cas refs/conv/work
#
# 12.9 config quoting and environment precedence
#

sib config set sib.robustness.value 'value with spaces'

assert_eq "value with spaces" \
    "$(sib config get sib.robustness.value)" \
    "config preserves arguments containing spaces"

sib config set sib.model configured-core-model
sib config set sib.endpoint https://configured.example.invalid/v1

cat >"$RUNTIME/sib-core-probe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'model=%s\n' "$PLM_MODEL"
printf 'endpoint=%s\n' "$PLM_ENDPOINT"

for argument in "$@"; do
    printf 'arg=<%s>\n' "$argument"
done
EOF
chmod +x "$RUNTIME/sib-core-probe"

probe_output=$(
    env -u PLM_MODEL -u PLM_ENDPOINT \
        sib core-probe 'argument with spaces' --literal)

assert_contains "$probe_output" 'model=configured-core-model' \
    "dispatcher exports the configured model to external commands"

assert_contains "$probe_output" \
    'endpoint=https://configured.example.invalid/v1' \
    "dispatcher exports the configured endpoint to external commands"

assert_contains "$probe_output" 'arg=<argument with spaces>' \
    "dispatcher preserves an argument containing spaces"

assert_contains "$probe_output" 'arg=<--literal>' \
    "dispatcher preserves dash-prefixed external command arguments"

probe_output=$(
    PLM_MODEL=environment-core-model \
    PLM_ENDPOINT=https://environment.example.invalid/v1 \
        sib core-probe
)

assert_contains "$probe_output" 'model=environment-core-model' \
    "PLM_MODEL environment value overrides configuration"

assert_contains "$probe_output" \
    'endpoint=https://environment.example.invalid/v1' \
    "PLM_ENDPOINT environment value overrides configuration"

#
# A sib-<name> executable must not override a built-in cmd_<name>.
#

cat >"$RUNTIME/sib-rev-parse" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'external command incorrectly selected'
exit 99
EOF
chmod +x "$RUNTIME/sib-rev-parse"

assert_eq "$(sib git rev-parse HEAD)" "$(sib rev-parse HEAD)" \
    "built-in commands take priority over sib-* executables"

rm -f "$RUNTIME/sib-rev-parse"

#
# Restore user-facing configuration for any later tests or inspection.
#

sib config set sib.model "$model_before_reinit"
sib config set sib.endpoint "$endpoint_before_reinit"


#
# plm-wrap key format (real plm-wrap, not the mock)
#

PLM_WRAP="$SOURCE_DIR/plm-wrap"

raw_response='{
  "id": "resp_1", "object": "response", "status": "completed", "model": "m1",
  "output": [
    {"type": "reasoning", "id": "rs_1", "status": "completed",
     "summary": [{"type": "summary_text", "text": "a"}, {"type": "summary_text", "text": "b"}],
     "encrypted_content": "ENC"},
    {"type": "function_call", "id": "fc_1", "status": "completed",
     "call_id": "call_1", "name": "get_weather", "arguments": "{\"city\":\"Seoul\"}"},
    {"type": "web_search_call", "id": "ws_1", "status": "completed"},
    {"type": "message", "id": "msg_1", "status": "incomplete", "role": "assistant",
     "content": [{"type": "output_text", "text": "x", "annotations": []},
                 {"type": "output_text", "text": "y", "annotations": []}]}
  ]
}'

assert_eq \
    "$(jq -c . <<'EOF'
{"type":"reasoning","content":"a\n\nb","encrypted_content":"ENC","sib:model":"m1"}
{"type":"function_call","call_id":"call_1","name":"get_weather","content":"{\"city\":\"Seoul\"}","sib:model":"m1"}
{"type":"message","role":"assistant","content":"x\n\ny","status":"incomplete","sib:model":"m1"}
EOF
)" \
    "$("$PLM_WRAP" -f response -t plm <<<"$raw_response")" \
    "plm-wrap maps each output item to one plm line"

assert_eq \
    '{"type":"message","role":"user","content":"hi\n"}' \
    "$(printf 'hi\n' | "$PLM_WRAP" -f text -t plm)" \
    "plm-wrap text input is a typed user message"

plm_chain='{"type":"message","role":"user","content":"q","sib:model":"m1"}
{"type":"reasoning","content":"a","encrypted_content":"ENC"}
{"type":"reasoning","content":"no enc"}
{"type":"function_call","call_id":"call_1","name":"f","content":"{}","status":"completed"}
{"type":"function_call_output","call_id":"call_1","name":"f","content":"out"}
{"type":"web_search_call","content":"skip"}'

assert_eq \
    "$(jq -c . <<'EOF'
[{"type":"message","role":"user","content":"q"},
 {"type":"reasoning","summary":[{"type":"summary_text","text":"a"}],"encrypted_content":"ENC"},
 {"type":"function_call","call_id":"call_1","name":"f","arguments":"{}"},
 {"type":"function_call_output","call_id":"call_1","output":"out"}]
EOF
)" \
    "$(PLM_MODEL=m PLM_USE_STREAM=false "$PLM_WRAP" -f plm -t request <<<"$plm_chain" | jq -c .input)" \
    "plm-wrap builds request input from per-type whitelist"

assert_eq \
    '[{"type":"message","role":"assistant","content":"a"},{"type":"message","role":"user","content":"q"}]' \
    "$(printf '%s\n' '{"role":"assistant","content":"a","model":"m"}' '{"role":"user","content":"q"}' |
        PLM_MODEL=m PLM_USE_STREAM=false "$PLM_WRAP" -f plm -t request | jq -c .input)" \
    "plm-wrap treats lines without type as messages"

response_chain=$("$PLM_WRAP" -f response -t plm <<<"$raw_response" | sib chain-jsonl)

assert_eq "3" "$(commit_count "$response_chain")" \
    "one response with three known items chains three commits"

tools_file="$TMPDIR_ROOT/tools.json"
printf '%s' '[{"type":"function","name":"f","parameters":{"type":"object","properties":{}}}]' >"$tools_file"

tool_request=$(printf '%s\n' '{"type":"message","role":"user","content":"q"}' |
    PLM_MODEL=m PLM_USE_STREAM=false PLM_TOOLS="$tools_file" "$PLM_WRAP" -f plm -t request)

assert_eq "$(jq -c . "$tools_file")" "$(jq -c .tools <<<"$tool_request")" \
    "plm-wrap passes PLM_TOOLS verbatim as tools"

assert_eq "null" "$(jq -c .tool_choice <<<"$tool_request")" \
    "plm-wrap omits tool_choice by default"

assert_eq "null" \
    "$(printf '%s\n' '{"content":"q"}' |
        PLM_MODEL=m PLM_USE_STREAM=false "$PLM_WRAP" -f plm -t request | jq -c .tools)" \
    "plm-wrap omits tools when PLM_TOOLS is unset"

assert_eq '"required"' \
    "$(printf '%s\n' '{"content":"q"}' |
        PLM_MODEL=m PLM_USE_STREAM=false PLM_TOOL_CHOICE=required \
        "$PLM_WRAP" -f plm -t request | jq -c .tool_choice)" \
    "plm-wrap passes a string tool_choice"

assert_eq '{"type":"function","name":"f"}' \
    "$(printf '%s\n' '{"content":"q"}' |
        PLM_MODEL=m PLM_USE_STREAM=false PLM_TOOL_CHOICE='{"type":"function","name":"f"}' \
        "$PLM_WRAP" -f plm -t request | jq -c .tool_choice)" \
    "plm-wrap passes a JSON object tool_choice"

printf '{}' >"$TMPDIR_ROOT/bad-tools.json"
expect_input_fail \
    "plm-wrap rejects tools that are not an array" \
    '{"content":"q"}' \
    env PLM_MODEL=m PLM_USE_STREAM=false PLM_TOOLS="$TMPDIR_ROOT/bad-tools.json" \
    "$PLM_WRAP" -f plm -t request

sib config set sib.tools "$tools_file"
assert_contains "$(env -u PLM_TOOLS sib status)" "PLM_TOOLS:    $tools_file" \
    "sib.tools configuration sets PLM_TOOLS"
sib config unset sib.tools

status=0
printf 'call a tool' | MOCK_FUNCTION_CALL=1 sib ask -n >/dev/null 2>&1 || status=$?
assert_eq "10" "$status" "sib ask exits 10 when the function_call has no tool"

assert_eq "function_call" "$(sib show -k type HEAD)" \
    "sib ask still commits the function_call before exiting 10"

status=0
printf 'plain' | sib ask >/dev/null 2>&1 || status=$?
assert_eq "0" "$status" "sib ask exits 0 when the response ends with a message"

#
# sib ask -j and sib tool
#

expect_fail "sib ask rejects -r with -j" sib ask -r -j

printf 'start' | MOCK_FUNCTION_CALL=1 sib ask -n >/dev/null 2>&1 || :
fc_head=$(sib rev-parse HEAD)

assert_json_eq '{"type":"function_call","call_id":"call_1","name":"f","content":"{}"}' \
    "$(sib tool pending)" \
    "tool pending lists a function_call without output"

assert_eq "" "$(sib tool pending "$(parent_of "$fc_head")")" \
    "tool pending prints nothing when no call is pending"

sib tool pending |
    jq -c '{type: "function_call_output", call_id, content: "result"}' |
    sib ask -j -c >/dev/null

assert_eq "function_call_output" "$(sib show -k type HEAD)" \
    "sib ask -j -c chains plm jsonl input as is"

assert_eq "$fc_head" "$(parent_of "$(sib rev-parse HEAD)")" \
    "sib ask -j chains on top of the function_call"

assert_eq "" "$(sib tool pending)" \
    "tool pending ignores calls answered by function_call_output"

status=0
printf '%s\n' \
    '{"type":"function_call_output","call_id":"call_9","content":"a"}' \
    '{"type":"function_call_output","call_id":"call_8","content":"b"}' |
    sib ask -j >/dev/null 2>&1 || status=$?
assert_eq "0" "$status" "sib ask -j sends after chaining several items"

assert_eq $'call_9\ncall_8\nmock assistant' \
    "$(sib rev-jsonl HEAD | tail -n 3 | jq -r '.call_id // .content')" \
    "sib ask -j keeps input order and appends the response"

#
# plm-send display (real plm-send with a fake curl)
#

FAKE_BIN="$TMPDIR_ROOT/fake-bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
cat "$FAKE_CURL_RESPONSE"
EOF
chmod +x "$FAKE_BIN/curl"

plm_send_display() {
    local display="$TMPDIR_ROOT/display"
    FAKE_CURL_RESPONSE=$1 PATH="$FAKE_BIN:$PATH" PLM_ENDPOINT=http://fake.invalid \
        "$SOURCE_DIR/plm-send" </dev/null >/dev/null 3>"$display"
    cat "$display"
}

fc_item='{"type":"function_call","call_id":"call_1","name":"get_weather","arguments":"{\"city\":\"Seoul\"}"}'
msg_item='{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hi"}]}'

{
    printf 'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n'
    printf 'event: response.output_text.delta\ndata: {"delta":"hi"}\n\n'
    printf 'event: response.output_text.done\ndata: {}\n\n'
    printf 'event: response.output_item.done\ndata: {"item":%s}\n\n' "$msg_item"
    printf 'event: response.output_item.done\ndata: {"item":%s}\n\n' "$fc_item"
    printf 'event: response.completed\ndata: {"response":{"output":[]}}\n\n'
} >"$TMPDIR_ROOT/stream.http"

assert_eq $'hi\nfunction_call: get_weather({"city":"Seoul"})' \
    "$(plm_send_display "$TMPDIR_ROOT/stream.http")" \
    "plm-send shows function calls in a stream"

{
    printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n'
    printf '{"output":[%s,%s]}\n' "$msg_item" "$fc_item"
} >"$TMPDIR_ROOT/json.http"

assert_eq $'hi\nfunction_call: get_weather({"city":"Seoul"})' \
    "$(plm_send_display "$TMPDIR_ROOT/json.http")" \
    "plm-send shows function calls in a JSON response"

#
# sib tool run and $SIB_DIR/tools
#

mkdir -p "$SIB_DIR/tools"
cat >"$SIB_DIR/tools/echo_args" <<'EOF'
#!/usr/bin/env bash
printf 'got:'; cat; echo err >&2; exit 3
EOF
chmod +x "$SIB_DIR/tools/echo_args"

assert_json_eq \
    '{"type":"function_call_output","call_id":"c1","content":"got:{\"a\":1}err"}' \
    "$(printf '%s\n' '{"type":"function_call","call_id":"c1","name":"echo_args","content":"{\"a\":1}"}' |
        sib tool run)" \
    "tool run passes arguments on stdin and captures stdout and stderr"

assert_eq $'c1\nc2' \
    "$(printf '%s\n' \
        '{"type":"function_call","call_id":"c1","name":"echo_args","content":"{}"}' \
        '{"type":"function_call","call_id":"c2","name":"echo_args","content":"{}"}' |
        sib tool run | jq -r .call_id)" \
    "tool run answers every call in order"

expect_input_fail \
    "tool run fails on an unknown tool" \
    '{"type":"function_call","call_id":"c1","name":"nope","content":"{}"}' \
    sib tool run

expect_input_fail \
    "tool run rejects a tool name with a path" \
    '{"type":"function_call","call_id":"c1","name":"../tools/echo_args","content":"{}"}' \
    sib tool run

assert_eq "" \
    "$(printf '%s\n' \
        '{"type":"function_call","call_id":"c1","name":"echo_args","content":"{}"}' \
        '{"type":"function_call","call_id":"c2","name":"nope","content":"{}"}' |
        sib tool run 2>/dev/null || :)" \
    "tool run runs nothing when any call fails"

assert_eq "" "$(sib tool run </dev/null)" \
    "tool run prints nothing for no calls"

printf '[]' >"$SIB_DIR/tools/tools.json"
assert_contains "$(env -u PLM_TOOLS sib status)" "PLM_TOOLS:    $SIB_DIR/tools/tools.json" \
    "PLM_TOOLS defaults to \$SIB_DIR/tools/tools.json"
rm -f "$SIB_DIR/tools/tools.json"

assert_eq "" "$(env -u PLM_TOOLS sib status | grep PLM_TOOLS || :)" \
    "PLM_TOOLS stays unset without tools.json"

assert_eq "ok" \
    "$(printf '%s' '{"command":"echo ok"}' | "$SOURCE_DIR/contrib/tools/bash")" \
    "contrib bash tool runs the command"

status=0
printf 'use a tool' | MOCK_FUNCTION_CALL_ONCE="$TMPDIR_ROOT/fc-once" sib ask -n >/dev/null 2>&1 ||
    status=$?
assert_eq "0" "$status" "sib ask runs the tool and asks again"

assert_eq $'message\nfunction_call\nfunction_call_output\nmessage' \
    "$(sib rev-jsonl HEAD | jq -r .type)" \
    "sib ask chains call, tool output and the final message"

assert_eq "got:{}err" "$(sib rev-jsonl HEAD | jq -rs '.[2].content')" \
    "sib ask stores the tool output"

#
# Final status
#

printf '\n1..%d\n' "$tests"
