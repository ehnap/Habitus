import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:habitus/src/failure.dart';
import 'package:habitus/src/playback/format_policy.dart';
import 'package:habitus/src/subsonic/auth.dart';
import 'package:habitus/src/subsonic/client.dart';

void main() {
  test('form post, decision json, wrong password, and folder retry', () async {
    final hits = <_Hit>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final bodyBytes = await request.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      final hit = _Hit(request.method, request.uri, utf8.decode(bodyBytes), request.headers.contentType?.mimeType);
      hits.add(hit);
      final endpoint = request.uri.path;
      final query = request.uri.queryParameters;
      final form = Uri.splitQueryString(hit.body);
      Map<String, dynamic> payload;
      if (endpoint.endsWith('getOpenSubsonicExtensions.view')) {
        payload = {
          'type': 'navidrome',
          'serverVersion': '0.64.2',
          'openSubsonicExtensions': [
            {'name': 'formPost'},
            {'name': 'transcoding'},
            {'name': 'songLyrics'},
            {'name': 'transcodeOffset'},
          ],
        };
      } else if (endpoint.endsWith('ping.view')) {
        final token = form['t'] ?? query['t'];
        final salt = form['s'] ?? query['s'];
        if (token != subsonicToken('secret', salt ?? '')) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'subsonic-response': {
                'status': 'failed',
                'version': '1.16.1',
                'error': {'code': 40, 'message': 'Wrong username or password'},
              },
            }),
          );
          await request.response.close();
          return;
        }
        payload = {};
      } else if (endpoint.endsWith('getTranscodeDecision.view')) {
        payload = {
          'transcodeDecision': {
            'canDirectPlay': true,
            'canTranscode': false,
            'transcodeParams': 'copied',
            'sourceStream': {'codec': 'flac', 'container': 'flac'},
          },
        };
      } else if (endpoint.endsWith('getAlbumList2.view')) {
        final folder = query['musicFolderId'] ?? form['musicFolderId'];
        if (folder != null) {
          payload = {};
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'subsonic-response': {
                'status': 'failed',
                'version': '1.16.1',
                'error': {'code': 0, 'message': 'no folder'},
              },
            }),
          );
          await request.response.close();
          return;
        }
        payload = {
          'albumList2': {
            'album': {'id': 'a', 'name': '专辑', 'artist': '甲'},
          },
        };
      } else {
        payload = {};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'subsonic-response': {'status': 'ok', 'version': '1.16.1', ...payload},
        }),
      );
      await request.response.close();
    });

    final client = SubsonicClient()
      ..baseUrl = 'http://127.0.0.1:${server.port}'
      ..username = 'ada'
      ..password = 'secret';
    final info = await client.openExtensions();
    expect(info.hasFormPost, isTrue);
    expect(hits.first.uri.queryParameters.containsKey('u'), isFalse);
    client.formPost = true;
    await client.ping();
    final ping = hits[1];
    final pingForm = Uri.splitQueryString(ping.body);
    expect(ping.method, 'POST');
    expect(ping.uri.query, isEmpty);
    expect(ping.contentType, 'application/x-www-form-urlencoded');
    expect(pingForm['u'], 'ada');
    expect(pingForm['p'], isNull);
    expect(ping.body.contains('secret'), isFalse);
    expect(pingForm['t'], subsonicToken('secret', pingForm['s']!));

    client.formPost = false;
    final decision = await client.transcodeDecision(
      mediaId: 'song-1',
      body: clientInfoBody(platformLabel: 'Android', platform: PlatformGroup.android, allowDirect: true),
    );
    expect(decision.transcodeParams, 'copied');
    expect(decision.canDirectPlay, isTrue);
    final decisionHit = hits[2];
    expect(decisionHit.method, 'POST');
    expect(decisionHit.uri.queryParameters.containsKey('password'), isFalse);
    expect(decisionHit.uri.queryParameters['t'], subsonicToken('secret', decisionHit.uri.queryParameters['s']!));
    final decisionBody = jsonDecode(decisionHit.body) as Map<String, dynamic>;
    expect(decisionBody['maxTranscodingAudioBitrate'], 256000);
    expect(jsonEncode(decisionBody).toLowerCase().contains('hls'), isFalse);

    final albums = await client.albumList(type: 'newest', musicFolderId: '9');
    expect(albums.single.name, '专辑');
    expect(client.folderFilterDropped, isTrue);

    client.password = 'wrong';
    await expectLater(
      client.ping(),
      throwsA(isA<AppFailure>().having((error) => error.kind, 'kind', FailureKind.wrongCredentials)),
    );

    client.close();
    await server.close(force: true);
  });

  test('self-signed certificate is refused until trusted, and a changed pin blocks the password', () async {
    final dir = await Directory.systemTemp.createTemp('habitus-tls');
    final cert = '${dir.path}/cert.pem';
    final key = '${dir.path}/key.pem';
    final generated = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-keyout',
      key,
      '-out',
      cert,
      '-days',
      '1',
      '-nodes',
      '-subj',
      '/CN=localhost',
    ]);
    expect(generated.exitCode, 0, reason: generated.stderr.toString());
    final context = SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(key);
    var requests = 0;
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    server.listen((request) async {
      requests += 1;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'subsonic-response': {'status': 'ok', 'version': '1.16.1'},
        }),
      );
      await request.response.close();
    });
    final base = 'https://127.0.0.1:${server.port}';

    final refused = SubsonicClient()
      ..baseUrl = base
      ..username = 'ada'
      ..password = 'secret';
    await expectLater(
      refused.ping(),
      throwsA(isA<AppFailure>().having((error) => error.kind, 'kind', FailureKind.certificateUntrusted)),
    );
    await _settle();
    expect(requests, 0);
    refused.close();

    final trusted = SubsonicClient()
      ..baseUrl = base
      ..username = 'ada'
      ..password = 'secret'
      ..trustNewCertificate = true;
    await trusted.ping();
    expect(requests, 1);
    final fingerprint = trusted.acceptedFingerprint;
    expect(fingerprint, isNotNull);
    trusted.close();

    final changed = SubsonicClient()
      ..baseUrl = base
      ..username = 'ada'
      ..password = 'secret'
      ..pinnedFingerprint = '00' * 32;
    await expectLater(
      changed.ping(),
      throwsA(isA<AppFailure>().having((error) => error.kind, 'kind', FailureKind.certificateChanged)),
    );
    await _settle();
    expect(requests, 1);
    changed.close();

    await server.close(force: true);
    await dir.delete(recursive: true);
  });
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

class _Hit {
  _Hit(this.method, this.uri, this.body, this.contentType);

  final String method;
  final Uri uri;
  final String body;
  final String? contentType;
}
