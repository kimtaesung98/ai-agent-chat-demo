import 'package:flutter/material.dart';

import 'api/chat_api.dart';
import 'chat/chat_controller.dart';
import 'ui/chat_page.dart';
import 'ui/theme.dart';

/// 서버 주소. 웹은 비워 두면 같은 출처 (ADR-011). 모바일은 빌드할 때 주입 — 키는 절대 넣지 않는다.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

void main() {
  final controller = ChatController(HttpChatApi(baseUrl: apiBaseUrl))..loadConfig();
  runApp(ChatApp(controller: controller));
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key, required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Agent Chat',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: ChatPage(controller: controller),
    );
  }
}
