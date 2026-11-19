#!/usr/bin/env bash
# Copyright 2026 Hee-Suk Kim <hskim@dilluti0n.com>
# SPDX-License-Identifier: GPL-3.0-only

test_description='sib ask, save and switch'

. "$(dirname -- "$0")/test-lib.sh"

sib init >/dev/null 2>&1

printf 'first turn' | sib ask -c >/dev/null

first=$(head_hash)

assert_eq "" "$(parent_of "$first")" \
    "first turn is a root commit"

assert_eq "user" "$(field role "$first")" \
    "first turn has user role"

assert_eq "first turn" "$(field content "$first")" \
    "first turn preserves content"

#
# Save
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
# Symbolic switch and ask
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
# Explicit detach
#

sib switch HEAD

assert_direct_head \
    "switch HEAD detaches at the current position"

assert_eq "$work_after" "$(head_hash)" \
    "switch HEAD preserves the current chain position"

assert_eq "$work_after" "$(sib rev-parse work)" \
    "detaching does not move the followed ref"

#
# Start a new root
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
# Full successful ask
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
# Direct switch from a saved shorthand
#

sib switch work

assert_direct_head \
    "ordinary switch always produces direct HEAD"

assert_eq "$(sib rev-parse work)" "$(head_hash)" \
    "switch resolves refs/conv shorthand"

#
# Exit status
#

status=0
printf 'call a tool' | MOCK_FUNCTION_CALL=1 sib ask -n >/dev/null 2>&1 || status=$?
assert_eq "10" "$status" "sib ask exits 10 when the function_call has no tool"

assert_eq "function_call" "$(sib show HEAD:type)" \
    "sib ask still commits the function_call before exiting 10"

status=0
printf 'plain' | sib ask >/dev/null 2>&1 || status=$?
assert_eq "0" "$status" "sib ask exits 0 when the response ends with a message"

test_done
