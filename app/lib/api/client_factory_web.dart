import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

/// 웹용 클라이언트. `package:http`의 웹 클라이언트는 응답을 다 받은 뒤 돌려줘 스트리밍이 안 된다.
/// 기본값 noCors는 JSON 요청을 막으므로 cors 모드를 쓴다 (같은 출처에서도 동작).
http.Client createHttpClient() => FetchClient(mode: RequestMode.cors);
