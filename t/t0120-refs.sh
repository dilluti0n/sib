#!/usr/bin/env bash
# Copyright 2026 Hee-Suk Kim <hskim@dilluti0n.com>
# SPDX-License-Identifier: GPL-3.0-only

test_description='Ref plumbing: rev-parse, update-ref, show-ref'

. "$(dirname -- "$0")/test-lib.sh"

sib init >/dev/null 2>&1
printf 'first turn' | sib ask -c >/dev/null

raw_trace=$(printf '%s' '{"content":"root"}' | sib mktrace-json)
deterministic_root_a=$(sib chain-trace "$raw_trace")
deterministic_child_a=$(sib chain-trace -p "$deterministic_root_a" "$raw_trace")

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
# Ref plumbing and compare-and-swap
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

test_done
