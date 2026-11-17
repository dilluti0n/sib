#!/usr/bin/env bash
# Copyright 2026 Hee-Suk Kim <hskim@dilluti0n.com>
# SPDX-License-Identifier: GPL-3.0-only

test_description='Configuration and external commands'

. "$(dirname -- "$0")/test-lib.sh"

sib init >/dev/null 2>&1
printf 'first turn' | sib ask -c >/dev/null

sib config set sib.robustness.value 'value with spaces'

assert_eq "value with spaces" \
    "$(sib config get sib.robustness.value)" \
    "config preserves arguments containing spaces"

sib config set sib.model configured-core-model
sib config set sib.endpoint https://configured.example.invalid/v1

cat >"$RUNTIME/sib-core-probe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'model=%s\n' "$PLM_MODEL"
printf 'endpoint=%s\n' "$PLM_ENDPOINT"

for argument in "$@"; do
    printf 'arg=<%s>\n' "$argument"
done
EOF
chmod +x "$RUNTIME/sib-core-probe"

probe_output=$(
    env -u PLM_MODEL -u PLM_ENDPOINT \
        sib core-probe 'argument with spaces' --literal)

assert_contains "$probe_output" 'model=configured-core-model' \
    "dispatcher exports the configured model to external commands"

assert_contains "$probe_output" \
    'endpoint=https://configured.example.invalid/v1' \
    "dispatcher exports the configured endpoint to external commands"

assert_contains "$probe_output" 'arg=<argument with spaces>' \
    "dispatcher preserves an argument containing spaces"

assert_contains "$probe_output" 'arg=<--literal>' \
    "dispatcher preserves dash-prefixed external command arguments"

probe_output=$(
    PLM_MODEL=environment-core-model \
    PLM_ENDPOINT=https://environment.example.invalid/v1 \
        sib core-probe
)

assert_contains "$probe_output" 'model=environment-core-model' \
    "PLM_MODEL environment value overrides configuration"

assert_contains "$probe_output" \
    'endpoint=https://environment.example.invalid/v1' \
    "PLM_ENDPOINT environment value overrides configuration"

#
# A sib-<name> executable must not override a built-in cmd_<name>.
#

cat >"$RUNTIME/sib-rev-parse" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'external command incorrectly selected'
exit 99
EOF
chmod +x "$RUNTIME/sib-rev-parse"

assert_eq "$(sib git rev-parse HEAD)" "$(sib rev-parse HEAD)" \
    "built-in commands take priority over sib-* executables"

rm -f "$RUNTIME/sib-rev-parse"

test_done
