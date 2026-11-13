import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import 'install_hint.dart';

@JS('aiPwa')
extension type _Pwa._(JSObject _) implements JSObject {
  external JSString mode();
  external JSPromise<JSBoolean> install();
  external JSBoolean dismissed();
  external void dismiss();
  external void onChange(JSFunction f);
  external JSBoolean wakeLockSupported();
}

@JS('aiPwa')
external _Pwa get _pwa;

/// 웹: `web/pwa.js`(window.aiPwa)에게 묻는다. 스크립트가 없으면 안내하지 않는다.
Installer createInstaller() => _WebInstaller();

class _WebInstaller extends ChangeNotifier implements Installer {
  _WebInstaller() {
    if (_ok) _pwa.onChange((() => notifyListeners()).toJS);
  }

  final bool _ok = globalContext.has('aiPwa');

  @override
  InstallMode get mode {
    if (!_ok) return InstallMode.unsupported;
    return switch (_pwa.mode().toDart) {
      'installed' => InstallMode.installed,
      'prompt' => InstallMode.prompt,
      'ios' => InstallMode.ios,
      _ => InstallMode.unsupported,
    };
  }

  @override
  bool get dismissed => !_ok || _pwa.dismissed().toDart;

  @override
  void dismiss() {
    if (!_ok) return;
    _pwa.dismiss();
    notifyListeners();
  }

  @override
  Future<bool> install() async {
    if (!_ok) return false;
    final yes = (await _pwa.install().toDart).toDart;
    notifyListeners();
    return yes;
  }

  @override
  bool get wakeLockSupported => _ok && _pwa.wakeLockSupported().toDart;
}
