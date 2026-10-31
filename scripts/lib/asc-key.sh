#!/bin/bash

# Callers set ROOT to the physical repository root before using these helpers.
asc_initialize() {
  local env_file="${ASC_ENV_FILE:-$ROOT/.env.local}"
  [ -f "$env_file" ] && [ -r "$env_file" ] || {
    echo "Set ASC_ENV_FILE to a readable credentials file outside the repository." >&2
    return 1
  }
  ASC_ENV_FILE=$(perl -MCwd=realpath -e 'print realpath($ARGV[0]) // die "Cannot resolve credentials path\n"' "$env_file") || return 1
  case "$ASC_ENV_FILE" in
    "$ROOT"/*) echo "App Store Connect credentials must be stored outside the repository; set ASC_ENV_FILE accordingly." >&2; return 1 ;;
  esac
  export ASC_ENV_FILE
  TEMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd -P) || {
    echo "Cannot resolve the temporary directory." >&2
    return 1
  }
  case "$TEMP_ROOT/" in
    "$ROOT/"*) echo "The temporary directory must not be inside the repository." >&2; return 1 ;;
  esac
}

asc_write_key() {
  if [ -z "$KEY_DIR" ]; then
    KEY_DIR=$(umask 077; mktemp -d "$TEMP_ROOT/astrid-asc.XXXXXXXX") || {
      echo "Could not create a private temporary directory for the App Store Connect key." >&2
      return 1
    }
    KEY_FILE="$KEY_DIR/AuthKey.p8"
  fi
  KEY_ID=$(grep -E '^APPLE_ASC_KEY_ID=' "$ASC_ENV_FILE" | cut -d= -f2- | tr -d "\"'") \
    || { echo "APPLE_ASC_KEY_ID is missing from the credentials file." >&2; return 1; }
  ISSUER=$(grep -E '^APPLE_ASC_ISSUER_ID=' "$ASC_ENV_FILE" | cut -d= -f2- | tr -d "\"'") \
    || { echo "APPLE_ASC_ISSUER_ID is missing from the credentials file." >&2; return 1; }
  [ -n "$KEY_ID" ] && [ -n "$ISSUER" ] \
    || { echo "App Store Connect key and issuer IDs must not be empty." >&2; return 1; }
  (umask 077; : > "$KEY_FILE") || { echo "Could not create the temporary App Store Connect key." >&2; return 1; }
  grep -qE '^APPLE_ASC_PRIVATE_KEY=' "$ASC_ENV_FILE" \
    || { echo "APPLE_ASC_PRIVATE_KEY is missing from the credentials file." >&2; return 1; }
  if ! grep -E '^APPLE_ASC_PRIVATE_KEY=' "$ASC_ENV_FILE" | sed -E "s/^APPLE_ASC_PRIVATE_KEY=//; s/^['\"]//; s/['\"]$//" \
    | perl -pe 's/\\n/\n/g' > "$KEY_FILE"; then
    echo "Could not read or decode APPLE_ASC_PRIVATE_KEY from the credentials file." >&2
    return 1
  fi
  grep -q '[^[:space:]]' "$KEY_FILE" \
    || { echo "APPLE_ASC_PRIVATE_KEY must not be empty." >&2; return 1; }
}

asc_cleanup_key() {
  local status=0
  if [ -n "$KEY_FILE" ]; then
    rm -f -- "$KEY_FILE" || { echo "Could not remove temporary App Store Connect key: $KEY_FILE" >&2; status=1; }
  fi
  if [ -n "$KEY_DIR" ]; then
    rmdir "$KEY_DIR" || { echo "Could not remove temporary App Store Connect directory: $KEY_DIR" >&2; status=1; }
  fi
  return "$status"
}
