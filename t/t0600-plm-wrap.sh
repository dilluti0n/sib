#!/usr/bin/env bash
# Copyright 2026 Hee-Suk Kim <hskim@dilluti0n.com>
# SPDX-License-Identifier: GPL-3.0-only

test_description='plm-wrap (real plm-wrap, not the mock)'

. "$(dirname -- "$0")/test-lib.sh"

sib init >/dev/null 2>&1

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
{"type":"reasoning","id":"rs_1","content":"a","encrypted_content":"ENC"}
{"type":"reasoning","content":"","encrypted_content":"ENC2"}
{"type":"reasoning","content":"no enc"}
{"type":"function_call","call_id":"call_1","name":"f","content":"{}","status":"completed"}
{"type":"function_call_output","call_id":"call_1","name":"f","content":"out"}
{"type":"web_search_call","content":"skip"}'

assert_eq \
    "$(jq -c . <<'EOF'
[{"type":"message","role":"user","content":"q"},
 {"type":"reasoning","summary":[{"type":"summary_text","text":"a"}],"encrypted_content":"ENC"},
 {"type":"reasoning","summary":[],"encrypted_content":"ENC2"},
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
assert_eq "false" "$(jq -c .store <<<"$tool_request")" \
    "plm-wrap sends store false"

assert_eq '{"summary":"auto"}' "$(jq -c .reasoning <<<"$tool_request")" \
    "plm-wrap asks for reasoning summaries"

expect_input_fail \
    "plm-wrap rejects tools that are not an array" \
    '{"content":"q"}' \
    env PLM_MODEL=m PLM_USE_STREAM=false PLM_TOOLS="$TMPDIR_ROOT/bad-tools.json" \
    "$PLM_WRAP" -f plm -t request

err=$({ yes '{"content":"q"}' | head -n 100000 |
        PLM_MODEL=m PLM_TOOLS="$TMPDIR_ROOT" "$PLM_WRAP" -f plm -t request >/dev/null; } 2>&1) || :
assert_eq "err: $TMPDIR_ROOT: cannot read tools" "$err" \
    "plm-wrap reports an unreadable PLM_TOOLS in one line"

expect_input_fail \
    "plm-wrap requires PLM_MODEL for request" \
    '{"content":"q"}' \
    env -u PLM_MODEL "$PLM_WRAP" -f plm -t request

test_done
