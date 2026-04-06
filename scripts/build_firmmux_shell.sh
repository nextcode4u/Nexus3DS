#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/build-logs"
STAMP="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$LOG_DIR/$STAMP"
LATEST_LINK="$LOG_DIR/latest"
SUMMARY_FILE="$RUN_DIR/summary.txt"

export PATH="$ROOT_DIR/bin:$PATH"

mkdir -p "$RUN_DIR"
rm -f "$LATEST_LINK"
ln -s "$RUN_DIR" "$LATEST_LINK"

log() {
    printf '[build] %s\n' "$*"
}

run_build() {
    local name="$1"
    local mode="$2"
    local dir="$3"
    local target="$4"
    local log_file="$RUN_DIR/${name}_${mode}.log"
    local status_file="$RUN_DIR/${name}_${mode}.status"
    local flag_value=0

    if [[ "$mode" == "experimental" ]]; then
        flag_value=1
    fi

    log "building $name ($mode)"
    {
        printf 'component=%s\n' "$name"
        printf 'mode=%s\n' "$mode"
        printf 'cwd=%s\n' "$dir"
        printf 'flag=%s\n' "$flag_value"
        printf 'started=%s\n' "$(date -Iseconds)"
    } > "$status_file"

    set +e
    (
        cd "$dir"
        make clean
        make all EXPERIMENTAL_FIRMMUX_SHELL="$flag_value"
    ) >"$log_file" 2>&1
    local rc=$?
    set -e

    if [[ $rc -eq 0 ]]; then
        printf 'result=ok\n' >> "$status_file"
        printf '%s %s: ok\n' "$name" "$mode" >> "$SUMMARY_FILE"
        return 0
    fi

    if grep -q "makerom: command not found" "$log_file" && [[ -f "$target" ]]; then
        printf 'result=compile-ok-package-skipped\n' >> "$status_file"
        printf 'note=makerom missing; %s exists\n' "$target" >> "$status_file"
        printf '%s %s: compile-ok-package-skipped\n' "$name" "$mode" >> "$SUMMARY_FILE"
        return 0
    fi

    printf 'result=failed\n' >> "$status_file"
    printf 'exit_code=%s\n' "$rc" >> "$status_file"
    printf '%s %s: failed\n' "$name" "$mode" >> "$SUMMARY_FILE"
    log "build failed for $name ($mode); see $log_file"
    return 1
}

run_top_level_build() {
    local mode="$1"
    local log_file="$RUN_DIR/boot_firm_${mode}.log"
    local status_file="$RUN_DIR/boot_firm_${mode}.status"
    local flag_value=0

    if [[ "$mode" == "experimental" ]]; then
        flag_value=1
    fi

    log "building boot.firm ($mode)"
    {
        printf 'component=boot.firm\n'
        printf 'mode=%s\n' "$mode"
        printf 'cwd=%s\n' "$ROOT_DIR"
        printf 'flag=%s\n' "$flag_value"
        printf 'started=%s\n' "$(date -Iseconds)"
    } > "$status_file"

    set +e
    (
        cd "$ROOT_DIR"
        make clean
        make boot.firm EXPERIMENTAL_FIRMMUX_SHELL="$flag_value"
    ) >"$log_file" 2>&1
    local rc=$?
    set -e

    if [[ $rc -eq 0 && -f "$ROOT_DIR/boot.firm" ]]; then
        printf 'result=ok\n' >> "$status_file"
        printf 'artifact=%s\n' "$ROOT_DIR/boot.firm" >> "$status_file"
        printf 'boot.firm %s: ok\n' "$mode" >> "$SUMMARY_FILE"
        return 0
    fi

    printf 'result=failed\n' >> "$status_file"
    printf 'exit_code=%s\n' "$rc" >> "$status_file"
    printf 'boot.firm %s: failed\n' "$mode" >> "$SUMMARY_FILE"
    log "boot.firm build failed for $mode; see $log_file"
    return 1
}

main() {
    : > "$SUMMARY_FILE"

    local failed=0

    run_build "k11_extension" "stock" \
        "$ROOT_DIR/k11_extension" \
        "$ROOT_DIR/k11_extension/k11_extension.elf" || failed=1

    run_build "k11_extension" "experimental" \
        "$ROOT_DIR/k11_extension" \
        "$ROOT_DIR/k11_extension/k11_extension.elf" || failed=1

    run_build "pm" "stock" \
        "$ROOT_DIR/sysmodules/pm" \
        "$ROOT_DIR/sysmodules/pm/pm.elf" || failed=1

    run_build "pm" "experimental" \
        "$ROOT_DIR/sysmodules/pm" \
        "$ROOT_DIR/sysmodules/pm/pm.elf" || failed=1

    run_top_level_build "experimental" || failed=1

    log "summary written to $SUMMARY_FILE"
    cat "$SUMMARY_FILE"

    if [[ $failed -ne 0 ]]; then
        exit 1
    fi
}

main "$@"
