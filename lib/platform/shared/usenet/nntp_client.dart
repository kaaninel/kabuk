library;

import 'dart:async';
import 'dart:convert' show ascii, utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// A parsed NNTP response (single‑line or multi‑line).
@immutable
class NntpResponse {
  /// The 3‑digit status code.
  final int code;

  /// The human‑readable message on the status line.
  final String message;

  /// For multi‑line responses the data lines (dot‑unstuffed).
  /// `null` when the response is single‑line.
  final List<String>? dataLines;

  /// Creates an [NntpResponse].
  const NntpResponse({
    required this.code,
    required this.message,
    this.dataLines,
  });

  /// Whether the response indicates success.
  ///
  /// NNTP success codes span several ranges depending on command:
  /// 1xx (informational), 2xx (command OK), 3xx (continue / send data).
  bool get isSuccess => code >= 100 && code < 400;

  /// `true` when the server requires authentication (480).
  bool get isAuthRequired => code == 480;

  /// `true` when the requested article was not found (430).
  bool get isArticleNotFound => code == 430;

  @override
  String toString() => 'NntpResponse($code $message)';
}

/// Parsed result of the CAPABILITIES command.
@immutable
class NntpCapabilities {
  /// The raw capability strings returned by the server.
  final Set<String> capabilities;

  /// Creates an [NntpCapabilities].
  const NntpCapabilities({required this.capabilities});

  /// Whether the server advertises STARTTLS.
  bool get supportsStartTls =>
      capabilities.any((c) => c.toUpperCase().startsWith('STARTTLS'));

  /// Whether the server advertises AUTHINFO.
  bool get supportsAuthInfo =>
      capabilities.any((c) => c.toUpperCase().startsWith('AUTHINFO'));

  /// Whether the server advertises OVER or XOVER.
  bool get supportsOverview => capabilities.any((c) {
        final upper = c.toUpperCase();
        return upper.startsWith('OVER') || upper.startsWith('XOVER');
      });

  @override
  String toString() => 'NntpCapabilities(${capabilities.length} entries)';
}

/// Error type thrown (or returned) for NNTP‑level failures.
@immutable
class NntpException {
  /// The NNTP status code, if one was received.
  final int? code;

  /// A human‑readable description of the error.
  final String message;

  /// Creates an [NntpException].
  const NntpException({this.code, required this.message});

  @override
  String toString() =>
      code != null ? 'NntpException($code: $message)' : 'NntpException($message)';
}

// ---------------------------------------------------------------------------
// NNTP Client
// ---------------------------------------------------------------------------

/// A native Dart NNTP / NNTPS client implementing the core of RFC 3977.
///
/// Example:
/// ```dart
/// final client = NntpClient(host: 'news.example.com', port: 563);
/// await client.connect();
/// await client.authenticate('user', 'pass');
/// final body = await client.body('some-id@example.com');
/// await client.quit();
/// ```
class NntpClient {
  /// Creates an [NntpClient] targeting [host]:[port].
  ///
  /// When [ssl] is `true` (the default) the connection is established over TLS
  /// using [SecureSocket] — the standard approach for NNTPS on port 563.
  NntpClient({
    required this.host,
    required this.port,
    this.ssl = true,
  });

  /// The server hostname.
  final String host;

  /// The server port (typically 563 for NNTPS).
  final int port;

  /// Whether to connect over TLS.
  final bool ssl;

  /// Connection timeout applied to the initial socket handshake.
  static const Duration connectionTimeout = Duration(seconds: 30);

  /// Read timeout for waiting on a single command response.
  static const Duration readTimeout = Duration(seconds: 60);

  // -- internal state -------------------------------------------------------

  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;

  /// Internal byte buffer for accumulating data from the socket.
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  /// Completer that is active while we are waiting for a response.
  Completer<void>? _dataReady;

  /// Whether the underlying socket is connected and open.
  bool _connected = false;

  /// Whether we are currently waiting for a response.
  bool _busy = false;

  /// Whether the socket connection is active.
  bool get isConnected => _connected;

  // -- public API -----------------------------------------------------------

