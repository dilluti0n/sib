#!/usr/bin/env bash
# Copyright 2026 Hee-Suk Kim <hskim@dilluti0n.com>
# SPDX-License-Identifier: GPL-3.0-only

test_description='sib init and the dispatcher'

. "$(dirname -- "$0")/test-lib.sh"

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

printf 'first turn' | sib ask -c >/dev/null

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

switch_err=$(
    export SIB_DIR="$TMPDIR_ROOT/unborn-store"
    sib init >/dev/null 2>&1
    c=$(printf '{"content":"x"}' | sib chain-jsonl)
    sib switch "$c" 2>&1 >/dev/null | sed "s/$c/C/g; s/${c:0:7}/c/"
) || fail "switch from an unborn HEAD failed"

assert_eq "switch to C (c) from (unborn)" \
    "$switch_err" \
    "switch from an unborn HEAD reports it without git errors"

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

test_done
