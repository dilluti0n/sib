#!/usr/bin/env bash
# Copyright 2026 Hee-Suk Kim <hskim@dilluti0n.com>
# SPDX-License-Identifier: GPL-3.0-only

test_description='plm-send display (real plm-send with a fake curl)'

. "$(dirname -- "$0")/test-lib.sh"

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

sse() {
    printf 'event: %s\ndata: {"type":"%s"%s}\n\n' "$1" "$1" "${2:+,$2}"
}

sse_http() {
    printf 'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n'
    sse response.created
    "$@"
}

stream_body() {
    sse response.reasoning_summary_text.delta '"delta":"thin"'
    sse response.reasoning_summary_text.delta '"delta":"king"'
    sse response.reasoning_summary_text.done
    sse response.output_text.delta '"delta":"hi"'
    sse response.output_text.done
    sse response.output_item.done "\"item\":$msg_item"
    sse response.output_item.done "\"item\":$fc_item"
}

{
    sse_http stream_body
    sse response.completed '"response":{"id":"r1","output":[]}'
} >"$TMPDIR_ROOT/stream.http"

assert_eq $'thinking\n\nhi\nfunction_call: get_weather({"city":"Seoul"})' \
    "$(plm_send_display "$TMPDIR_ROOT/stream.http")" \
    "plm-send shows function calls in a stream"

plm_send() {
    FAKE_CURL_RESPONSE=$1 PATH="$FAKE_BIN:$PATH" PLM_ENDPOINT=http://fake.invalid \
        "$SOURCE_DIR/plm-send" </dev/null 3>/dev/null
}

assert_eq '{"id":"r1","output":[]}' \
    "$(plm_send "$TMPDIR_ROOT/stream.http" | jq -c .)" \
    "plm-send prints the completed response"

{
    sse_http stream_body
    sse response.incomplete \
        '"response":{"id":"r1","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}}'
} >"$TMPDIR_ROOT/incomplete.http"

out=$(plm_send "$TMPDIR_ROOT/incomplete.http" 2>"$TMPDIR_ROOT/err") ||
    fail "plm-send keeps an incomplete response"
assert_eq "r1" "$(jq -r .id <<<"$out")" "plm-send keeps an incomplete response"
assert_contains "$(cat "$TMPDIR_ROOT/err")" "max_output_tokens" \
    "plm-send warns about an incomplete response"

{
    sse_http stream_body
    sse response.failed \
        '"response":{"id":"r1","status":"failed","error":{"code":"server_error","message":"boom"}}'
} >"$TMPDIR_ROOT/failed.http"

expect_fail "plm-send fails on response.failed" plm_send "$TMPDIR_ROOT/failed.http"
assert_contains "$(plm_send "$TMPDIR_ROOT/failed.http" 2>&1 >/dev/null)" \
    "server_error: boom" "plm-send reports response.failed error"

{
    sse_http stream_body
    sse error '"code":"rate_limit_exceeded","message":"slow down"'
} >"$TMPDIR_ROOT/error.http"

expect_fail "plm-send fails on error event" plm_send "$TMPDIR_ROOT/error.http"
assert_contains "$(plm_send "$TMPDIR_ROOT/error.http" 2>&1 >/dev/null)" \
    "rate_limit_exceeded: slow down" "plm-send reports error event"

sse_http stream_body >"$TMPDIR_ROOT/truncated.http"
expect_fail "plm-send fails when the stream ends early" \
    plm_send "$TMPDIR_ROOT/truncated.http"

{
    printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n'
    printf '{"output":[%s,%s,%s]}\n' \
        '{"type":"reasoning","summary":[{"type":"summary_text","text":"thinking"}]}' \
        "$msg_item" "$fc_item"
} >"$TMPDIR_ROOT/json.http"

assert_eq $'thinking\n\nhi\nfunction_call: get_weather({"city":"Seoul"})' \
    "$(plm_send_display "$TMPDIR_ROOT/json.http")" \
    "plm-send shows function calls in a JSON response"

test_done