  /// Opens the connection and reads the server greeting.
  ///
  /// Throws [NntpException] if the connection fails or the greeting
  /// indicates a service‑unavailable state.
  Future<void> connect() async {
    try {
      if (ssl) {
        _socket = await SecureSocket.connect(
          host,
          port,
          timeout: connectionTimeout,
        );
      } else {
        _socket = await Socket.connect(
          host,
          port,
          timeout: connectionTimeout,
        );
      }
    } on SocketException catch (e) {
      throw NntpException(message: 'Connection failed: $e');
    }

    _connected = true;
    _listenToSocket();

    // Read the server greeting.
    final greeting = await _readResponse();
    if (greeting.code == 502) {
      _connected = false;
      await _closeSocket();
      throw NntpException(
        code: greeting.code,
        message: 'Service not available: ${greeting.message}',
      );
    }
  }

  /// Authenticates with the server using AUTHINFO USER / PASS.
  ///
  /// Returns the final [NntpResponse] from the PASS step.
  Future<NntpResponse> authenticate(String username, String password) async {
    _assertConnected();
    final userResp = await _command('AUTHINFO USER $username');
    // 381 = password required
    if (userResp.code != 381) {
      if (userResp.isSuccess) return userResp;
      throw NntpException(
        code: userResp.code,
        message: 'AUTHINFO USER failed: ${userResp.message}',
      );
    }
    final passResp = await _command('AUTHINFO PASS $password');
    if (!passResp.isSuccess) {
      throw NntpException(
        code: passResp.code,
        message: 'AUTHINFO PASS failed: ${passResp.message}',
      );
    }
    return passResp;
  }

  /// Selects a newsgroup via the GROUP command.
  Future<NntpResponse> group(String groupName) async {
    _assertConnected();
    final resp = await _command('GROUP $groupName');
    if (resp.code == 411) {
      throw NntpException(code: 411, message: 'No such group: $groupName');
    }
    return resp;
  }

  /// Retrieves the raw body of an article as bytes.
  ///
  /// The [messageId] is automatically wrapped in angle brackets if it does not
  /// already contain them.
  ///
  /// This is the most performance‑critical path: the body may contain
  /// yEnc‑encoded binary data, so it is returned as a [Uint8List] without any
  /// character‑set decoding.
  Future<Uint8List> body(String messageId) async {
    _assertConnected();
    final id = _bracketId(messageId);
    await _sendLine('BODY $id');
    final statusLine = await _readStatusLine();
    if (statusLine.code == 430) {
      throw NntpException(code: 430, message: 'Article not found: $id');
    }
    if (statusLine.code == 480) {
      throw const NntpException(code: 480, message: 'Authentication required');
    }
    if (statusLine.code != 222) {
      throw NntpException(
        code: statusLine.code,
        message: 'BODY failed: ${statusLine.message}',
      );
    }
    // Read the raw multi‑line body as bytes (no UTF‑8 decoding).
    return _readMultiLineBytes();
  }

  /// Retrieves the article headers via the HEAD command.
  Future<NntpResponse> head(String messageId) async {
    _assertConnected();
    return _multiLineCommand('HEAD ${_bracketId(messageId)}');
  }

  /// Checks whether an article exists via the STAT command.
  Future<NntpResponse> stat(String messageId) async {
    _assertConnected();
    return _command('STAT ${_bracketId(messageId)}');
  }

  /// Retrieves the full article (headers + body) via the ARTICLE command.
  Future<NntpResponse> article(String messageId) async {
    _assertConnected();
    return _multiLineCommand('ARTICLE ${_bracketId(messageId)}');
  }

  /// Queries the server's capabilities (RFC 3977 §5.2).
  Future<NntpCapabilities> capabilities() async {
    _assertConnected();
    final resp = await _multiLineCommand('CAPABILITIES');
    final caps = resp.dataLines ?? const [];
    return NntpCapabilities(capabilities: caps.toSet());
  }

  /// Sends the QUIT command and closes the connection.
  Future<void> quit() async {
    if (!_connected) return;
    try {
      await _command('QUIT');
    } catch (_) {
      // Best‑effort: we're closing anyway.
    }
    await _closeSocket();
    _connected = false;
  }

  /// Releases all resources held by this client.
  ///
  /// Safe to call multiple times. Prefer [quit] for a clean shutdown.
  void dispose() {
    _connected = false;
    _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _buffer.clear();
    _completeDataReady();
  }

  // -- internal helpers -----------------------------------------------------

  /// Wraps [id] in angle brackets if not already present.
  String _bracketId(String id) {
    if (id.startsWith('<') && id.endsWith('>')) return id;
    return '<$id>';
  }

  /// Throws [NntpException] when the client is not connected.
  void _assertConnected() {
    if (!_connected) {
      throw const NntpException(message: 'Not connected');
    }
  }

