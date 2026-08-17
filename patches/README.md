# Patches

`build-final.sh` applies **every** `*.patch` in this directory, unconditionally,
regardless of which WebRTC version is being built:

```bash
for p in /patches/*.patch; do
    git apply $p || patch -p1 --forward < $p
done
```

There is no version gating. A patch that doesn't apply will fail the whole build
(`set -e`). To skip a patch, rename it so it no longer ends in `.patch`
(e.g. `.patch.disabled`) — `shopt -s nullglob` makes an empty directory a no-op.

The `patch -p1` fallback exists because `git apply` can refuse paths inside
nested gclient-managed repos (e.g. `third_party/jni_zero`), which
`android_jni_zero_aar_registration.patch` touches. `git apply` is atomic, so a
failed attempt changes nothing and there is no double-apply risk.

> **Note:** `build-final-gn.sh` does **not** mount or apply patches at all. If you
> need a patch, you must build via `build-final.sh`.

## Current patches

### `android_jni_zero_aar_registration.patch`

**Required for WebRTC 151 and newer. Do not use when building 150 or older.**

WebRTC 151 migrated the Android Java bindings to `jni_zero`'s `@NativeMethods`
proxy pattern. Two things then go missing from a `build_aar.py` AAR, and any call
into WebRTC dies at runtime with `NoClassDefFoundError`:

- the per-target accessor classes (`PeerConnectionFactoryJni`, …), which are only
  transitive deps and so are dropped by `dist_jar`'s `direct_deps_only = true`
- `org.jni_zero.GEN_JNI`, which `jni_zero` normally generates once per final app
  binary

This patch lists the 18 accessor targets explicitly and adds a
`generate_jni_registration()` scoped to the library itself (WebRTC's own Java
targets + its own `.so`, with `add_stubs_for_missing_jni`). It also widens
`third_party/jni_zero`'s `generate_jni` visibility to allow `//sdk/android:*`.

Adapted from shiguredo's
[`android_jni_zero_generated_java.patch`](https://github.com/shiguredo-webrtc-build/webrtc-build/blob/master/patches/android_jni_zero_generated_java.patch)
(theirs can't be used verbatim — it references their own `:simulcast_java` target).

> ⚠️ This patch also applies cleanly to **150**, where it is unnecessary. Move it
> aside before building 150 or older, or you are no longer building a vanilla 150.

Full background, the version boundary, and the failed approaches that preceded
this are documented in `mobile-webrtc/docs/android-jni-zero-migration.md`.
