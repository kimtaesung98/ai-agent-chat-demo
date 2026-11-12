/// 글자 크기 설정 (SPEC.md F-023 S-006). 어르신이 크게 볼 수 있게 앱 전체 글자를 키운다.
/// `package:flutter/foundation.dart`까지만 import한다. 저장은 바깥(`storage/`)이 한다.
library;

import 'package:flutter/foundation.dart';

/// 고를 수 있는 글자 크기. [scale]은 기기 글자 크기에 곱한다.
enum TextSize {
  normal('보통', 1.0),
  large('크게', 1.2),
  xlarge('아주 크게', 1.4);

  const TextSize(this.label, this.scale);
  final String label;
  final double scale;

  static TextSize parse(String? name) => values.where((v) => v.name == name).firstOrNull ?? normal;
}

class DisplaySettings extends ChangeNotifier {
  DisplaySettings([this._textSize = TextSize.normal]);

  TextSize _textSize;
  TextSize get textSize => _textSize;

  set textSize(TextSize value) {
    if (value == _textSize) return;
    _textSize = value;
    notifyListeners();
  }
}