  /// Starts listening on the socket and feeding bytes into [_buffer].
  void _listenToSocket() {
    _subscription = _socket!.listen(
      (Uint8List data) {
        _buffer.add(data);
        _completeDataReady();
      },
      onError: (Object error) {
        _connected = false;
        _failDataReady(
          NntpException(message: 'Socket error: $error'),
        );
      },
      onDone: () {
        _connected = false;
        _completeDataReady();
      },
      cancelOnError: false,
    );
  }

  void _completeDataReady() {
    if (_dataReady != null && !_dataReady!.isCompleted) {
      _dataReady!.complete();
    }
  }

  void _failDataReady(NntpException exception) {
    if (_dataReady != null && !_dataReady!.isCompleted) {
      _dataReady!.completeError(exception);
    }
  }

  /// Waits until more data arrives in [_buffer] or throws on timeout.
  Future<void> _waitForData() async {
    _dataReady = Completer<void>();
    try {
      await _dataReady!.future.timeout(readTimeout, onTimeout: () {
        throw const NntpException(message: 'Read timeout');
      });
    } finally {
      _dataReady = null;
    }
  }

  /// Sends a single line terminated by `\r\n`.
  Future<void> _sendLine(String line) async {
    if (_socket == null) {
      throw const NntpException(message: 'Socket is null');
    }
    _socket!.add(ascii.encode('$line\r\n'));
    await _socket!.flush();
  }

  // -- response reading -----------------------------------------------------

  /// ASCII code for `\r`.
  static const int _cr = 13;

  /// ASCII code for `\n`.
  static const int _lf = 10;

  /// ASCII code for `.`.
  static const int _dot = 46;

  /// Reads a single CRLF‑terminated line from the buffer as a [String].
  ///
  /// Blocks (with timeout) until a complete line is available.
  Future<String> _readLine() async {
    while (true) {
      final bytes = _buffer.takeBytes();
      final crlfIndex = _indexOfCrlf(bytes);
      if (crlfIndex != -1) {
        final line = utf8.decode(bytes.sublist(0, crlfIndex), allowMalformed: true);
        // Put remaining bytes back.
        if (crlfIndex + 2 < bytes.length) {
          _buffer.add(bytes.sublist(crlfIndex + 2));
        }
        return line;
      }
      // No complete line yet — put bytes back and wait.
      _buffer.add(bytes);
      await _waitForData();
    }
  }

  /// Reads the first status line and parses code + message.
  Future<NntpResponse> _readStatusLine() async {
    final line = await _readLine();
    return _parseStatusLine(line);
  }

  /// Reads a full single‑line response (status line only).
  Future<NntpResponse> _readResponse() async {
    return _readStatusLine();
  }

  /// Reads multi‑line data following a status line.
  ///
  /// The terminating dot line (`.`) is consumed but not included.
  /// Dot‑stuffed lines (leading `..`) are unstuffed.
  Future<List<String>> _readMultiLineData() async {
    final lines = <String>[];
    while (true) {
      final line = await _readLine();
      if (line == '.') break;
      // Dot‑unstuffing: if a line starts with '..' replace with '.'.
      lines.add(line.startsWith('..') ? line.substring(1) : line);
    }
    return lines;
  }

  /// Reads the raw multi‑line body as bytes, preserving binary content.
  ///
  /// Scans for the terminating sequence `\r\n.\r\n` at the byte level
  /// and performs dot‑unstuffing on the raw bytes.
  Future<Uint8List> _readMultiLineBytes() async {
    // We accumulate all body bytes here.
    final body = BytesBuilder(copy: false);

    // We need to scan for the terminating `\r\n.\r\n`.  Because the
    // terminator may straddle socket reads we keep a rolling window
    // of trailing bytes.

    while (true) {
      // Drain whatever is currently in the buffer.
      var chunk = _buffer.takeBytes();
      if (chunk.isEmpty) {
        await _waitForData();
        chunk = _buffer.takeBytes();
      }

      // Search for the terminator within the accumulated data.
      body.add(chunk);
      final accumulated = body.takeBytes();
      final termIndex = _indexOfTerminator(accumulated);

      if (termIndex == -2) {
        // Empty body: terminator was `.\r\n` at offset 0.
        final afterTerm = 3; // skip `.\r\n`
        if (afterTerm < accumulated.length) {
          _buffer.add(accumulated.sublist(afterTerm));
        }
        return Uint8List(0);
      }

      if (termIndex >= 0) {
        // Everything before termIndex is body data.
        final raw = accumulated.sublist(0, termIndex);
        // Anything after the terminator goes back into the socket buffer.
        // The terminator is \r\n.\r\n (5 bytes starting at termIndex).
        final afterTerm = termIndex + 5; // skip full `\r\n.\r\n`
        if (afterTerm < accumulated.length) {
          _buffer.add(accumulated.sublist(afterTerm));
        }
        return _dotUnstuffBytes(raw);
      }

      // No terminator yet — put data back and keep reading.
      body.add(accumulated);
    }
  }

