import 'package:ai_agent_chat/voice/sentences.dart';
import 'package:flutter_test/flutter_test.dart';

/// 글자를 [step]개씩 늘려 가며 push하고, 마지막에 flush한 결과 (스트리밍 흉내).
List<String> streamed(String text, {int step = 3}) {
  final s = SentenceSplitter();
  final out = <String>[];
  for (var i = step; i < text.length + step; i += step) {
    out.addAll(s.push(text.substring(0, i.clamp(0, text.length))));
  }
  return out..addAll(s.flush());
}

void main() {
  group('F-012 AC3 문장 분리', () {
    test('F-012 AC3 마침표·물음표·느낌표·줄임표·줄바꿈에서 자른다', () {
      expect(streamed('안녕하세요. 무엇을 도와드릴까요? 좋아요! 음… 그렇군요\n다음 줄'), [
        '안녕하세요.',
        '무엇을 도와드릴까요?',
        '좋아요!',
        '음…',
        '그렇군요',
        '다음 줄',
      ]);
    });

    test('F-012 AC3 문장이 완성되면 답이 끝나기 전에 바로 내보낸다', () {
      final s = SentenceSplitter();
      expect(s.push('첫 문장이에요'), isEmpty);
      expect(s.push('첫 문장이에요.'), isEmpty, reason: '다음 글자를 봐야 문장 끝인지 안다');
      expect(s.push('첫 문장이에요. 두'), ['첫 문장이에요.']);
      expect(s.push('첫 문장이에요. 두 번째'), isEmpty);
      expect(s.flush(), ['두 번째']);
    });

    test('F-012 AC3 소수점·약어·번호 목록에서는 자르지 않는다', () {
      expect(streamed('원주율은 3.14예요. e.g. 사과처럼요. Dr. Kim이 말했어요.'), ['원주율은 3.14예요.', 'e.g. 사과처럼요.', 'Dr. Kim이 말했어요.']);
      expect(streamed('순서는 이래요.\n1. 물을 끓여요\n2. 면을 넣어요'), ['순서는 이래요.', '물을 끓여요', '면을 넣어요']);
    });

    test('F-012 AC3 닫는 따옴표·괄호는 문장에 붙인다', () {
      expect(streamed('그가 "좋아요." 라고 했어요. (정말이에요!) 끝'), ['그가 "좋아요."', '라고 했어요.', '(정말이에요!)', '끝']);
    });

    test('F-012 AC3 코드 블록은 읽지 않는다 (닫히지 않아도)', () {
      expect(streamed('예시예요.\n```dart\nprint(1);\n```\n이렇게 써요.'), ['예시예요.', '이렇게 써요.']);
      expect(streamed('예시예요.\n```\nprint(1);'), ['예시예요.']);
    });

    test('F-012 AC3 문장부호 없이 길어지면 쉼표에서 끊는다', () {
      final long = '${'가나다라마바사 ' * 16}, 그리고 계속 이어지는 말';
      final s = SentenceSplitter();
      final first = s.push(long);
      expect(first, hasLength(1));
      expect(long.startsWith(first.single.substring(0, 10)), isTrue);
    });
  });

  group('F-012 AC3 읽을 문장 정리', () {
    test('F-012 AC3 마크다운 기호를 뺀다', () {
      expect(speakable('## 제목'), '제목');
      expect(speakable('**굵게** 그리고 *기울임* ~~취소~~'), '굵게 그리고 기울임 취소');
      expect(speakable('- 목록 항목'), '목록 항목');
      expect(speakable('> 인용문'), '인용문');
      expect(speakable('`code` 예시'), 'code 예시');
    });

    test('F-012 AC3 링크는 글자만, URL·이미지는 뺀다', () {
      expect(speakable('[공식 문서](https://example.com)를 보세요.'), '공식 문서를 보세요.');
      expect(speakable('주소는 https://example.com/a?b=1 이에요.'), '주소는 이에요.');
      expect(speakable('![그림](a.png) 설명'), '설명');
    });

    test('F-012 AC3 표·구분선은 읽을 만하게 바꾸거나 뺀다', () {
      expect(speakable('---'), '');
      expect(speakable('|---|:--:|'), '');
      expect(speakable('| 이름 | 나이 |'), '이름, 나이');
    });

    test('F-012 AC3 읽을 글자가 없으면 빈 문자열', () {
      for (final s in ['', '   ', '…', '**', '- ', '```']) {
        expect(speakable(s), '', reason: s);
      }
    });
  });
}
