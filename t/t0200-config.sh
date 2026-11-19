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

# Without sib.vendor, sib.{endpoint,model} are used
sib config unset sib.vendor
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
# sib.vendor names a vendor.<name> section over sib.{endpoint,model}
#

sib config set vendor.cyberdyne.endpoint https://cyberdyne.example.invalid/v1
sib config set vendor.cyberdyne.model skynet
sib config set sib.vendor cyberdyne

probe_output=$(sib core-probe)

assert_contains "$probe_output" 'model=skynet' \
    "sib.vendor takes the model of its vendor section"

assert_contains "$probe_output" \
    'endpoint=https://cyberdyne.example.invalid/v1' \
    "sib.vendor takes the endpoint of its vendor section"

assert_contains "$(PLM_MODEL=environment-core-model sib core-probe)" \
    'model=environment-core-model' \
    "PLM_MODEL environment value overrides the vendor"

assert_contains "$(sib status)" \
    $'Vendor:   cyberdyne\nEndpoint: https://cyberdyne.example.invalid/v1\nModel:    skynet' \
    "status shows the vendor, its endpoint and model"

sib config set vendor.cyberdyne.headerCmd 'pass show cyberdyne'

cat >"$RUNTIME/sib-header-probe" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PLM_HEADER_CMD"
EOF
chmod +x "$RUNTIME/sib-header-probe"

assert_eq 'pass show cyberdyne' "$(sib header-probe)" \
    "sib.vendor exports its headerCmd as PLM_HEADER_CMD"

sib config unset vendor.cyberdyne.model

assert_contains "$(sib core-probe)" 'model=configured-core-model' \
    "a vendor without a model falls back to sib.model"

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