  /// Finds the index of the terminating `\r\n.\r\n` sequence.
  ///
  /// Returns the index of the `\r\n` **before** the dot, or -1 if not found.
  /// After the status line the first `\r\n` is at the start of body data,
  /// so the terminator is `\r\n.\r\n` where `\r\n` precedes the lone dot.
  int _indexOfTerminator(Uint8List data) {
    // We look for the pattern: \r\n.\r\n
    for (var i = 0; i <= data.length - 5; i++) {
      if (data[i] == _cr &&
          data[i + 1] == _lf &&
          data[i + 2] == _dot &&
          data[i + 3] == _cr &&
          data[i + 4] == _lf) {
        return i;
      }
    }
    // Also handle the case where the body is empty and the terminator is
    // the very first thing: `.\r\n` at offset 0.
    if (data.length >= 3 &&
        data[0] == _dot &&
        data[1] == _cr &&
        data[2] == _lf) {
      return -2; // sentinel: empty body
    }
    return -1;
  }

  /// Performs dot‑unstuffing on raw bytes.
  ///
  /// Any sequence `\r\n..` is replaced with `\r\n.`.
  Uint8List _dotUnstuffBytes(Uint8List data) {
    if (data.isEmpty) return data;

    final out = BytesBuilder(copy: false);
    var i = 0;
    while (i < data.length) {
      if (i + 3 < data.length &&
          data[i] == _cr &&
          data[i + 1] == _lf &&
          data[i + 2] == _dot &&
          data[i + 3] == _dot) {
        // Write \r\n. and skip the doubled dot.
        out.add(const [_cr, _lf, _dot]);
        i += 4;
      } else {
        out.addByte(data[i]);
        i++;
      }
    }
    // Handle leading dot‑stuffed line (first line has no preceding \r\n).
    final result = out.takeBytes();
    if (result.length >= 2 && result[0] == _dot && result[1] == _dot) {
      return Uint8List.fromList([...result.sublist(1)]);
    }
    return result;
  }

  /// Sends [command] and reads the status line.
  Future<NntpResponse> _command(String command) async {
    await _acquireLock();
    try {
      await _sendLine(command);
      return await _readResponse();
    } finally {
      _releaseLock();
    }
  }

  /// Sends [command] and reads a multi‑line response.
  Future<NntpResponse> _multiLineCommand(String command) async {
    await _acquireLock();
    try {
      await _sendLine(command);
      final status = await _readStatusLine();
      if (!status.isSuccess) return status;
      final data = await _readMultiLineData();
      return NntpResponse(
        code: status.code,
        message: status.message,
        dataLines: data,
      );
    } finally {
      _releaseLock();
    }
  }

  // -- locking (one command at a time) --------------------------------------

  Completer<void>? _lock;

  Future<void> _acquireLock() async {
    while (_busy) {
      _lock ??= Completer<void>();
      await _lock!.future;
    }
    _busy = true;
  }

  void _releaseLock() {
    _busy = false;
    if (_lock != null && !_lock!.isCompleted) {
      _lock!.complete();
    }
    _lock = null;
  }

  // -- socket helpers -------------------------------------------------------

  /// Finds the first `\r\n` in [data] and returns its index, or -1.
  int _indexOfCrlf(Uint8List data) {
    for (var i = 0; i < data.length - 1; i++) {
      if (data[i] == _cr && data[i + 1] == _lf) return i;
    }
    return -1;
  }

  /// Parses a status line of the form `"code message..."`.
  NntpResponse _parseStatusLine(String line) {
    if (line.length < 3) {
      throw NntpException(message: 'Invalid status line: $line');
    }
    final code = int.tryParse(line.substring(0, 3));
    if (code == null) {
      throw NntpException(message: 'Invalid status code in line: $line');
    }
    final message = line.length > 4 ? line.substring(4) : '';
    return NntpResponse(code: code, message: message);
  }

  Future<void> _closeSocket() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _buffer.clear();
  }
}
