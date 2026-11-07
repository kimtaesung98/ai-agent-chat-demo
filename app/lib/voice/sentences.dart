/// 스트리밍 중인 답을 읽을 문장으로 나눈다 (SPEC.md F-012 AC2·AC3).
/// 순수 Dart — 위젯·엔진을 모른다.
library;

/// 답 글자가 늘어날 때마다 [push]로 지금까지의 전체 답을 넣으면, 새로 완성된 문장을 돌려준다.
/// 답이 끝나면 [flush]로 남은 부분을 받는다. 돌려주는 문장은 이미 [speakable]로 정리돼 있다.
class SentenceSplitter {
  /// 문장부호가 없어도 이 길이를 넘으면 쉼표·공백에서 끊는다 (첫 문장을 빨리 읽기 위해).
  static const softLimit = 120;

  String _text = '';
  int _pos = 0; // 아직 문장으로 내보내지 않은 부분의 시작
  bool _inCode = false; // ``` 코드 블록 안 (읽지 않음)

  /// [text]는 지금까지 받은 전체 답이다 (앞부분은 바뀌지 않는다고 가정).
  List<String> push(String text) {
    _text = text;
    return _scan(final_: false);
  }

  /// 답이 끝났을 때 남은 부분을 문장으로 내보낸다.
  List<String> flush() => _scan(final_: true);

  void reset() {
    _text = '';
    _pos = 0;
    _inCode = false;
  }

  List<String> _scan({required bool final_}) {
    final out = <String>[];
    void emit(int end) {
      final s = speakable(_text.substring(_pos, end));
      if (s.isNotEmpty) out.add(s);
      _pos = end;
    }

    var i = _pos;
    while (i < _text.length) {
      if (_inCode) {
        final close = _text.indexOf('```', i);
        if (close < 0) {
          if (final_) _pos = _text.length; // 닫히지 않은 코드 블록은 버린다
          return out;
        }
        _inCode = false;
        i = _pos = close + 3;
        continue;
      }
      if (_text.startsWith('```', i)) {
        emit(i);
        _inCode = true;
        i = _pos = i + 3;
        continue;
      }
      final c = _text[i];
      if (c == '\n') {
        emit(i + 1);
        i = _pos;
        continue;
      }
      if (_terminators.contains(c)) {
        var end = i + 1;
        while (end < _text.length && (_terminators.contains(_text[end]) || _closers.contains(_text[end]))) {
          end++;
        }
        if (end == _text.length && !final_) return out; // 다음 글자를 봐야 안다 (예: "3." 뒤에 "14")
        if (end == _text.length || _isSpace(_text[end])) {
          if (!(c == '.' && _isNonBoundaryDot(i))) {
            emit(end);
            i = _pos;
            continue;
          }
        }
        i = end;
        continue;
      }
      i++;
    }

    if (final_) {
      emit(_text.length);
    } else if (_text.length - _pos > softLimit) {
      final chunk = _text.substring(_pos);
      final cut = [
        chunk.lastIndexOf(', '),
        chunk.lastIndexOf('，'),
        chunk.lastIndexOf(' '),
      ].reduce((a, b) => a > b ? a : b);
      if (cut > softLimit ~/ 3) emit(_pos + cut + 1);
    }
    return out;
  }

  /// 마침표지만 문장 끝이 아닌 경우: 줄 맨 앞 번호 목록("1. ")과 약어("e.g. ", "Dr. ").
  bool _isNonBoundaryDot(int dot) {
    var start = dot;
    while (start > 0 && !_isSpace(_text[start - 1])) {
      start--;
    }
    final word = _text.substring(start, dot);
    if (_abbreviations.contains(word.toLowerCase())) return true;
    if (RegExp(r'^\d{1,3}$').hasMatch(word)) {
      final lineStart = _text.lastIndexOf('\n', dot) + 1;
      return _text.substring(lineStart, start).trim().isEmpty;
    }
    return false;
  }
}

const _terminators = {'.', '?', '!', '…', '。', '？', '！'};
const _closers = {'"', "'", ')', ']', '”', '’', '」', '』'};
const _abbreviations = {'e.g', 'i.e', 'mr', 'mrs', 'ms', 'dr', 'st', 'vs', 'etc'};

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

final _image = RegExp(r'!\[[^\]]*\]\([^)]*\)');
final _link = RegExp(r'\[([^\]]+)\]\([^)]*\)');
final _url = RegExp(r'https?://\S+|www\.\S+');
final _inlineCode = RegExp(r'`([^`]*)`');
final _emphasis = RegExp(r'\*{1,3}|_{2,3}|~~');
final _lineMarker = RegExp(r'^\s*(?:#{1,6}\s+|>\s*|[-*+]\s+|\d{1,3}[.)]\s+)');
final _rule = RegExp(r'^\s*(?:[-*_]\s*){3,}$');
final _tableSep = RegExp(r'^\s*\|?[\s:|-]+\|?\s*$');
final _spaces = RegExp(r'\s+');
final _hasWord = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// 소리 내어 읽을 문장으로 정리한다: 마크다운 기호·URL·코드 표시를 빼고 공백을 줄인다.
/// 읽을 글자가 없으면 빈 문자열.
String speakable(String text) {
  final lines = <String>[];
  for (var line in text.split('\n')) {
    if (_rule.hasMatch(line) || (line.contains('|') && _tableSep.hasMatch(line))) continue;
    line = line
        .replaceAll(_image, '')
        .replaceAllMapped(_link, (m) => m[1]!)
        .replaceAll(_url, '')
        .replaceAllMapped(_inlineCode, (m) => m[1]!)
        .replaceFirst(_lineMarker, '')
        .replaceAll(_emphasis, '');
    if (line.contains('|')) {
      line = line.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).join(', ');
    }
    lines.add(line);
  }
  final s = lines.join(' ').replaceAll(_spaces, ' ').trim();
  return _hasWord.hasMatch(s) ? s : '';
}
