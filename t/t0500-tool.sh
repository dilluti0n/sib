#!/usr/bin/env bash
# Copyright 2026 Hee-Suk Kim <hskim@dilluti0n.com>
# SPDX-License-Identifier: GPL-3.0-only

test_description='sib tool, ask -j and contrib tools'

. "$(dirname -- "$0")/test-lib.sh"

sib init >/dev/null 2>&1

tools_file="$TMPDIR_ROOT/tools.json"
printf '%s' '[{"type":"function","name":"f","parameters":{"type":"object","properties":{}}}]' >"$tools_file"

sib config set sib.tools "$tools_file"
assert_contains "$(env -u PLM_TOOLS sib status)" "Tools:    $tools_file" \
    "sib.tools configuration sets PLM_TOOLS"
sib config unset sib.tools

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

assert_eq "function_call_output" "$(sib show HEAD:type)" \
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

status=0
printf '%s\n' '{"type":"function_call_output","call_id":"call_7"}' |
    sib ask -j -c >/dev/null 2>&1 || status=$?
assert_eq "0" "$status" "sib ask -j -c accepts an item without content"
sib switch HEAD~ 2>/dev/null

assert_eq $'call_9\ncall_8\nmock assistant' \
    "$(sib rev-jsonl HEAD | tail -n 3 | jq -r '.call_id // .content')" \
    "sib ask -j keeps input order and appends the response"

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
assert_contains "$(env -u PLM_TOOLS sib status)" "Tools:    $SIB_DIR/tools/tools.json" \
    "PLM_TOOLS defaults to \$SIB_DIR/tools/tools.json"
rm -f "$SIB_DIR/tools/tools.json"

assert_eq "" "$(env -u PLM_TOOLS sib status | grep Tools: || :)" \
    "PLM_TOOLS stays unset without tools.json"

assert_eq "ok" \
    "$(printf '%s' '{"command":"echo ok"}' | "$SOURCE_DIR/contrib/tools/bash")" \
    "contrib bash tool runs the command"

status=0
ask_out=$(printf 'use a tool' | MOCK_FUNCTION_CALL_ONCE="$TMPDIR_ROOT/fc-once" sib ask -n 2>/dev/null) ||
    status=$?
assert_eq "0" "$status" "sib ask runs the tool and asks again"

assert_contains "$ask_out" "function_call_output: got:{}err" \
    "sib ask shows the tool output"

assert_eq $'message\nfunction_call\nfunction_call_output\nmessage' \
    "$(sib rev-jsonl HEAD | jq -r .type)" \
    "sib ask chains call, tool output and the final message"

assert_eq "got:{}err" "$(sib rev-jsonl HEAD | jq -rs '.[2].content')" \
    "sib ask stores the tool output"

printf '%s\n' '{"type":"function_call","call_id":"call_old","name":"echo_args","content":"{}"}' |
    sib ask -n -j -c >/dev/null
printf 'go' | MOCK_FUNCTION_CALL_ONCE="$TMPDIR_ROOT/fc-old" sib ask >/dev/null 2>&1
assert_eq "call_once" \
    "$(sib rev-jsonl HEAD | jq -r 'select(.type == "function_call_output") | .call_id')" \
    "sib ask runs only the calls of the latest response"

#
# contrib sib tool
#

cp "$SOURCE_DIR/contrib/tools/sib" "$SIB_DIR/tools/sib"

assert_eq "message" \
    "$(printf '%s' '{"args":["show","HEAD:type"]}' | "$SIB_DIR/tools/sib")" \
    "contrib sib tool passes args to sib"

assert_eq "sib ask is not allowed from this tool" \
    "$(printf '%s' '{"args":["ask","-c"]}' | "$SIB_DIR/tools/sib" || :)" \
    "contrib sib tool refuses ask"

status=0
printf 'original' |
    MOCK_FUNCTION_CALL_ONCE="$TMPDIR_ROOT/fc-edit" MOCK_FC_NAME=sib \
    MOCK_FC_ARGS='{"args":["edit","HEAD~1"],"content":"edited"}' \
    sib ask -n >/dev/null 2>&1 || status=$?
assert_eq "0" "$status" "sib ask runs the sib tool"

assert_eq $'edited\nsib\nfunction_call_output\nmock assistant' \
    "$(sib rev-jsonl HEAD | jq -r 'if .type == "message" then .content elif .type == "function_call" then .name else .type end')" \
    "sib ask continues from the chain edited by the sib tool"

test_done
