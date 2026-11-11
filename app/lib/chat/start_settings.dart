/// 앱 시작 설정 (SPEC.md F-021). 켜 두면 앱을 열자마자 지금 페르소나와 음성 대화 화면으로 시작한다 — 어르신용.
/// `package:flutter/foundation.dart`까지만 import한다. 저장은 바깥(`storage/`)이 한다.
library;

import 'package:flutter/foundation.dart';

class StartSettings extends ChangeNotifier {
  StartSettings([this._voiceOnStart = false]);

  bool _voiceOnStart;

  /// 앱을 켜면 바로 음성 대화로 시작할지.
  bool get voiceOnStart => _voiceOnStart;

  set voiceOnStart(bool value) {
    if (value == _voiceOnStart) return;
    _voiceOnStart = value;
    notifyListeners();
  }
}
