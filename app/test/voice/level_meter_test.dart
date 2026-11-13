import 'package:ai_agent_chat/voice/level_meter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('F-018 AC11 iOS dB 범위(-50~0)에서 조용함은 0 가까이, 말소리는 1 가까이', () {
    final m = LevelMeter();
    expect(m.add(-50), 0);
    expect(m.add(-50), lessThan(0.05));
    expect(m.add(-10), closeTo(1, 0.01));
    expect(m.add(-48), lessThan(0.1));
  });

  test('F-018 AC11 Android dB 범위(-2~10)에서도 같은 모양', () {
    final m = LevelMeter();
    m.add(-2);
    expect(m.add(10), closeTo(1, 0.01));
    expect(m.add(-2), lessThan(0.05));
  });

  test('F-018 AC11 조용한 방의 작은 잡음은 크게 보이지 않고, 이상한 값은 0', () {
    final m = LevelMeter();
    m.add(-50);
    expect(m.add(-47), lessThan(0.35));
    expect(m.add(double.nan), 0);
    expect(m.add(double.negativeInfinity), 0);
  });
}
