/// 첫 화면 고르기 (SPEC.md F-023 §6.2): 로그인 전 → S-004 로그인, 첫 실행 → S-005 대화 상대 고르기, 그 뒤 → S-001 채팅.
/// 로그인 상태가 바뀌면 이 위젯이 화면을 바꾼다 — 화면끼리 서로 이동시키지 않는다.
library;

import 'package:flutter/material.dart';

import '../chat/auth_controller.dart';
import '../chat/chat_controller.dart';
import '../chat/display_settings.dart';
import '../chat/server_settings.dart';
import '../chat/start_settings.dart';
import '../voice/voice_controller.dart';
import 'chat_page.dart';
import 'install_hint.dart';
import 'login_page.dart';
import 'onboarding_page.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.auth,
    required this.controller,
    this.voice,
    this.server,
    this.start,
    this.display,
    this.mockGoogle = false,
    this.installer,
  });

  final AuthController auth;
  final ChatController controller;
  final VoiceSession? voice;
  final ServerSettings? server;
  final StartSettings? start;
  final DisplaySettings? display;
  final bool mockGoogle;
  final Installer? installer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (!auth.signedIn) return LoginPage(auth: auth, mockGoogle: mockGoogle);
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
          server: server,
          start: start,
          auth: auth,
          display: display,
          installer: installer,
        );
      },
    );
  }
}
