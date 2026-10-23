import 'package:dio/dio.dart';

import 'network_security.dart';
import 'webos.dart';

/// Einziger Weg, über den die App HTTP-Anfragen stellt: jede Anfrage trägt
/// den getarnten User-Agent und läuft vorher durch den Kill-Switch.
Dio createHttpClient({
  required String userAgent,
  required NetworkGuard guard,
  Duration connectTimeout = const Duration(seconds: 15),
  Duration receiveTimeout = const Duration(seconds: 60),
}) {
  final dio = Dio(
    BaseOptions(connectTimeout: connectTimeout, receiveTimeout: receiveTimeout, headers: {'User-Agent': userAgent}),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          await guard.ensureAllowed();
          if (isWebOs) {
            final agent = options.headers.remove('User-Agent') as String?;
            final target = options.uri.toString();
            options
              ..baseUrl = ''
              ..queryParameters = {}
              ..path = proxiedUrl(target, userAgent: agent);
          }
          handler.next(options);
        } on KillSwitchException catch (e) {
          handler.reject(DioException(requestOptions: options, error: e, type: DioExceptionType.cancel));
        }
      },
    ),
  );
  return dio;
}

/// Verständliche Fehlermeldung für Anfragen, die der Kill-Switch gestoppt hat.
bool isKillSwitchError(Object error) =>
    error is KillSwitchException || (error is DioException && error.error is KillSwitchException);
