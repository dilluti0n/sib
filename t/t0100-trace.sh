#!/usr/bin/env bash
# Copyright 2026 Hee-Suk Kim <hskim@dilluti0n.com>
# SPDX-License-Identifier: GPL-3.0-only

test_description='Trace plumbing: mktrace, ls-trace, and JSON traces'

. "$(dirname -- "$0")/test-lib.sh"

sib init >/dev/null 2>&1

trace=$(
    printf '%s' '{"role":"user","content":"hello","model":"mock"}' |
        json_trace
)

assert_eq "hello" "$(trace_json "$trace" | jq -r .content)" \
    "trace JSON round-trips string content"

expect_input_fail \
    "trace rejects a nested object value" \
    '{"content":{"nested":true}}' \
    sib chain-jsonl

expect_input_fail \
    "trace rejects an array value" \
    '{"content":["one","two"]}' \
    sib chain-jsonl

expect_input_fail \
    "trace rejects a numeric value" \
    '{"content":123}' \
    sib chain-jsonl

expect_input_fail \
    "trace rejects a null value" \
    '{"content":null}' \
    sib chain-jsonl

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
    "$(trace_json "$raw_trace" | jq -r .content)" \
    "mktrace accepts the documented key/hash format"

empty_trace=$(sib mktrace </dev/null)

assert_json_eq '{}' "$(trace_json "$empty_trace")" \
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
# JSON trace fidelity and validation
#

rich_json='{
    "role": "user",
    "content": "line 1\nline\t2: 안녕 😀",
    "empty": ""
}'

rich_trace=$(
    printf '%s' "$rich_json" |
        json_trace
)

assert_json_eq "$rich_json" "$(trace_json "$rich_trace")" \
    "JSON trace preserves multiline, tab, Unicode, and empty strings"

expect_input_fail \
    "chain-jsonl rejects invalid JSON" \
    '{"content":' \
    sib chain-jsonl

expect_input_fail \
    "chain-jsonl rejects a top-level string" \
    '"content"' \
    sib chain-jsonl

expect_input_fail \
    "chain-jsonl rejects an empty key" \
    '{"":"value"}' \
    sib chain-jsonl

expect_input_fail \
    "chain-jsonl rejects a whitespace-containing key" \
    '{"bad key":"value"}' \
    sib chain-jsonl

expect_input_fail \
    "chain-jsonl rejects a tab-containing key" \
    '{"bad\tkey":"value"}' \
    sib chain-jsonl

expect_input_fail \
    "chain-jsonl rejects a slash-containing key" \
    '{"bad/key":"value"}' \
    sib chain-jsonl

colon_json='{"sib:model":"m","content":"x"}'
assert_json_eq "$colon_json" \
    "$(trace_json "$(printf '%s' "$colon_json" | json_trace)")" \
    "chain-jsonl accepts a colon-containing key"

expect_input_fail \
    "chain-jsonl rejects a key starting with colon" \
    '{":model":"value"}' \
    sib chain-jsonl

#
# Trace schema and object integrity
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

test_done
