#!/bin/bash
set -euo pipefail

IMAGE=threema/webrtc-build-tools:latest
BUILD_ARGS="${WEBRTC_BUILD_ARGS:-symbol_level=1 debuggable_apks=false enable_libaom=false rtc_enable_protobuf=false rtc_include_dav1d_in_internal_decoder_factory=false use_siso=false android_static_analysis=\\\"off\\\" is_component_build=false rtc_include_tests=false}"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 138.0.7204.179"
    exit 1
fi
WEBRTC_VERSION=$1
echo "WebRTC version: $WEBRTC_VERSION"

# Pull recent releases, find specified version
RELEASES_RESPONSE=$(curl -s "https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Android&num=50")

# Use python to parse JSON properly
COMMIT_HASH=$(echo "$RELEASES_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for release in data:
    if release.get('version') == '$WEBRTC_VERSION':
        hashes = release.get('hashes', {})
        commit = hashes.get('webrtc')
        if commit:
            print(commit)
        break
")

if [[ -n "$COMMIT_HASH" ]]; then
    echo "Commit hash for $WEBRTC_VERSION: $COMMIT_HASH"
else
    echo "Unable to fetch metadata for version: $WEBRTC_VERSION"
    echo "Available versions:"
    echo "$RELEASES_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for release in data[:10]:
    print(f\"  {release.get('version', 'N/A')} (milestone {release.get('milestone', 'N/A')})\")" 2>/dev/null || echo "  Failed to parse available versions"
    exit 1
fi

rm -rf ./out && mkdir -p ./out
docker run --platform linux/amd64 --rm -v "$(pwd)/out:/out" \
    $IMAGE /bin/bash -c "
    set -euo pipefail

    export OUT='/out'

    echo '==> Fetching sources'
    fetch --nohooks webrtc_android

    echo '==> Change current working directory to src/ of the workspace'
    cd src

    echo '==> Checking out release $WEBRTC_VERSION'
    git checkout $COMMIT_HASH

    echo '==> Run gclient sync'
    gclient sync

    echo '==> Log revision and build args'
    git log --pretty=fuller HEAD...HEAD^ > \$OUT/revision.txt
    echo \"BUILD_ARGS: $BUILD_ARGS\" >> \$OUT/build_args.txt

    echo '==> Build AAR via build_aar.py (it drives GN gen + ninja itself for every architecture)'
    source build/android/envsetup.sh

    python3 tools_webrtc/android/build_aar.py --build-dir out --output \$OUT/libwebrtc.aar --extra-gn-args $BUILD_ARGS

    echo 'Done!'
"
