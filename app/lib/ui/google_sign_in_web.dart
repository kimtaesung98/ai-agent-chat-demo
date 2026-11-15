import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../chat/auth_controller.dart';

@JS('chatGoogle')
extension type _ChatGoogle._(JSObject _) implements JSObject {
  external JSPromise<JSString> signIn(JSString clientId);
}

@JS('chatGoogle')
external _ChatGoogle get _chatGoogle;

/// 웹: `web/google.js`(window.chatGoogle)로 Google 버튼을 띄워 ID 토큰을 받는다. 스크립트가 없으면 Google 버튼을 숨긴다.
GoogleSignIn? createGoogleSignIn() => globalContext.has('chatGoogle') ? const _WebGoogleSignIn() : null;

class _WebGoogleSignIn implements GoogleSignIn {
  const _WebGoogleSignIn();

  @override
  Future<String?> idToken(String clientId) async {
    final token = (await _chatGoogle.signIn(clientId.toJS).toDart).toDart;
    return token.isEmpty ? null : token;
  }
}
