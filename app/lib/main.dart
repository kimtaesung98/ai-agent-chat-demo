import 'package:flutter/material.dart';

import 'api/chat_api.dart';
import 'chat/auth_controller.dart';
import 'chat/chat_controller.dart';
import 'chat/display_settings.dart';
import 'chat/start_settings.dart';
import 'storage/app_storage.dart';
import 'storage/prefs_store.dart';
import 'ui/app_shell.dart';
import 'ui/install_hint.dart';
import 'ui/installer.dart';
import 'ui/chat_page.dart';
import 'ui/theme.dart';
import 'voice/agent_voice_controller.dart';
import 'voice/realtime_agent_factory.dart';

/// 서버 주소. 비워 두면 같은 출처 (ADR-011) — 개발 때 다른 주소의 `chatd`를 부를 때만 빌드할 때 넣는다. 키는 절대 넣지 않는다.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KeyValueStore store;
  try {
    store = await PrefsStore.open();
  } catch (_) {
    store = MemoryStore(); // 기기 저장소를 열지 못해도 앱은 뜬다 — 이번 실행만 기억
  }
  final api = HttpChatApi(baseUrl: apiBaseUrl.trim());
  final controller = ChatController(api, personas: loadPersonas(store), memory: loadMemory(store))..loadConfig();
  // 실시간 음성은 OpenAI Realtime (F-024). 안 되면 한 번 알리고 글 대화로 계속한다
  final voice = AgentVoiceController(controller, api.voiceSession, agent: createRealtimeAgent());
  // 로그인 (F-023): 지금은 모의 Google 로그인 — 진짜 Google 로그인·서버 세션은 F-008
  final auth = loadAuth(store, google: const MockGoogleSignIn());
  runApp(
    ChatApp(
      controller: controller,
      voice: voice,
      start: loadStart(store),
      auth: auth,
      display: loadDisplay(store),
      mockGoogle: true,
      installer: createInstaller(),
    ),
  );
}

class ChatApp extends StatelessWidget {
  const ChatApp({
    super.key,
    required this.controller,
    this.voice,
    this.start,
    this.auth,
    this.display,
    this.mockGoogle = false,
    this.installer,
  });

  final ChatController controller;
  final VoiceSession? voice;

  /// 앱 시작 설정 (F-021). 없으면 설정 칸을 그리지 않는다.
  final StartSettings? start;

  /// 로그인 (F-023). 없으면 로그인·첫 실행 없이 바로 채팅 화면이다 (테스트·예전 동작).
  final AuthController? auth;

  /// 글자 크기 (F-023). 없으면 기기 글자 크기 그대로.
  final DisplaySettings? display;

  /// Google 로그인이 모의인지 — 로그인 화면에 알린다.
  final bool mockGoogle;

  /// 웹앱 설치 안내 (F-025). 없으면 안내하지 않는다.
  final Installer? installer;

  @override
  Widget build(BuildContext context) {
    final display = this.display;
    final auth = this.auth;
    Widget app() => MaterialApp(
      title: 'AI 말벗',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // 글자 크기는 기기 설정에 곱한다 — 앱 전체(대화상자 포함)에 적용
      builder: display == null
          ? null
          : (context, child) {
              final mq = MediaQuery.of(context);
              final scale = mq.textScaler.scale(1) * display.textSize.scale;
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              );
            },
      home: auth == null
          ? ChatPage(controller: controller, voice: voice, start: start, display: display, installer: installer)
          : AppShell(
              auth: auth,
              controller: controller,
              voice: voice,
              start: start,
              display: display,
              mockGoogle: mockGoogle,
              installer: installer,
            ),
    );
    if (display == null) return app();
    return ListenableBuilder(listenable: display, builder: (context, _) => app());
  }
}
