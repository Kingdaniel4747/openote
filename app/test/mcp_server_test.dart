import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/api/learning_access.dart';
import 'package:openote/api/mcp_server.dart';

void main() {
  late McpServer server;
  late HttpClient client;
  late Uri uri;
  late String token;
  var calls = 0;
  Completer<Map<String, dynamic>>? pending;

  setUp(() async {
    calls = 0;
    pending = null;
    token = McpServer.newToken();
    server = McpServer(
        tools: LearningAccess.tools,
        callTool: (_, __) async {
          calls++;
          if (pending != null) return pending!.future;
          return {
            'content': [
              {'type': 'text', 'text': 'allowed'}
            ]
          };
        });
    final port = await server.start(token: token, port: 0);
    uri = Uri.parse('http://127.0.0.1:$port/mcp');
    client = HttpClient();
  });
  tearDown(() async {
    await server.stop();
    client.close(force: true);
  });

  Future<({int status, dynamic body})> send(dynamic body,
      {String method = 'POST',
      String? authorization,
      String? origin,
      String? host,
      Uri? target}) async {
    final request = await client.openUrl(method, target ?? uri);
    request.headers.contentType = ContentType.json;
    request.headers.set('Accept', 'application/json, text/event-stream');
    request.headers.set('Authorization', authorization ?? 'Bearer $token');
    if (origin != null) request.headers.set('Origin', origin);
    if (host != null) request.headers.set('Host', host);
    if (method == 'POST') {
      request.write(body is String ? body : jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (
      status: response.statusCode,
      body: text.isEmpty ? null : jsonDecode(text)
    );
  }

  Map<String, dynamic> rpc(String method, [Map<String, dynamic>? params]) => {
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        if (params != null) 'params': params,
      };

  test('MCP initialize, tools/list, notification, ping and call interoperate',
      () async {
    final init = await send(rpc('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': {},
      'clientInfo': {'name': 'test', 'version': '1'}
    }));
    expect(init.status, 200);
    expect(init.body['result']['protocolVersion'], '2025-06-18');
    expect(init.body['result']['capabilities'], {'tools': {}});
    final notification =
        await send({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    expect(notification.status, 202);
    expect((await send(rpc('ping'))).body['result'], isEmpty);
    final listed =
        (await send(rpc('tools/list'))).body['result']['tools'] as List;
    expect(listed.map((t) => t['name']), [
      'get_context',
      'list_pages',
      'search_pages',
      'read_page',
      'read_page_image'
    ]);
    expect(
        listed.every((t) => t['annotations']['readOnlyHint'] == true), isTrue);
    final result = await send(rpc('tools/call', {'name': 'get_context'}));
    expect(result.body['result']['content'][0]['text'], 'allowed');
    expect(calls, 1);
  });

  test('wrong token, browser origin and DNS rebinding cannot invoke tools',
      () async {
    final request = rpc('tools/call', {'name': 'read_page'});
    expect((await send(request, authorization: 'Bearer wrong')).status, 401);
    expect(
        (await send(request, origin: 'https://attacker.example')).status, 403);
    expect((await send(request, host: 'attacker.example:${uri.port}')).status,
        403);
    expect(calls, 0);
  });

  test('GET and arbitrary paths never expose data', () async {
    expect((await send(null, method: 'GET')).status, 405);
    expect(
        (await send(rpc('ping'), target: uri.replace(path: '/workspace')))
            .status,
        404);
    expect(
        (await send(rpc('ping'), target: uri.replace(query: 'token=x'))).status,
        404);
    expect(calls, 0);
  });

  test('malformed messages and write methods fail without invoking tools',
      () async {
    expect((await send('{')).body['error']['code'], -32700);
    expect((await send([rpc('ping')])).body['error']['code'], -32600);
    expect((await send(rpc('write_page'))).body['error']['code'], -32601);
    expect(
        (await send(rpc('tools/call', {'name': 'delete_page'}))).body['error']
            ['code'],
        -32602);
    expect(calls, 0);
  });

  test('request body has a hard bound', () async {
    expect((await send('x' * 65537)).status, 413);
    expect(calls, 0);
  });

  test('turning server off revokes a pending response', () async {
    pending = Completer();
    final request = send(rpc('tools/call', {'name': 'read_page'}));
    // Register the error handler before the force-close.
    final outcome = request.then<Object>((value) => value,
        onError: (Object error) => error);
    while (calls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await server.stop();
    pending!.complete({
      'content': [
        {'type': 'text', 'text': 'secret'}
      ]
    });
    final result = await outcome;
    if (result is ({int status, dynamic body})) {
      expect(result.body?.toString() ?? '', isNot(contains('secret')));
    } else {
      expect(result, isA<Exception>());
    }
  });
}
