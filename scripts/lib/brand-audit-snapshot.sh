#!/bin/bash

brand_audit_begin() {
    BRAND_AUDIT_FILES=("$@")
    BRAND_AUDIT_ORIGINAL=()
    BRAND_AUDIT_EXPECTED=()
    BRAND_AUDIT_PRESENT=()
    BRAND_AUDIT_INSTALLED=()
    BRAND_AUDIT_DIR="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/astrid-brand-audit.XXXXXXXX")" || return 1

    local i path
    for ((i = 0; i < ${#BRAND_AUDIT_FILES[@]}; i++)); do
        path="${BRAND_AUDIT_FILES[$i]}"
        BRAND_AUDIT_ORIGINAL[$i]="$BRAND_AUDIT_DIR/original-$i"
        BRAND_AUDIT_EXPECTED[$i]="$BRAND_AUDIT_DIR/expected-$i"
        BRAND_AUDIT_PRESENT[$i]=0
        BRAND_AUDIT_INSTALLED[$i]=0
        if [[ -L "$path" ]]; then
            echo "Brand audit refuses a symlink: $path" >&2
            return 1
        fi
        if [[ -e "$path" ]]; then
            if [[ ! -f "$path" ]]; then
                echo "Brand audit expected a regular file: $path" >&2
                return 1
            fi
            cp -p "$path" "${BRAND_AUDIT_ORIGINAL[$i]}" || return 1
            BRAND_AUDIT_PRESENT[$i]=1
        fi
    done
}

brand_audit_prepare() {
    local i
    for ((i = 0; i < ${#BRAND_AUDIT_FILES[@]}; i++)); do
        if [[ "${BRAND_AUDIT_PRESENT[$i]}" == 1 ]]; then
            cp -p "${BRAND_AUDIT_ORIGINAL[$i]}" "${BRAND_AUDIT_EXPECTED[$i]}" || return 1
        fi
    done
}

brand_audit_install() {
    local i path
    for ((i = 0; i < ${#BRAND_AUDIT_FILES[@]}; i++)); do
        path="${BRAND_AUDIT_FILES[$i]}"
        if [[ -L "$path" ]] || {
            [[ "${BRAND_AUDIT_PRESENT[$i]}" == 1 ]] && ! cmp -s "$path" "${BRAND_AUDIT_ORIGINAL[$i]}"
        } || {
            [[ "${BRAND_AUDIT_PRESENT[$i]}" == 0 ]] && [[ -e "$path" ]]
        }; then
            echo "$path changed before the brand audit; leaving it untouched." >&2
            return 1
        fi
    done
    for ((i = 0; i < ${#BRAND_AUDIT_FILES[@]}; i++)); do
        if [[ "${BRAND_AUDIT_PRESENT[$i]}" == 1 ]]; then
            BRAND_AUDIT_INSTALLED[$i]=1
            cp -p "${BRAND_AUDIT_EXPECTED[$i]}" "${BRAND_AUDIT_FILES[$i]}" || return 1
        fi
    done
}

brand_audit_restore() {
    local i path failed=0
    for ((i = 0; i < ${#BRAND_AUDIT_FILES[@]}; i++)); do
        [[ "${BRAND_AUDIT_INSTALLED[$i]}" == 1 ]] || continue
        path="${BRAND_AUDIT_FILES[$i]}"
        if [[ ! -L "$path" ]] && cmp -s "$path" "${BRAND_AUDIT_EXPECTED[$i]}"; then
            if ! cp -p "${BRAND_AUDIT_ORIGINAL[$i]}" "$path"; then
                echo "Could not restore $path; its original is in $BRAND_AUDIT_DIR." >&2
                failed=1
                continue
            fi
        elif [[ -L "$path" ]] || ! cmp -s "$path" "${BRAND_AUDIT_ORIGINAL[$i]}"; then
            echo "$path changed during the brand audit; leaving it untouched. Its original is in $BRAND_AUDIT_DIR." >&2
            failed=1
            continue
        fi
        BRAND_AUDIT_INSTALLED[$i]=0
    done
    return "$failed"
}

brand_audit_dispose() {
    local i
    for ((i = 0; i < ${#BRAND_AUDIT_FILES[@]}; i++)); do
        if [[ "${BRAND_AUDIT_INSTALLED[$i]:-0}" == 1 ]]; then
            echo "Keeping brand-audit snapshots in $BRAND_AUDIT_DIR for recovery." >&2
            return 1
        fi
    done
    for ((i = 0; i < ${#BRAND_AUDIT_FILES[@]}; i++)); do
        rm -f -- "${BRAND_AUDIT_ORIGINAL[$i]:-}" "${BRAND_AUDIT_EXPECTED[$i]:-}" || return 1
    done
    rmdir "$BRAND_AUDIT_DIR"
}
