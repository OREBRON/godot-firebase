#!/usr/bin/env bash
# Select the repository's JDK for subsequent GitHub Actions steps.
# Runs under bash on Linux runners; setup_sdkman_java_ci.zsh sources it on macOS.
set -e

export SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
if [[ ! -f "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
  echo '::error::Install SDKMAN for the self-hosted runner user.' >&2
  exit 1
fi
source "$SDKMAN_DIR/bin/sdkman-init.sh"
# Installs a missing .sdkmanrc version without changing the user's default.
sdk env install

if [[ "${JAVA_HOME:-}" != "$SDKMAN_DIR/candidates/java/"* ]]; then
  echo '::error::SDKMAN did not select a Java installation.' >&2
  exit 1
fi
case "$("$JAVA_HOME/bin/javac" -version 2>&1)" in
  'javac 17.'*) ;;
  *) echo '::error::The SDKMAN selection must be JDK 17.' >&2; exit 1 ;;
esac

printf '%s\n' "JAVA_HOME=$JAVA_HOME" >> "$GITHUB_ENV"
printf '%s\n' "$JAVA_HOME/bin" >> "$GITHUB_PATH"
"$JAVA_HOME/bin/java" -version
