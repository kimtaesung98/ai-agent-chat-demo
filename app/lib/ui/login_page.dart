/// S-004 로그인 화면 (SPEC.md F-023, F-008 화면 기반). 큰 버튼 두 개 — Google로 시작 · 이름만 적고 시작.
/// Google 로그인은 지금 모의다 ([AuthController]가 [GoogleSignIn]을 받는다). 진짜는 F-008에서 갈아 끼운다.
library;

import 'package:flutter/material.dart';

import '../chat/auth_controller.dart';
import 'big_button.dart';
import 'theme.dart';

/// 앱 이름(가칭). 정해지면 여기만 바꾼다.
const appDisplayName = 'AI 말벗';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.auth, this.mockGoogle = false});

  final AuthController auth;

  /// Google 로그인이 모의면 화면 아래에 알린다.
  final bool mockGoogle;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _name = TextEditingController();
  bool _askName = false;

  AuthController get _auth => widget.auth;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _startGuest() => _auth.continueAsGuest(_name.text);

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    return Scaffold(
      key: const Key('login-page'),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _auth,
          builder: (context, _) => Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Hero(colors: c),
                    const SizedBox(height: 48),
                    if (_askName) ..._nameStep(c) else ..._choices(c),
                    if (_auth.error case final error?) ...[
                      const SizedBox(height: 16),
                      Text(
                        error,
                        key: const Key('login-error'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.error, fontSize: 18),
                      ),
                    ],
                    if (widget.mockGoogle && !_askName) ...[
                      const SizedBox(height: 32),
                      Row(
                        key: const Key('login-mock-note'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline, size: 18, color: c.muted),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('시험판이라 Google 로그인은 아직 흉내만 내요', style: TextStyle(color: c.muted, fontSize: 15)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _choices(ChatColors c) => [
    BigButton(
      key: const Key('login-google'),
      label: _auth.busy ? 'Google에 연결하는 중…' : 'Google 계정으로 시작하기',
      style: BigButtonStyle.outlined,
      leading: _auth.busy
          ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3))
          : const _GoogleMark(),
      onPressed: _auth.busy ? null : _auth.signInWithGoogle,
    ),
    const SizedBox(height: 16),
    BigButton(
      key: const Key('login-guest'),
      label: '이름만 적고 시작하기',
      icon: Icons.person_outline,
      style: BigButtonStyle.outlined,
      onPressed: _auth.busy ? null : () => setState(() => _askName = true),
    ),
  ];

  List<Widget> _nameStep(ChatColors c) => [
    Text(
      '어떻게 불러 드릴까요?',
      textAlign: TextAlign.center,
      style: TextStyle(color: c.text, fontSize: 26, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 20),
    TextField(
      key: const Key('login-name'),
      controller: _name,
      autofocus: true,
      maxLength: Account.maxName,
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _startGuest(),
      style: const TextStyle(fontSize: 24),
      decoration: InputDecoration(
        hintText: '예) 김순자',
        counterText: '',
        filled: true,
        fillColor: c.panel,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    const SizedBox(height: 8),
    Text(
      '이름은 이 기기에만 남아요',
      textAlign: TextAlign.center,
      style: TextStyle(color: c.muted, fontSize: 16),
    ),
    const SizedBox(height: 24),
    BigButton(key: const Key('login-guest-start'), label: '시작하기', onPressed: _startGuest),
    const SizedBox(height: 8),
    BigButton(
      key: const Key('login-back'),
      label: '뒤로',
      style: BigButtonStyle.plain,
      onPressed: () => setState(() => _askName = false),
    ),
  ];
}

class _Hero extends StatelessWidget {
  const _Hero({required this.colors});
  final ChatColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(color: c.user.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: c.user, shape: BoxShape.circle),
              child: Icon(Icons.record_voice_over, size: 40, color: c.userText),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          appDisplayName,
          style: TextStyle(color: c.text, fontSize: 34, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          '말로 편하게 이야기 나누는\n나만의 AI 말벗이에요',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 20, height: 1.5),
        ),
      ],
    );
  }
}

/// Google 버튼 앞 "G" 표시. 진짜 Google 로그인(F-008)을 붙일 때 브랜드 지침의 공식 로고로 바꾼다.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFDADCE0)),
      ),
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(color: Color(0xFF4285F4), fontSize: 18, fontWeight: FontWeight.w800),
      ),
    );
  }
}
