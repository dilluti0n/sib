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
# Name resolution
#

assert_eq "$deterministic_root_a" "$(sib rev-parse refs/conv/core-short)" \
    "rev-parse takes full ref names as is"

sib update-ref refs/conv/core-pair "$deterministic_child_a"

assert_eq "$deterministic_root_a" "$(sib rev-parse core-pair~1)" \
    "rev-parse applies git suffixes to conversation names"

assert_eq "$deterministic_root_a" "$(sib rev-parse core-pair@{0}~1)" \
    "rev-parse reads a conversation's reflog"

sib git tag core-pair "$deterministic_root_a"

assert_eq "$deterministic_child_a" "$(sib rev-parse core-pair)" \
    "rev-parse never falls back to git DWIM for names"

assert_eq "$deterministic_root_a" "$(sib rev-parse refs/tags/core-pair)" \
    "rev-parse reaches other namespaces by full name"

expect_fail \
    "rev-parse does not resolve tags by short name" \
    sib rev-parse core-tag-only

short_root=$(sib git rev-parse --short "$deterministic_root_a")

sib update-ref refs/conv/"$short_root" "$deterministic_child_a"

expect_fail \
    "rev-parse rejects a name that is both a conversation and a hash" \
    sib rev-parse "$short_root"

assert_eq "$deterministic_child_a" "$(sib rev-parse conv/"$short_root")" \
    "conv/ disambiguates a conversation from a hash"

sib update-ref -d refs/conv/"$short_root"

assert_eq "$deterministic_root_a" "$(sib rev-parse "$short_root")" \
    "rev-parse resolves a short hash"

expect_fail \
    "rev-parse rejects tree paths" \
    sib rev-parse core-pair:content

#
# Ranges
#

assert_eq "$deterministic_child_a" "$(sib rev-list core-short..core-pair)" \
    "rev-list resolves names on both sides of a range"

assert_eq "$deterministic_child_a" "$(sib rev-list ^core-short core-pair)" \
    "rev-list resolves negated names"

assert_eq "root" "$(sib rev-jsonl --max-count=1 core-pair~1 | jq -r .content)" \
    "rev-jsonl resolves conversation names"

expect_fail \
    "rev-list rejects unknown names in a range" \
    sib rev-list core-missing..core-pair

#
# Ref names
#

assert_eq "refs/conv/core-pair" "$(sib rev-parse --ref core-pair)" \
    "rev-parse --ref maps a name to refs/conv/"

assert_eq "refs/conv/core-pair" "$(sib rev-parse --ref conv/core-pair)" \
    "rev-parse --ref strips conv/"

assert_eq "refs/conv/core-new" "$(sib rev-parse --ref core-new)" \
    "rev-parse --ref maps a name that does not exist yet"

assert_eq "refs/heads/x" "$(sib rev-parse --ref refs/heads/x)" \
    "rev-parse --ref keeps full ref names"

expect_fail \
    "rev-parse --ref rejects HEAD" \
    sib rev-parse --ref HEAD

expect_fail \
    "rev-parse --ref rejects a chain-ish" \
    sib rev-parse --ref core-pair~1

sib save conv/core-saved core-pair 2>/dev/null

assert_eq "$deterministic_child_a" "$(sib show-ref refs/conv/core-saved)" \
    "save stores conv/<name> at refs/conv/<name>"

#
# Chain plumbing takes chain-ish
#

assert_eq "$deterministic_root_a" \
    "$(sib ls-chain core-pair | awk '$1 == "parent" { print $2 }')" \
    "ls-chain resolves conversation names"

assert_eq "$deterministic_child_a" \
    "$(sib chain-trace -p core-short "$raw_trace")" \
    "chain-trace -p resolves conversation names"

assert_eq "$deterministic_child_a" \
    "$(printf '{"content":"root"}' | sib chain-jsonl -p core-short)" \
    "chain-jsonl -p resolves conversation names"

expect_fail \
    "ls-trace takes object ids only" \
    sib ls-trace core-pair

#
# Ref plumbing takes full ref names
#

expect_fail \
    "update-ref rejects a ref outside refs/" \
    sib update-ref core-loose "$deterministic_root_a"

assert_eq "" "$(ls "$SIB_DIR" | grep -x core-loose || :)" \
    "update-ref leaves no loose ref behind"

sib update-ref refs/conv/core-value core-pair

assert_eq "$deterministic_child_a" "$(sib show-ref refs/conv/core-value)" \
    "update-ref resolves its value as a chain-ish"

sib update-ref refs/conv/core-value core-pair~1 core-pair

assert_eq "$deterministic_root_a" "$(sib show-ref refs/conv/core-value)" \
    "update-ref resolves its old value as a chain-ish"

sib update-ref -d refs/conv/core-value core-pair~1

expect_fail \
    "update-ref -d removes the ref" \
    sib show-ref refs/conv/core-value

expect_fail \
    "show-ref rejects a short name" \
    sib show-ref core-pair

expect_fail \
    "symbolic-ref rejects a short target" \
    sib symbolic-ref HEAD core-pair

expect_fail \
    "ls-refs rejects a prefix outside refs/" \
    sib ls-refs conv/

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
