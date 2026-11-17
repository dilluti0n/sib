#!/usr/bin/env bash
# Copyright 2026 Hee-Suk Kim <hskim@dilluti0n.com>
# SPDX-License-Identifier: GPL-3.0-only

test_description='sib edit'

. "$(dirname -- "$0")/test-lib.sh"

sib init >/dev/null 2>&1

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

edit_commits=($(sib rev-list HEAD))

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

edit_commits=($(sib rev-list HEAD))

assert_eq "3" "${#edit_commits[@]}" \
    "editing a middle turn preserves chain length"

assert_eq "edited root" "$(field content "${edit_commits[0]}")" \
    "middle edit preserves its parent"

assert_eq "edited middle" "$(field content "${edit_commits[1]}")" \
    "middle edit replaces target content"

assert_eq "edit three" "$(field content "${edit_commits[2]}")" \
    "middle edit replays its descendant"

#
# Editing through symbolic HEAD
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
# EDITOR with arguments
#

EDIT_CONTENT='edited with args' \
EDITOR="$RUNTIME/test-editor -w" \
    sib edit HEAD >/dev/null

assert_eq "edited with args" "$(field content HEAD)" \
    "EDITOR may carry arguments"

test_done
