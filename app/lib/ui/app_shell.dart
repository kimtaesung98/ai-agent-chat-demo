/// 첫 화면 고르기 (SPEC.md F-023 §6.2, F-026): 세션 확인 중 → 로그인 전이면 S-004 로그인 → 내 정보 받기 →
/// 기기 데이터 옮기기 묻기(한 번) → 첫 실행이면 S-005 대화 상대 고르기 → 그 뒤 S-001 채팅.
/// 로그인·서버 상태가 바뀌면 이 위젯이 화면을 바꾼다 — 화면끼리 서로 이동시키지 않는다.
library;

import 'package:flutter/material.dart';

import '../chat/auth_controller.dart';
import '../chat/chat_controller.dart';
import '../chat/display_settings.dart';
import '../chat/server_sync.dart';
import '../chat/start_settings.dart';
import '../voice/voice_session.dart';
import 'big_button.dart';
import 'chat_page.dart';
import 'install_hint.dart';
import 'login_page.dart';
import 'onboarding_page.dart';
import 'theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.auth,
    required this.controller,
    this.sync,
    this.voice,
    this.start,
    this.display,
    this.installer,
  });

  final AuthController auth;
  final ChatController controller;

  /// 서버 계정 데이터 (F-026~F-028). 없으면 로그인 뒤 바로 채팅이다 (테스트).
  final ServerSync? sync;
  final VoiceSession? voice;
  final StartSettings? start;
  final DisplaySettings? display;
  final Installer? installer;

  @override
  Widget build(BuildContext context) {
    final sync = this.sync;
    return ListenableBuilder(
      listenable: Listenable.merge([auth, ?sync]),
      builder: (context, _) {
        if (auth.phase == AuthPhase.checking) return const _Waiting(key: Key('auth-checking'), text: '들어가는 중…');
        if (!auth.signedIn) return LoginPage(auth: auth);
        if (sync != null) {
          switch (sync.state) {
            case SyncState.idle || SyncState.loading:
              return const _Waiting(key: Key('sync-loading'), text: '내 대화 상대를 불러오는 중…');
            case SyncState.failed:
              return _LoadFailed(sync: sync, auth: auth);
            case SyncState.ready when sync.importPending:
              return ImportPage(sync: sync);
            case SyncState.ready:
          }
        }
        final personas = controller.personas;
        if (!auth.onboarded && personas != null) {
          return OnboardingPage(
            auth: auth,
            personas: personas,
            start: voice == null ? null : start,
            hasVoice: voice != null,
          );
        }
        return ChatPage(
          controller: controller,
          voice: voice,
          start: start,
          auth: auth,
          display: display,
          installer: installer,
        );
      },
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(text, style: TextStyle(color: c.muted, fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.sync, required this.auth});
  final ServerSync sync;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    return Scaffold(
      key: const Key('sync-failed'),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.cloud_off, size: 56, color: c.muted),
                  const SizedBox(height: 16),
                  Text(
                    sync.error ?? SyncMessages.loadFailed,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.text, fontSize: 20),
                  ),
                  const SizedBox(height: 24),
                  BigButton(key: const Key('sync-retry'), label: '다시 하기', onPressed: sync.load),
                  const SizedBox(height: 8),
                  BigButton(label: '로그아웃', style: BigButtonStyle.plain, onPressed: auth.signOut),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 처음 로그인한 뒤 한 번: "이 기기의 대화 상대와 기억을 내 계정으로 옮길까요?" (F-026 상세 동작 9)
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, required this.sync});
  final ServerSync sync;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  String? _error;

  Future<void> _import() async {
    final error = await widget.sync.importDevice();
    if (mounted) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final busy = widget.sync.importing;
    return Scaffold(
      key: const Key('import-page'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.move_to_inbox_outlined, size: 64, color: c.user),
                  const SizedBox(height: 20),
                  Text(
                    '이 기기의 대화 상대와 기억을\n내 계정으로 옮길까요?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.text, fontSize: 26, fontWeight: FontWeight.w800, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '옮기면 다른 기기에서 로그인해도 이어서 이야기할 수 있어요. 한 번만 물어봐요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, fontSize: 18, height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  BigButton(
                    key: const Key('import-yes'),
                    label: busy ? '옮기는 중…' : '네, 옮길게요',
                    onPressed: busy ? null : _import,
                  ),
                  const SizedBox(height: 8),
                  BigButton(
                    key: const Key('import-no'),
                    label: '아니요, 새로 시작할게요',
                    style: BigButtonStyle.plain,
                    onPressed: busy ? null : widget.sync.skipImport,
                  ),
                  if (_error case final error?) ...[
                    const SizedBox(height: 16),
                    Text(
                      error,
                      key: const Key('import-error'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.error, fontSize: 18),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
