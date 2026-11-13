/// 음성 화면의 소리 파형 (F-018 AC11). 막대들이 물결처럼 흐르고, 마이크 소리가 클수록 높아진다.
/// 듣는 중에는 마이크 소리 크기를, 말하는 중에는 정해진 크기로 움직인다. 움직임 줄이기 설정이면 멈춘 막대만 그린다.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class VoiceWave extends StatefulWidget {
  const VoiceWave({
    super.key,
    required this.level,
    required this.color,
    required this.moving,
    this.speaking = false,
    this.bars = 28,
    this.height = 56,
  });

  /// 마이크 소리 크기 0~1.
  final ValueListenable<double> level;
  final Color color;

  /// 듣는 중·말하는 중이면 true — 물결이 흐른다.
  final bool moving;

  /// 말하는 중이면 마이크 소리 대신 정해진 크기로 움직인다.
  final bool speaking;
  final int bars;
  final double height;

  @override
  State<VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<VoiceWave> with SingleTickerProviderStateMixin {
  late final _ticker = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  double _amp = 0; // 부드럽게 따라가는 높이

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _sync(bool run) {
    if (run && !_ticker.isAnimating) {
      _ticker.repeat();
    } else if (!run && _ticker.isAnimating) {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    _sync(widget.moving && !still);
    return ExcludeSemantics(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: Listenable.merge([_ticker, widget.level]),
          builder: (context, _) {
            if (!widget.moving) {
              _amp = 0; // 멈추면 바로 낮은 막대로 — 물결이 멈춰 더는 다시 그리지 않는다
            } else {
              final target = widget.speaking ? 0.55 : widget.level.value.clamp(0.0, 1.0);
              // 올라갈 땐 빨리, 내려갈 땐 천천히 — 말소리에 맞춰 튀고 부드럽게 가라앉는다
              _amp += (target - _amp) * (target > _amp ? 0.5 : 0.12);
            }
            return CustomPaint(
              key: const Key('voice-wave-paint'),
              painter: VoiceWavePainter(
                phase: still ? 0 : _ticker.value * 2 * math.pi,
                amp: _amp,
                idle: widget.moving ? 0.12 : 0.05,
                bars: widget.bars,
                color: widget.color,
              ),
            );
          },
        ),
      ),
    );
  }
}

class VoiceWavePainter extends CustomPainter {
  VoiceWavePainter({
    required this.phase,
    required this.amp,
    required this.idle,
    required this.bars,
    required this.color,
  });

  final double phase, amp, idle;
  final int bars;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width / bars;
    final w = math.max(2.0, gap * 0.45);
    final paint = Paint()
      ..color = color
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    final mid = size.height / 2;
    for (var i = 0; i < bars; i++) {
      final x = gap * (i + 0.5);
      final t = i / (bars - 1);
      // 가운데가 높고 양 끝이 낮은 모양 × 두 물결을 겹친 흐름
      final envelope = math.sin(math.pi * t);
      final wave = 0.5 + 0.3 * math.sin(phase + t * 6 * math.pi) + 0.2 * math.sin(phase * 2 - t * 10 * math.pi);
      final h = (idle + amp * envelope * wave) * (size.height - w);
      final half = math.max(w / 2, h / 2);
      canvas.drawLine(Offset(x, mid - half + w / 2), Offset(x, mid + half - w / 2), paint);
    }
  }

  @override
  bool shouldRepaint(VoiceWavePainter old) =>
      old.phase != phase || old.amp != amp || old.idle != idle || old.color != color || old.bars != bars;
}
