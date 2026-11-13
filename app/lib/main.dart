import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api/chat_api.dart';
import 'api/server_address.dart';
import 'chat/auth_controller.dart';
import 'chat/chat_controller.dart';
import 'chat/display_settings.dart';
import 'chat/server_settings.dart';
import 'chat/start_settings.dart';
import 'storage/app_storage.dart';
import 'storage/prefs_store.dart';
import 'ui/app_shell.dart';
import 'ui/chat_page.dart';
import 'ui/theme.dart';
import 'voice/agent_voice_controller.dart';
import 'voice/plugin_voice_engine.dart';
import 'voice/realtime_agent_factory.dart';
import 'voice/voice_controller.dart';

/// 서버 주소. 웹은 비워 두면 같은 출처 (ADR-011). 모바일은 빌드할 때 주입 — 키는 절대 넣지 않는다.
/// 모바일에서 비워 두면 에뮬레이터·시뮬레이터에서 개발 컴퓨터의 `chatd`를 부른다 (F-017).
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

AppPlatform get _platform {
  if (kIsWeb) return AppPlatform.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => AppPlatform.android,
    TargetPlatform.iOS => AppPlatform.ios,
    _ => AppPlatform.other,
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KeyValueStore store;
  try {
    store = await PrefsStore.open();
  } catch (_) {
    store = MemoryStore(); // 기기 저장소를 열지 못해도 앱은 뜬다 — 이번 실행만 기억
  }
  // 웹은 같은 출처라 주소 설정이 없다. 모바일은 빌드 때 주소가 기본, 앱에서 바꿀 수 있다 (F-017 AC7)
  final fallback = resolveServerAddress(configured: apiBaseUrl, platform: _platform);
  final server = kIsWeb ? null : loadServer(store, fallback: fallback);
  final api = HttpChatApi(baseUrl: server?.address ?? fallback);
  final controller = ChatController(api, personas: loadPersonas(store), memory: loadMemory(store))..loadConfig();
  server?.addListener(() {
    api.baseUrl = server.address;
    controller.loadConfig(); // 새 서버의 모드(모의·Claude)를 다시 읽는다
  });
  // 실시간 음성(웹: OpenAI Realtime F-024, 앱: ElevenLabs F-022)이 되면 그것으로, 아니면 기기 음성(F-012)으로 대화한다
  final voice = AgentVoiceController(
    controller,
    (context) => controller.config?.voiceProvider == 'openai' ? api.voiceSession(context) : api.voiceToken(),
    VoiceController(controller, PluginVoiceEngine()),
    agent: createRealtimeAgent(),
  );
  // 로그인 (F-023): 지금은 모의 Google 로그인 — 진짜 Google 로그인·서버 세션은 F-008
  final auth = loadAuth(store, google: const MockGoogleSignIn());
  runApp(
    ChatApp(
      controller: controller,
      voice: voice,
      server: server,
      start: loadStart(store),
      auth: auth,
      display: loadDisplay(store),
      mockGoogle: true,
    ),
  );
}

class ChatApp extends StatelessWidget {
  const ChatApp({
    super.key,
    required this.controller,
    this.voice,
    this.server,
    this.start,
    this.auth,
    this.display,
    this.mockGoogle = false,
  });

  final ChatController controller;
  final VoiceSession? voice;

  /// 모바일 앱의 서버 주소 설정. 웹은 null.
  final ServerSettings? server;

  /// 앱 시작 설정 (F-021). 없으면 설정 칸을 그리지 않는다.
  final StartSettings? start;

  /// 로그인 (F-023). 없으면 로그인·첫 실행 없이 바로 채팅 화면이다 (테스트·예전 동작).
  final AuthController? auth;

  /// 글자 크기 (F-023). 없으면 기기 글자 크기 그대로.
  final DisplaySettings? display;

  /// Google 로그인이 모의인지 — 로그인 화면에 알린다.
  final bool mockGoogle;

  @override
  Widget build(BuildContext context) {
    final display = this.display;
    final auth = this.auth;
    Widget app() => MaterialApp(
      title: 'AI Agent Chat',
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
          ? ChatPage(controller: controller, voice: voice, server: server, start: start, display: display)
          : AppShell(
              auth: auth,
              controller: controller,
              voice: voice,
              server: server,
              start: start,
              display: display,
              mockGoogle: mockGoogle,
            ),
    );
    if (display == null) return app();
    return ListenableBuilder(listenable: display, builder: (context, _) => app());
  }
}
