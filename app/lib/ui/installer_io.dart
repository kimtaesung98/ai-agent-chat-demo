import 'package:flutter/foundation.dart';

import 'install_hint.dart';

/// 웹이 아닌 곳(테스트 VM): 설치 안내가 필요 없다.
Installer createInstaller() => _NativeInstaller();

class _NativeInstaller extends ChangeNotifier implements Installer {
  @override
  InstallMode get mode => InstallMode.installed;
  @override
  bool get dismissed => true;
  @override
  void dismiss() {}
  @override
  Future<bool> install() async => false;
  @override
  bool get wakeLockSupported => true; // 웹이 아닌 곳(테스트 VM)은 안내하지 않는다
}
