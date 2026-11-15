import 'dart:async';

import 'package:flutter/material.dart';

import 'api/account_api.dart';
import 'api/chat_api.dart';
import 'chat/auth_controller.dart';
import 'chat/chat_controller.dart';
import 'chat/display_settings.dart';
import 'chat/server_sync.dart';
import 'chat/start_settings.dart';
import 'storage/app_storage.dart';
import 'storage/prefs_store.dart';
import 'ui/app_shell.dart';
import 'ui/google_sign_in.dart';
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
  final accounts = HttpAccountApi(baseUrl: apiBaseUrl.trim());
  final device = loadDeviceData(store); // 컨트롤러가 기기 값을 바꾸기 전에 읽는다 (F-026 상세 동작 9)
  final controller = ChatController(api, personas: loadPersonas(store), memory: loadMemory(store))..loadConfig();
  // 실시간 음성은 OpenAI Realtime (F-024). 로그인했으면 서버 대화 id를 실어 서버가 DB의 페르소나·기억으로 지시문을 만든다 (F-028)
  final voice = AgentVoiceController(controller, (context) async {
    final id = await controller.voiceConversation().catchError((Object _) => throw const VoiceTokenFailed());
    return api.voiceSession({...context, 'conversationId': ?id});
  }, agent: createRealtimeAgent());
  // 로그인 (F-026): 관리자가 준 코드 또는 연결된 Google 계정. 세션은 서버 쿠키
  final auth = loadAuth(store, api: accounts, google: createGoogleSignIn());
  final start = loadStart(store);
  final display = loadDisplay(store);
  final sync = ServerSync(api: accounts, auth: auth, chat: controller, start: start, display: display, device: device);
  unawaited(auth.start());
  runApp(
    ChatApp(
      controller: controller,
      voice: voice,
      start: start,
      auth: auth,
      sync: sync,
      display: display,
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
    this.sync,
    this.installer,
  });

  final ChatController controller;
  final VoiceSession? voice;

  /// 앱 시작 설정 (F-021). 없으면 설정 칸을 그리지 않는다.
  final StartSettings? start;

  /// 로그인 (F-026·F-023). 없으면 로그인·첫 실행 없이 바로 채팅 화면이다 (테스트).
  final AuthController? auth;

  /// 글자 크기 (F-023). 없으면 기기 글자 크기 그대로.
  final DisplaySettings? display;

  /// 로그인한 뒤 서버 계정 데이터 (F-026~F-028). 없으면 기기 데이터로만 (테스트).
  final ServerSync? sync;

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
              sync: sync,
              installer: installer,
            ),
    );
    if (display == null) return app();
    return ListenableBuilder(listenable: display, builder: (context, _) => app());
  }
}
