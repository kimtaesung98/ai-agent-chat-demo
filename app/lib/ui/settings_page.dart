/// S-006 설정 (SPEC.md F-023). 서랍에 흩어져 있던 설정을 한 화면에 모은다 — 내 계정·내 프로필·시작 방식·
/// 지난 대화 기억·글자 크기·서버 주소(앱만)·앱 정보. 로그아웃은 한 번 더 묻는다 (잘못 누르기 막기).
library;

import 'package:flutter/material.dart';

import '../chat/auth_controller.dart';
import '../chat/chat_controller.dart';
import '../chat/display_settings.dart';
import '../chat/server_settings.dart';
import '../chat/start_settings.dart';
import '../voice/voice_controller.dart';
import 'login_page.dart';
import 'memory_page.dart';
import 'persona_widgets.dart';
import 'server_dialog.dart';
import 'theme.dart';

Future<void> openSettingsPage(
  BuildContext context, {
  required ChatController chat,
  VoiceSession? voice,
  AuthController? auth,
  StartSettings? start,
  DisplaySettings? display,
  ServerSettings? server,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          SettingsPage(chat: chat, voice: voice, auth: auth, start: start, display: display, server: server),
    ),
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.chat, this.voice, this.auth, this.start, this.display, this.server});

  final ChatController chat;
  final VoiceSession? voice;

  /// 없으면(로그인 없이 띄운 앱) 내 계정 칸을 그리지 않는다.
  final AuthController? auth;

  /// 음성이 없으면 시작 방식 칸을 그리지 않는다.
  final StartSettings? start;
  final DisplaySettings? display;

  /// 모바일 앱만. 웹은 같은 출처라 null.
  final ServerSettings? server;

  Future<void> _signOut(BuildContext context, AuthController auth) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃할까요?'),
        content: const Text('페르소나와 지난 대화 기억은 이 기기에 그대로 남아요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('아니요')),
          FilledButton(
            key: const Key('confirm-logout'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    voice?.stop();
    chat.reset(); // 지금 대화를 정리해 기억으로 남기고 비운다 (F-019)
    Navigator.of(context).popUntil((r) => r.isFirst);
    auth.signOut(); // 앱이 로그인 화면으로 바꾼다
  }

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final personas = chat.personas;
    final memory = chat.memory;
    final voiceStart = voice == null ? null : start;
    return Scaffold(
      key: const Key('settings-page'),
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: c.panel,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: c.line)),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([chat, ?auth, ?start, ?display, ?server, ?personas]),
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (auth case final auth?)
                  if (auth.account case final account?)
                    _Section(
                      title: '내 계정',
                      children: [
                        ListTile(
                          key: const Key('settings-account'),
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor: c.user,
                            foregroundColor: c.userText,
                            child: Text(account.initial, style: const TextStyle(fontSize: 20)),
                          ),
                          title: Text(account.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          subtitle: Text(switch (account.kind) {
                            AccountKind.google => [
                              'Google 계정${account.mock ? ' (모의)' : ''}',
                              if (account.email.isNotEmpty) account.email,
                            ].join(' · '),
                            AccountKind.guest => '이 기기에서만 쓰는 이름',
                          }),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          child: OutlinedButton.icon(
                            key: const Key('settings-logout'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                            onPressed: () => _signOut(context, auth),
                            icon: const Icon(Icons.logout),
                            label: const Text('로그아웃', style: TextStyle(fontSize: 17)),
                          ),
                        ),
                      ],
                    ),
                _Section(
                  title: '대화',
                  children: [
                    if (personas != null)
                      ListTile(
                        key: const Key('settings-profile'),
                        leading: const Icon(Icons.person_outline),
                        title: const Text('내 프로필'),
                        subtitle: Text(
                          personas.about.trim().isEmpty ? '나에 대해 알려 주면 대화에 참고해요' : personas.about.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final about = await showProfileDialog(context, personas.about);
                          if (about != null) personas.setAbout(about);
                        },
                      ),
                    if (voiceStart != null)
                      SwitchListTile(
                        key: const Key('start-voice'),
                        secondary: const Icon(Icons.record_voice_over_outlined),
                        title: const Text('켜면 바로 음성 대화'),
                        subtitle: const Text('앱을 열면 지금 페르소나와 말로 시작해요'),
                        value: voiceStart.voiceOnStart,
                        onChanged: (v) => voiceStart.voiceOnStart = v,
                      ),
                    if (personas != null && memory != null)
                      ListTile(
                        key: const Key('settings-memory'),
                        leading: const Icon(Icons.auto_stories_outlined),
                        title: const Text('지난 대화 기억'),
                        subtitle: const Text('페르소나별로 정리한 요약 보기·지우기'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openMemoryPage(context, personas: personas, memory: memory),
                      ),
                  ],
                ),
                if (display case final display?)
                  _Section(
                    title: '화면',
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('글자 크기', style: TextStyle(fontSize: 16)),
                            const SizedBox(height: 12),
                            SegmentedButton<TextSize>(
                              key: const Key('text-size'),
                              showSelectedIcon: false,
                              style: SegmentedButton.styleFrom(minimumSize: const Size(0, 52)),
                              segments: [
                                for (final s in TextSize.values)
                                  ButtonSegment(
                                    value: s,
                                    label: Text(s.label, key: Key('text-size-${s.name}')),
                                  ),
                              ],
                              selected: {display.textSize},
                              onSelectionChanged: (v) => display.textSize = v.first,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                if (server case final server?)
                  _Section(
                    title: '연결',
                    children: [
                      ListTile(
                        key: const Key('server'),
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text('서버 주소'),
                        subtitle: Text(server.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => showServerDialog(context, server),
                      ),
                    ],
                  ),
                _Section(
                  title: '앱 정보',
                  children: [
                    ListTile(
                      key: const Key('settings-mode'),
                      leading: const Icon(Icons.info_outline),
                      title: const Text(appDisplayName),
                      subtitle: Text(switch (chat.config) {
                        _ when chat.configFailed => '서버에 연결하지 못했어요',
                        null => '서버에 연결하는 중…',
                        final cfg when cfg.isMock => 'AI: 모의 모드 (시험용 답)',
                        final cfg => 'AI: Claude · ${cfg.model}',
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
          child: Text(
            title,
            style: TextStyle(color: c.muted, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        Material(
          color: c.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ],
    );
  }
}
