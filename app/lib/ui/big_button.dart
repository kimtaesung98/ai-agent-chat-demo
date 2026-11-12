/// 어르신도 누르기 쉬운 큰 버튼 (SPEC.md F-023). 높이 64, 글자 20. 로그인·첫 실행 화면이 같이 쓴다.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

enum BigButtonStyle { filled, outlined, plain }

class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.style = BigButtonStyle.filled,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// [icon] 대신 그릴 것 (예: Google 글자 표시).
  final Widget? leading;
  final BigButtonStyle style;

  static const height = 64.0;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    );
    final lead = leading ?? (icon == null ? null : Icon(icon, size: 26));
    final child = lead == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              lead,
              const SizedBox(width: 12),
              Flexible(child: text),
            ],
          );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    const size = Size.fromHeight(height);
    return switch (style) {
      BigButtonStyle.filled => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: size,
          shape: shape,
          backgroundColor: c.user,
          foregroundColor: c.userText,
        ),
        child: child,
      ),
      BigButtonStyle.outlined => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: size,
          shape: shape,
          backgroundColor: c.panel,
          foregroundColor: c.text,
          side: BorderSide(color: c.line, width: 1.5),
        ),
        child: child,
      ),
      BigButtonStyle.plain => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(minimumSize: size, shape: shape, foregroundColor: c.muted),
        child: child,
      ),
    };
  }
}
