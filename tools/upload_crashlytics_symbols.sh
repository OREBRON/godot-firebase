#!/usr/bin/env bash
# Explicit opt-in upload: never called automatically by the reusable SDK build.
set -euo pipefail
usage() {
    echo 'Usage: upload_crashlytics_symbols.sh android|ios --binary PATH --symbols PATH --config GAME_JSON_OR_PLIST --upload-tool PATH [--readelf PATH] [--dwarfdump PATH] [--gradle-project PATH --variant Debug] [--mapping PATH]' >&2
    exit 2
}
[[ $# -gt 0 ]] || usage
platform="$1"; shift
binary=""; symbols=""; config=""; upload_tool=""; gradle_project=""; variant=""; mapping=""
readelf="llvm-readelf"; dwarfdump="dwarfdump"
while [[ $# -gt 0 ]]; do
    [[ $# -ge 2 ]] || usage
    case "$1" in
        --binary) binary="$2";;
        --symbols) symbols="$2";;
        --config) config="$2";;
        --upload-tool) upload_tool="$2";;
        --gradle-project) gradle_project="$2";;
        --variant) variant="$2";;
        --mapping) mapping="$2";;
        --readelf) readelf="$2";;
        --dwarfdump) dwarfdump="$2";;
        *) usage;;
    esac
    shift 2
done
[[ -n "$binary" && -n "$symbols" && -f "$config" && -x "$upload_tool" ]] || usage
verify_args=("$platform" --binary "$binary" --symbols "$symbols" --readelf "$readelf" --dwarfdump "$dwarfdump")
[[ -z "$mapping" ]] || verify_args+=(--mapping "$mapping")
python3 "$(dirname "$0")/verify_crashlytics_symbols.py" "${verify_args[@]}"
case "$platform" in
    ios)
        exec "$upload_tool" -gsp "$config" -p ios "$symbols"
        ;;
    android)
        [[ -d "$gradle_project" && "$variant" =~ ^[A-Z][A-Za-z0-9]*$ ]] || usage
        # The generated game build owns its Firebase app ID. Reject another game's JSON.
        cmp -s "$config" "$gradle_project/google-services.json" || { echo 'Game config differs from Gradle project google-services.json' >&2; exit 1; }
        symbol_dir="$(cd "$(dirname "$symbols")" && pwd)"
        tasks=("uploadCrashlyticsSymbolFile$variant")
        if [[ -n "$mapping" ]]; then
            first_letter="$(printf '%s' "${variant:0:1}" | tr '[:upper:]' '[:lower:]')"
            variant_directory="$first_letter${variant:1}"
            cmp -s "$mapping" "$gradle_project/build/outputs/mapping/$variant_directory/mapping.txt" || { echo 'R8 mapping differs from this Gradle export' >&2; exit 1; }
            tasks+=("uploadCrashlyticsMappingFile$variant")
        fi
        exec "$upload_tool" --no-daemon -p "$gradle_project" -PfirebaseCrashlyticsUploadEnabled=true "-PfirebaseCrashlyticsUnstrippedNativeLibsDir=$symbol_dir" "${tasks[@]}"
        ;;
    *) usage;;
esac
