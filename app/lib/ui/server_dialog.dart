/// 서버 주소 대화상자 (SPEC.md F-017 AC7). 모바일 앱에서만 열린다.
library;

import 'package:flutter/material.dart';

import '../chat/server_settings.dart';
import 'theme.dart';

Future<void> showServerDialog(BuildContext context, ServerSettings settings) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ServerDialog(settings: settings),
  );
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog({required this.settings});
  final ServerSettings settings;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final _text = TextEditingController(text: widget.settings.custom);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save(String value) {
    final error = widget.settings.update(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('서버 주소'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '채팅 서버(chatd) 주소예요. 같은 Wi-Fi의 컴퓨터에서 실행 중이면 그 컴퓨터의 주소와 3000번 포트를 넣어 주세요. '
              '비워 두면 기본 주소를 써요.',
              style: TextStyle(color: ChatColors.of(context).muted),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('server-address'),
              controller: _text,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onSubmitted: _save,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: '주소',
                hintText: widget.settings.fallback,
                helperText: '기본: ${widget.settings.fallback}',
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(key: const Key('save-server'), onPressed: () => _save(_text.text), child: const Text('저장')),
      ],
    );
  }
}
