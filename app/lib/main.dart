import 'package:flutter/material.dart';

import 'api/chat_api.dart';
import 'chat/chat_controller.dart';
import 'chat/persona_controller.dart';
import 'ui/chat_page.dart';
import 'ui/theme.dart';
import 'voice/plugin_voice_engine.dart';
import 'voice/voice_controller.dart';

/// 서버 주소. 웹은 비워 두면 같은 출처 (ADR-011). 모바일은 빌드할 때 주입 — 키는 절대 넣지 않는다.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

void main() {
  final controller = ChatController(HttpChatApi(baseUrl: apiBaseUrl), personas: PersonaController())..loadConfig();
  final voice = VoiceController(controller, PluginVoiceEngine());
  runApp(ChatApp(controller: controller, voice: voice));
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key, required this.controller, this.voice});

  final ChatController controller;
  final VoiceController? voice;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Agent Chat',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: ChatPage(controller: controller, voice: voice),
    );
  }
}
