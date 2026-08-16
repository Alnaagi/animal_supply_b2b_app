import 'browser_page_visibility_stub.dart'
    if (dart.library.js_interop) 'browser_page_visibility_web.dart' as platform;

bool isBrowserPageHidden() => platform.isBrowserPageHiddenImpl();

/// Fires when the document becomes hidden or visible. No-op on non-web.
void Function() subscribeBrowserVisibility(
  void Function(bool hidden) onChanged,
) {
  return platform.subscribeBrowserVisibilityImpl(onChanged);
}
