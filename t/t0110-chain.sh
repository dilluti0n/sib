#!/usr/bin/env bash
# Copyright 2026 Hee-Suk Kim <hskim@dilluti0n.com>
# SPDX-License-Identifier: GPL-3.0-only

test_description='Chain plumbing: chain-trace, chain-jsonl, ls-chain, rev-jsonl'

. "$(dirname -- "$0")/test-lib.sh"

sib init >/dev/null 2>&1

raw_blob=$(printf '%s' 'raw payload' | sib git hash-object -w --stdin)
raw_trace=$(printf '%s\tcontent\n' "$raw_blob" | sib mktrace)
rich_trace=$(printf '%s' '{"role":"user","content":"rich"}' | json_trace)

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
# JSONL failure behavior and traversal
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
    "rev-jsonl rejects an unknown extra argument" \
    sib rev-jsonl "$jsonl_with_blanks" unexpected

log_chain=$(
    printf '%s\n' \
        '{"role":"user","x":"m1\nm2\n\n","content":"a\nb\nc"}' \
        '{}' \
        '{"role":"only"}' \
        '{"role":"user","x":"m1\nm2\n\n","content":"a\nb\nc"}' |
        sib chain-jsonl
)
log_ids=($(sib git rev-list --reverse "$log_chain"))
user_turn="role: user
x: m1
m2

a
b
c"

assert_eq "chain ${log_ids[0]}
$user_turn

---

chain ${log_ids[1]}


---

chain ${log_ids[2]}
role: only


---

chain ${log_ids[3]}
$user_turn" "$(sib log "$log_chain")" \
    "log prints every chain, including shared and empty traces"

assert_eq "chain ${log_ids[2]}
role: only" "$(sib show "${log_ids[2]}")" \
    "show prints one chain in the log layout"

assert_eq "$(sib show "$log_chain")" "$(sib log -1 "$log_chain")" \
    "show is log -1"

assert_eq "" "$(sib log "$log_chain" 2>&1 >/dev/null)" \
    "log keeps stderr quiet on empty trace and missing content"

test_done
