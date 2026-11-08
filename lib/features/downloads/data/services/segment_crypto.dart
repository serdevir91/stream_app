import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';

import 'hls.dart';

/// Decrypts AES-128 HLS segments and writes them to disk on one long-lived
/// isolate, so the UI thread never runs AES and no isolate is spawned per
/// segment.
class SegmentCrypto {
  Isolate? _isolate;
  ReceivePort? _receive;
  SendPort? _send;
  Future<void>? _starting;
  int _nextId = 0;
  final Map<int, Completer<int>> _pending = {};

  static Uint8List decryptAes128(Uint8List data, Uint8List key, Uint8List iv) {
    final encrypter = Encrypter(AES(Key(key), mode: AESMode.cbc, padding: null));
    final out = Uint8List.fromList(
      encrypter.decryptBytes(Encrypted(data), iv: IV(iv)),
    );
    return Hls.pkcs7Unpad(out);
  }

  Future<void> _ensureStarted() {
    if (_send != null) return Future.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final receive = ReceivePort();
    final ready = Completer<SendPort>();
    receive.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      if (message is List && message.length == 3) {
        final completer = _pending.remove(message[0] as int);
        if (completer == null) return;
        final error = message[2];
        if (error != null) {
          completer.completeError(Exception(error.toString()));
        } else {
          completer.complete(message[1] as int);
        }
      }
    });
    _receive = receive;
    _isolate = await Isolate.spawn(_entry, receive.sendPort);
    _send = await ready.future;
  }

  /// Decrypts [data] and writes it to [path]; returns the written length.
  Future<int> decryptToFile(
    Uint8List data,
    Uint8List key,
    Uint8List iv,
    String path,
  ) async {
    await _ensureStarted();
    final id = _nextId++;
    final completer = Completer<int>();
    _pending[id] = completer;
    _send!.send([id, TransferableTypedData.fromList([data]), key, iv, path]);
    return completer.future;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _receive?.close();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('crypto worker stopped'));
    }
    _pending.clear();
    _isolate = null;
    _receive = null;
    _send = null;
    _starting = null;
  }

  static void _entry(SendPort reply) {
    final port = ReceivePort();
    reply.send(port.sendPort);
    port.listen((message) {
      final list = message as List;
      final id = list[0] as int;
      try {
        final data = (list[1] as TransferableTypedData).materialize().asUint8List();
        final out = decryptAes128(data, list[2] as Uint8List, list[3] as Uint8List);
        File(list[4] as String).writeAsBytesSync(out, flush: false);
        reply.send([id, out.length, null]);
      } catch (e) {
        reply.send([id, -1, e.toString()]);
      }
    });
  }
}
