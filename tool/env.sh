# Source this before flutter commands: `. tool/env.sh`
# Keeps this project's Gradle cache on the project drive instead of ~/.gradle.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GRADLE_USER_HOME="$ROOT/.gradle-home"
export JAVA_HOME="${JAVA_HOME:-$HOME/jdk}"
export PATH="$HOME/flutter/bin:$PATH"
