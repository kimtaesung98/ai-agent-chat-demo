import 'package:http/http.dart' as http;

/// 웹이 아닌 곳(테스트 VM)용 클라이언트.
http.Client createHttpClient() => http.Client();
