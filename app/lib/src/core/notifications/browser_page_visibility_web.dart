import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool isBrowserPageHiddenImpl() {
  try {
    return web.document.hidden;
  } catch (_) {
    return false;
  }
}

void Function() subscribeBrowserVisibilityImpl(
  void Function(bool hidden) onChanged,
) {
  void handle(web.Event _) {
    onChanged(isBrowserPageHiddenImpl());
  }

  final listener = handle.toJS;
  try {
    web.document.addEventListener('visibilitychange', listener);
    return () {
      web.document.removeEventListener('visibilitychange', listener);
    };
  } catch (_) {
    return () {};
  }
}
