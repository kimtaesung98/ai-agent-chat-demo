import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/main.dart';
import 'package:ai_agent_chat/ui/install_hint.dart';
import 'package:ai_agent_chat/ui/voice_page.dart';
import 'package:ai_agent_chat/voice/voice_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// 테스트가 상태를 정하는 가짜 설치기.
class FakeInstaller extends ChangeNotifier implements Installer {
  FakeInstaller(this.mode, {this.wakeLockSupported = true});

  @override
  InstallMode mode;
  @override
  bool dismissed = false;
  @override
  bool wakeLockSupported;
  var installs = 0;

  @override
  void dismiss() {
    dismissed = true;
    notifyListeners();
  }

  @override
  Future<bool> install() async {
    installs++;
    mode = InstallMode.installed;
    notifyListeners();
    return true;
  }
}

void main() {
  Future<ChatController> open(WidgetTester tester, FakeInstaller installer, {VoiceSession? voice}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chat = ChatController(FakeApi());
    await tester.pumpWidget(ChatApp(controller: chat, voice: voice, installer: installer));
    await tester.pump();
    return chat;
  }

  testWidgets('F-025 AC3 Android 등 설치 창을 띄울 수 있으면 추가하기 버튼을 보여 주고, 설치하면 사라진다', (tester) async {
    final installer = FakeInstaller(InstallMode.prompt);
    await open(tester, installer);
    expect(find.byKey(const Key('install-banner')), findsOneWidget);
    expect(find.text(InstallTexts.prompt), findsOneWidget);
    await tester.tap(find.byKey(const Key('install-button')));
    await tester.pump();
    expect(installer.installs, 1);
    expect(find.byKey(const Key('install-banner')), findsNothing);
  });

  testWidgets('F-025 AC3 iPhone은 공유 → 홈 화면에 추가 안내를 보여 주고(버튼 없음), 닫으면 사라진다', (tester) async {
    final installer = FakeInstaller(InstallMode.ios);
    await open(tester, installer);
    expect(find.text(InstallTexts.ios), findsOneWidget);
    expect(find.byKey(const Key('install-button')), findsNothing);
    await tester.tap(find.byKey(const Key('install-close')));
    await tester.pump();
    expect(installer.dismissed, isTrue);
    expect(find.byKey(const Key('install-banner')), findsNothing);
  });

  testWidgets('F-025 AC3 이미 설치해 열었거나 설치할 수 없거나 닫아 두었으면 안내하지 않는다', (tester) async {
    for (final installer in [
      FakeInstaller(InstallMode.installed),
      FakeInstaller(InstallMode.unsupported),
      FakeInstaller(InstallMode.prompt)..dismissed = true,
    ]) {
      await open(tester, installer);
      expect(find.byKey(const Key('install-banner')), findsNothing, reason: '${installer.mode}');
    }
  });

  testWidgets('F-025 AC4 화면 꺼짐 막기를 지원하지 않는 브라우저면 음성 화면에서 한 번 안내한다', (tester) async {
    final chat = ChatController(FakeApi());
    final voice = VoiceController(chat, FakeVoiceEngine());
    addTearDown(voice.dispose);
    await open(tester, FakeInstaller(InstallMode.installed, wakeLockSupported: false), voice: voice);
    await tester.tap(find.byKey(const Key('open-voice-page')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(VoicePage.noWakeLock), findsWidgets); // 뒤의 채팅 화면 Scaffold에도 같이 붙는다
    voice.stop();
  });
}
