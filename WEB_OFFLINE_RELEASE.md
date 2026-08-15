# Offline-ready Flutter web release

Use the release wrapper instead of calling `flutter build web` directly. It
runs the Flutter build, inventories the exact generated output, writes a
content-hashed shell manifest, and connects that manifest to the custom
service worker:

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app/app

FLUTTER_BIN=/home/alnaagi/development/flutter/bin/flutter \
  node tool/build_web_release.mjs \
  --release \
  --no-web-resources-cdn \
  --dart-define=APP_ENV=demo
```

For a production build, pass the same public `--dart-define` or
`--dart-define-from-file` arguments used by the normal Flutter build. Never put
server secrets in those arguments.

After the first successful online launch, the service worker stages the exact
versioned Flutter shell, including `main.dart.js`, local engine WASM/JavaScript,
fonts, icons, and packaged assets. The previous complete shell remains
available until the new shell is fully cached. Same-origin requests remain
network-first, with the complete shell used only when the network is
unavailable.

Static verification without rebuilding:

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app/app
node --check web/app_service_worker.js
node --check tool/build_web_release.mjs
node tool/build_web_release.mjs --prepare-only
```

The post-build step is required. A raw `flutter build web` still produces a
usable online build, but it does not create the generated shell manifest needed
for a guaranteed complete offline reopen.

The current August 13, 2026 demo release is `1.0.4+5` with shell version
`2a1f208c897592533cfeb8affdf5ed6ff72bcdb211181feaad6fd8066b91089a`
in `web_shell_manifest.2a1f208c89759253.json`. The generated manifest contains
76 resources, including the early PWA install bridge, and the final deployed
`main.dart.js`, `flutter_bootstrap.js`, and `pwa_install.js` matched their exact
local release files.
