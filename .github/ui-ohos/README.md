# Flutter UI OHOS compatibility

Run `node .github/patch-ui-ohos.cjs` from the app directory after `flutter pub get`.
The helper resolves only `material_ui` 1.5.0 and `cupertino_ui` 1.1.1 through
`.dart_tool/package_config.json`; it does not search the pub cache.

`manifest.json` contains fixed edits and SHA256 hashes of the original and patched
files. The original hashes were checked against the corresponding published
pub.dev archives. Unknown versions or changes to a patch target fail before any
file is written. Both already applied and interrupted, partly applied patches can
be rerun safely. Upgrading either package requires reviewing and replacing its
fixed manifest entries.

OHOS joins Android's existing switch arms, typography, touch density, scroll and
selection behavior, default page transition, ink effect and expansion semantics.
Other platform arms and nullable typography behavior retain their original code.
Package copyright headers and licenses are unchanged; the upstream license also
accompanies the source excerpts here in `LICENSE`.

The helper checks the SDK's actual `TargetPlatform` enum, using `FLUTTER_ROOT` when
set and the package-config Flutter entry otherwise. Conflicting SDKs are rejected.
With a standard Flutter SDK it reverses only these known patches, restoring exact
published bytes so no `TargetPlatform.ohos` references remain. Unknown edits are
never discarded automatically; review or restore the affected package before
retrying.

Run the helper regression checks with `node --test .github/patch-ui-ohos.test.cjs`.
