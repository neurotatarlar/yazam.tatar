// HTTP client for one-way streaming correction calls.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Wraps streaming correction calls to the backend.
class BackendClient {
  BackendClient(this.baseUrl);

  final String baseUrl;

  /// Resolve a path against the configured base URL.
  Uri _endpoint(String path) {
    final base = Uri.parse(baseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final fullPath = basePath.isEmpty ? path : '$basePath$path';
    return base.replace(path: fullPath);
  }

  /// Start a streaming correction request and emit SSE events.
  Stream<SseEvent> streamCorrect({
    required String text,
    required String lang,
    required String platform,
  }) {
    final controller = StreamController<SseEvent>();
    final client = http.Client();
    StreamSubscription<String>? subscription;

    controller
      ..onListen = () async {
        try {
          final uri = _endpoint('/v1/correct/stream');
          final request = http.Request('POST', uri);
          request.headers['Content-Type'] = 'application/json';
          request.headers['Accept'] = 'text/event-stream';
          request.body = jsonEncode({
            'text': text,
            'lang': lang,
            'client': {'platform': platform, 'version': 'flutter-0.1'},
          });

          final response = await client.send(request);
          if (response.statusCode != 200) {
            final body = await response.stream.bytesToString();
            final message = _extractErrorMessage(body, response.statusCode);
            client.close();
            throw Exception(message);
          }

          var buffer = '';
          var currentEvent = 'message';
          var currentData = '';

          subscription = response.stream
              .transform(utf8.decoder)
              .listen(
                (chunk) {
                  buffer += chunk;
                  while (buffer.contains('\n')) {
                    final index = buffer.indexOf('\n');
                    final line = buffer.substring(0, index).trimRight();
                    buffer = buffer.substring(index + 1);

                    if (line.isEmpty) {
                      if (currentData.isNotEmpty) {
                        final data =
                            jsonDecode(currentData) as Map<String, dynamic>;
                        controller.add(SseEvent(currentEvent, data));
                      }
                      currentEvent = 'message';
                      currentData = '';
                      continue;
                    }

                    if (line.startsWith('event:')) {
                      currentEvent = line.replaceFirst('event:', '').trim();
                    } else if (line.startsWith('data:')) {
                      final dataPart = line.replaceFirst('data:', '').trim();
                      if (currentData.isNotEmpty) {
                        currentData += '\n';
                      }
                      currentData += dataPart;
                    }
                  }
                },
                onDone: () {
                  if (!controller.isClosed) {
                    unawaited(controller.close());
                  }
                },
                onError: (Object err, StackTrace stack) {
                  if (!controller.isClosed) {
                    controller.addError(err, stack);
                  }
                },
              );
        } on Object catch (err, stack) {
          client.close();
          if (!controller.isClosed) {
            controller.addError(err, stack);
            await controller.close();
          }
        }
      }
      ..onCancel = () async {
        await subscription?.cancel();
        client.close();
        if (!controller.isClosed) {
          await controller.close();
        }
      };

    return controller.stream;
  }
}

/// Parse error messages from backend error payloads.
String _extractErrorMessage(String body, int statusCode) {
  if (body.isNotEmpty) {
    try {
      final payload = jsonDecode(body);
      if (payload is Map<String, dynamic>) {
        final detail = payload['detail'];
        if (detail is Map<String, dynamic>) {
          final message = detail['message'];
          if (message != null) {
            return message.toString();
          }
          final error = detail['error'];
          if (error != null) {
            return error.toString();
          }
        }
        if (detail is String) {
          return detail;
        }
      }
    } on Object catch (_) {}
  }
  return 'stream_failed:$statusCode';
}
