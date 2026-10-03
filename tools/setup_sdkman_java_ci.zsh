#!/usr/bin/env zsh
# Select the repository's JDK for subsequent GitHub Actions steps.
set -e

export SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
if [[ ! -f "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
  print -u2 '::error::Install SDKMAN for the self-hosted runner user.'
  exit 1
fi
source "$SDKMAN_DIR/bin/sdkman-init.sh"
sdk env install

if [[ "${JAVA_HOME:-}" != "$SDKMAN_DIR/candidates/java/"* ]]; then
  print -u2 '::error::SDKMAN did not select a Java installation.'
  exit 1
fi
case "$("$JAVA_HOME/bin/javac" -version 2>&1)" in
  'javac 17.'*) ;;
  *) print -u2 '::error::The SDKMAN selection must be JDK 17.'; exit 1 ;;
esac

print -r -- "JAVA_HOME=$JAVA_HOME" >> "$GITHUB_ENV"
print -r -- "$JAVA_HOME/bin" >> "$GITHUB_PATH"
"$JAVA_HOME/bin/java" -version
