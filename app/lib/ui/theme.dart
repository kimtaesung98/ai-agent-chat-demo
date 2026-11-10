import 'package:flutter/material.dart';

/// 화면 색 (라이트·다크). MVP HTML 디자인의 색과 같은 값.
@immutable
class ChatColors extends ThemeExtension<ChatColors> {
  const ChatColors({
    required this.bg,
    required this.panel,
    required this.text,
    required this.muted,
    required this.line,
    required this.user,
    required this.userText,
    required this.agent,
    required this.error,
    required this.errorBg,
  });

  final Color bg, panel, text, muted, line, user, userText, agent, error, errorBg;

  static const light = ChatColors(
    bg: Color(0xFFF6F5F2),
    panel: Color(0xFFFFFFFF),
    text: Color(0xFF1D1D1B),
    muted: Color(0xFF6B6A66),
    line: Color(0xFFE4E2DC),
    user: Color(0xFF1F4FD8),
    userText: Color(0xFFFFFFFF),
    agent: Color(0xFFEFEEE9),
    error: Color(0xFFB42318),
    errorBg: Color(0xFFFDECEA),
  );

  static const dark = ChatColors(
    bg: Color(0xFF151514),
    panel: Color(0xFF1E1E1C),
    text: Color(0xFFECEBE6),
    muted: Color(0xFF9C9A94),
    line: Color(0xFF2F2E2B),
    user: Color(0xFF4C7DFF),
    userText: Color(0xFFFFFFFF),
    agent: Color(0xFF2A2A27),
    error: Color(0xFFFF8A80),
    errorBg: Color(0xFF3A1D1B),
  );

  static ChatColors of(BuildContext context) => Theme.of(context).extension<ChatColors>()!;

  @override
  ChatColors copyWith() => this;

  @override
  ChatColors lerp(ChatColors? other, double t) => t < 0.5 || other == null ? this : other;
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? ChatColors.dark : ChatColors.light;
  return ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(seedColor: c.user, brightness: brightness, surface: c.panel),
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
  );
}
