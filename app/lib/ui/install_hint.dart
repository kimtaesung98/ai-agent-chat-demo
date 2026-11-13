/// 홈 화면에 추가 안내 (SPEC.md F-025 AC3, ARCHITECTURE.md ADR-027).
/// 설치 전 브라우저에서만 보인다: Android Chrome 등은 설치 창을 띄우는 버튼, iPhone Safari는 "공유 → 홈 화면에 추가" 안내.
/// 플랫폼 기능은 [Installer] 뒤에 두어 위젯 테스트는 가짜를 쓴다. 구현은 `installer_web.dart`(`web/pwa.js`).
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 지금 브라우저에서 할 수 있는 설치 방법.
enum InstallMode {
  /// 이미 홈 화면 앱으로 열었다 — 안내하지 않는다.
  installed,

  /// 브라우저가 설치 창을 띄울 수 있다 (Android Chrome 등).
  prompt,

  /// iPhone·iPad — 공유 메뉴에서 직접 추가해야 한다.
  ios,

  /// 설치할 수 없는 곳(데스크톱 일부 브라우저·네이티브 앱).
  unsupported,
}

/// 설치 상태와 동작. 브라우저가 설치 창을 늦게 알려 줄 수 있어 바뀌면 알린다.
abstract interface class Installer implements Listenable {
  InstallMode get mode;

  /// 사용자가 안내를 닫았는지 (이 브라우저에 기억).
  bool get dismissed;
  void dismiss();

  /// 설치 창을 띄운다. 설치했으면 true.
  Future<bool> install();

  /// 이 브라우저가 화면 꺼짐 막기(Wake Lock)를 지원하는지 (F-025 AC4).
  bool get wakeLockSupported;
}

/// 안내 문구.
abstract final class InstallTexts {
  static const title = '홈 화면에 추가해 보세요';
  static const prompt = '앱처럼 바로 열리고, 화면이 넓어져요.';
  static const ios = 'Safari 아래쪽의 공유 버튼을 누르고 "홈 화면에 추가"를 고르면 앱처럼 열려요.';
  static const install = '추가하기';
  static const close = '닫기';
}

/// 채팅 화면 위쪽 안내 띠. 설치했거나 닫았거나 설치할 수 없으면 아무것도 그리지 않는다.
class InstallBanner extends StatelessWidget {
  const InstallBanner({super.key, required this.installer});

  final Installer installer;

  static bool shows(Installer i) => !i.dismissed && (i.mode == InstallMode.prompt || i.mode == InstallMode.ios);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: installer,
      builder: (context, _) {
        if (!shows(installer)) return const SizedBox.shrink();
        final c = ChatColors.of(context);
        final ios = installer.mode == InstallMode.ios;
        return Container(
          key: const Key('install-banner'),
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(ios ? Icons.ios_share : Icons.add_to_home_screen, color: c.user, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(InstallTexts.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(ios ? InstallTexts.ios : InstallTexts.prompt, style: TextStyle(fontSize: 15, color: c.muted)),
                    if (!ios) ...[
                      const SizedBox(height: 10),
                      FilledButton(
                        key: const Key('install-button'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(120, 48),
                          backgroundColor: c.user,
                          foregroundColor: c.userText,
                        ),
                        onPressed: installer.install,
                        child: const Text(InstallTexts.install, style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                key: const Key('install-close'),
                tooltip: InstallTexts.close,
                iconSize: 26,
                onPressed: installer.dismiss,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        );
      },
    );
  }
}
