/// S-004 로그인 화면 (SPEC.md F-026 상세 동작 2·3, F-023). 계정은 관리자가 만든다 — 받은 **로그인 코드**를 넣거나,
/// 연결된 **Google 계정**으로 들어간다(서버에 Google이 켜져 있을 때만 버튼이 보인다). 스스로 가입하는 길은 없다.
library;

import 'package:flutter/material.dart';

import '../chat/auth_controller.dart';
import 'big_button.dart';
import 'theme.dart';

/// 앱 이름(가칭). 정해지면 여기만 바꾼다.
const appDisplayName = 'AI 말벗';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _code = TextEditingController();

  AuthController get _auth => widget.auth;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() => _auth.signInWithCode(_code.text);

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
                    const SizedBox(height: 40),
                    Text(
                      '받으신 로그인 코드를 넣어 주세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('login-code'),
                      controller: _code,
                      enabled: !_auth.busy,
                      maxLength: 14,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      style: const TextStyle(fontSize: 28, letterSpacing: 2, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'K7QM-4XPH-2R',
                        counterText: '',
                        filled: true,
                        fillColor: c.panel,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '요양사·관리자에게 받은 10자리 코드예요. 한 번만 쓸 수 있어요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted, fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    BigButton(
                      key: const Key('login-code-start'),
                      label: _auth.busy ? '확인하는 중…' : '들어가기',
                      onPressed: _auth.busy ? null : _submit,
                    ),
                    if (_auth.googleAvailable) ...[
                      const SizedBox(height: 16),
                      BigButton(
                        key: const Key('login-google'),
                        label: 'Google 계정으로 들어가기',
                        style: BigButtonStyle.outlined,
                        leading: const _GoogleMark(),
                        onPressed: _auth.busy ? null : _auth.signInWithGoogle,
                      ),
                    ],
                    if (_auth.error case final error?) ...[
                      const SizedBox(height: 16),
                      Text(
                        error,
                        key: const Key('login-error'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.error, fontSize: 18),
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

/// Google 버튼 앞 "G" 표시. 실제 Google 창(google.js)은 공식 버튼을 그린다.
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
