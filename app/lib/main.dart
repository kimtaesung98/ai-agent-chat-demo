import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api/chat_api.dart';
import 'api/server_address.dart';
import 'chat/chat_controller.dart';
import 'chat/server_settings.dart';
import 'storage/app_storage.dart';
import 'storage/prefs_store.dart';
import 'ui/chat_page.dart';
import 'ui/theme.dart';
import 'voice/plugin_voice_engine.dart';
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
  final controller = ChatController(api, personas: loadPersonas(store))..loadConfig();
  server?.addListener(() {
    api.baseUrl = server.address;
    controller.loadConfig(); // 새 서버의 모드(모의·Claude)를 다시 읽는다
  });
  final voice = VoiceController(controller, PluginVoiceEngine());
  runApp(ChatApp(controller: controller, voice: voice, server: server));
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key, required this.controller, this.voice, this.server});

  final ChatController controller;
  final VoiceController? voice;

  /// 모바일 앱의 서버 주소 설정. 웹은 null.
  final ServerSettings? server;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Agent Chat',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: ChatPage(controller: controller, voice: voice, server: server),
    );
  }
}
