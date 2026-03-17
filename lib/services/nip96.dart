/// NIP-96: HTTP File Storage Integration.
///
/// Provides file upload and management via NIP-96-compatible servers.
/// Includes NIP-98 HTTP Auth for authenticated uploads.
///
/// References:
/// - NIP-96: https://github.com/nostr-protocol/nips/blob/master/96.md
/// - NIP-98: https://github.com/nostr-protocol/nips/blob/master/98.md
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:kabuk/services/exports.dart' show NostrEvent;
import 'package:kabuk/services/nostr.dart' show NostrEvent;
import 'package:pointycastle/export.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Metadata returned by a NIP-96 server after a successful upload.
class Nip96FileMetadata {
  /// Creates a [Nip96FileMetadata].
  const Nip96FileMetadata({
    required this.url,
    this.mimeType,
    this.size,
    this.sha256,
    this.dimensions,
    this.blurhash,
    this.thumbUrl,
    this.magnetUri,
    this.torrentInfoHash,
    this.originalFilename,
  });

  /// The publicly accessible URL of the uploaded file.
  final String url;

  /// MIME type of the file (e.g. `image/jpeg`, `video/mp4`).
  final String? mimeType;

  /// File size in bytes.
  final int? size;

  /// SHA-256 hash of the file content (hex).
  final String? sha256;

  /// Pixel dimensions for images/videos: (width, height).
  final ({int width, int height})? dimensions;

  /// Blurhash placeholder string for progressive image loading.
  final String? blurhash;

  /// URL of a smaller thumbnail version (for video/large images).
  final String? thumbUrl;

  /// Magnet URI for torrent-based distribution.
  final String? magnetUri;

  /// BitTorrent info hash (hex).
  final String? torrentInfoHash;

  /// Original file name as uploaded.
  final String? originalFilename;

  /// Builds the NIP-92 `imeta` tag for this file, for use in kind 1 notes.
  ///
  /// Returns a tag list like:
  /// `['imeta', 'url <url>', 'm <mime>', 'dim <w>x<h>', 'blurhash <hash>']`
  List<String> toImetaTag() {
    final parts = <String>['imeta', 'url $url'];
    if (mimeType != null) parts.add('m $mimeType');
    if (sha256 != null) parts.add('x $sha256');
    if (size != null) parts.add('size $size');
    if (dimensions != null) {
      parts.add('dim ${dimensions!.width}x${dimensions!.height}');
    }
    if (blurhash != null) parts.add('blurhash $blurhash');
    if (thumbUrl != null) parts.add('thumb $thumbUrl');
    if (magnetUri != null) parts.add('magnet $magnetUri');
    if (torrentInfoHash != null) parts.add('i $torrentInfoHash');
    if (originalFilename != null) parts.add('filename $originalFilename');
    return parts;
  }

  /// Parses from a NIP-92 `imeta` tag.
  ///
  /// The tag format is `['imeta', 'url <url>', 'm <mime>', ...]`.
  static Nip96FileMetadata? fromImetaTag(List<String> tag) {
    if (tag.isEmpty || tag[0] != 'imeta') return null;

    String? url;
    String? mimeType;
    int? size;
    String? sha256;
    ({int width, int height})? dimensions;
    String? blurhash;
    String? thumbUrl;
    String? magnetUri;
    String? torrentInfoHash;
    String? originalFilename;

    for (var i = 1; i < tag.length; i++) {
      final entry = tag[i];
      final spaceIdx = entry.indexOf(' ');
      if (spaceIdx < 0) continue;
      final key = entry.substring(0, spaceIdx);
      final value = entry.substring(spaceIdx + 1);

      switch (key) {
        case 'url':
          url = value;
        case 'm':
          mimeType = value;
        case 'x':
          sha256 = value;
        case 'size':
          size = int.tryParse(value);
        case 'dim':
          final parts = value.split('x');
          if (parts.length == 2) {
            final w = int.tryParse(parts[0]);
            final h = int.tryParse(parts[1]);
            if (w != null && h != null) dimensions = (width: w, height: h);
          }
        case 'blurhash':
          blurhash = value;
        case 'thumb':
          thumbUrl = value;
        case 'magnet':
          magnetUri = value;
        case 'i':
          torrentInfoHash = value;
        case 'filename':
          originalFilename = value;
      }
    }

    if (url == null) return null;
    return Nip96FileMetadata(
      url: url,
      mimeType: mimeType,
      size: size,
      sha256: sha256,
      dimensions: dimensions,
      blurhash: blurhash,
      thumbUrl: thumbUrl,
      magnetUri: magnetUri,
      torrentInfoHash: torrentInfoHash,
      originalFilename: originalFilename,
    );
  }

  @override
  String toString() => 'Nip96FileMetadata(url: $url, mime: $mimeType)';
}

/// Server information returned by `/.well-known/nostr/nip96.json`.
class Nip96ServerInfo {
  /// Creates a [Nip96ServerInfo].
  const Nip96ServerInfo({
    required this.apiUrl,
    this.downloadUrl,
    this.delegated,
    this.contentTypes,
    this.plans,
  });

  /// The upload API endpoint URL.
  final String apiUrl;

  /// Alternative base URL for downloading files. If null, use [apiUrl].
  final String? downloadUrl;

  /// If true, files are served from a CDN / different domain.
  final bool? delegated;

  /// MIME types this server accepts. Empty / null = accepts all.
  final List<String>? contentTypes;

  /// Service plans offered by the server.
  final Map<String, dynamic>? plans;

  /// Parses from JSON.
  factory Nip96ServerInfo.fromJson(Map<String, dynamic> json) =>
      Nip96ServerInfo(
        apiUrl: json['api_url'] as String,
        downloadUrl: json['download_url'] as String?,
        delegated: json['delegated'] as bool?,
        contentTypes: (json['content_types'] as List?)
            ?.map((e) => e as String)
            .toList(),
        plans: json['plans'] as Map<String, dynamic>?,
      );
}

/// Result of a file upload operation.
sealed class Nip96UploadResult {
  const Nip96UploadResult();
}

/// A successful upload.
final class Nip96UploadSuccess extends Nip96UploadResult {
  /// Creates a [Nip96UploadSuccess].
  const Nip96UploadSuccess({required this.metadata, this.processingUrl});

  /// The file metadata for the uploaded file.
  final Nip96FileMetadata metadata;

  /// URL to poll for async processing status, if the server indicated so.
  final String? processingUrl;
}

/// A failed upload.
final class Nip96UploadFailure extends Nip96UploadResult {
  /// Creates a [Nip96UploadFailure].
  const Nip96UploadFailure({required this.message, this.statusCode});

  /// Human-readable error message.
  final String message;

  /// HTTP status code, if available.
  final int? statusCode;
}

// ---------------------------------------------------------------------------
// Service interface
// ---------------------------------------------------------------------------

/// Abstract interface for NIP-96 file storage operations.
abstract interface class Nip96Service {
  /// Fetches server information from `/.well-known/nostr/nip96.json`.
  ///
  /// [serverBaseUrl] is the base URL of the NIP-96 server
  /// (e.g. `https://nostr.build`). Results are cached for [cacheDuration].
  Future<Nip96ServerInfo> fetchServerInfo(
    String serverBaseUrl, {
    Duration cacheDuration = const Duration(hours: 1),
  });

  /// Uploads raw bytes to a NIP-96 server.
  ///
  /// [bytes] is the file content. [mimeType] is required.
  /// [serverBaseUrl] is the target server. [caption] is an optional
  /// description. [sensitiveContent] marks the file as NSFW (NIP-36).
  ///
  /// Returns [Nip96UploadSuccess] on success or [Nip96UploadFailure] on error.
  Future<Nip96UploadResult> uploadBytes(
    Uint8List bytes, {
    required String mimeType,
    required String serverBaseUrl,
    String? filename,
    String? caption,
    bool sensitiveContent = false,

    /// NIP-98 HTTP Auth callback — given the upload URL and HTTP method,
    /// must return a base64-encoded signed kind 27235 event.
    Future<String> Function(String url, String method)? buildNip98Auth,
  });

  /// Deletes a file from a NIP-96 server.
  ///
  /// [fileUrl] is the full URL of the file to delete.
  /// [serverBaseUrl] is the server that hosts the file.
  /// [buildNip98Auth] is required for authenticated deletion.
  Future<bool> deleteFile(
    String fileUrl, {
    required String serverBaseUrl,
    required Future<String> Function(String url, String method) buildNip98Auth,
  });
}

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

/// HTTP-based [Nip96Service] implementation.
class Nip96ServiceImpl implements Nip96Service {
  /// Creates a [Nip96ServiceImpl].
  Nip96ServiceImpl({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Map<String, ({Nip96ServerInfo info, DateTime fetchedAt})> _infoCache =
      {};

  @override
  Future<Nip96ServerInfo> fetchServerInfo(
    String serverBaseUrl, {
    Duration cacheDuration = const Duration(hours: 1),
  }) async {
    final cached = _infoCache[serverBaseUrl];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < cacheDuration) {
      return cached.info;
    }

    final base = serverBaseUrl.endsWith('/')
        ? serverBaseUrl.substring(0, serverBaseUrl.length - 1)
        : serverBaseUrl;
    final uri = Uri.parse('$base/.well-known/nostr/nip96.json');

    final response = await _http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw StateError(
        'NIP-96 server info fetch failed: '
        'HTTP ${response.statusCode} from $uri',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final info = Nip96ServerInfo.fromJson(json);
    _infoCache[serverBaseUrl] = (info: info, fetchedAt: DateTime.now());
    return info;
  }

  @override
  Future<Nip96UploadResult> uploadBytes(
    Uint8List bytes, {
    required String mimeType,
    required String serverBaseUrl,
    String? filename,
    String? caption,
    bool sensitiveContent = false,
    Future<String> Function(String url, String method)? buildNip98Auth,
  }) async {
    final Nip96ServerInfo info;
    try {
      info = await fetchServerInfo(serverBaseUrl);
    } on Object catch (e) {
      return Nip96UploadFailure(message: 'Could not fetch server info: $e');
    }

    final uri = Uri.parse(info.apiUrl);

    final request = http.MultipartRequest('POST', uri);

    // NIP-98 auth header.
    if (buildNip98Auth != null) {
      try {
        final authToken = await buildNip98Auth(info.apiUrl, 'POST');
        request.headers['Authorization'] = 'Nostr $authToken';
      } on Object {
        // Auth is optional on some servers.
      }
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename ?? 'upload',
      ),
    );

    if (caption != null && caption.isNotEmpty) {
      request.fields['caption'] = caption;
    }
    if (sensitiveContent) {
      request.fields['content-type'] = 'true'; // server-specific NSFW flag
    }
    if (mimeType.isNotEmpty) {
      request.fields['media_type'] = mimeType;
    }

    try {
      final streamed = await request.send().timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 202) {
        // Async processing — parse nip94_event if available.
        try {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final processingUrl = json['processing_url'] as String?;
          final meta = _parseUploadResponse(json);
          if (meta != null) {
            return Nip96UploadSuccess(
              metadata: meta,
              processingUrl: processingUrl,
            );
          }
          return Nip96UploadSuccess(
            metadata: Nip96FileMetadata(url: processingUrl ?? ''),
            processingUrl: processingUrl,
          );
        } on Object {
          return Nip96UploadFailure(
            message: 'Processing (async) — poll ${response.body}',
            statusCode: 202,
          );
        }
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        String message = 'HTTP ${response.statusCode}';
        try {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          message = json['message'] as String? ?? message;
        } on Object {
          // Use the HTTP status message if the body can't be parsed.
        }
        return Nip96UploadFailure(
          message: message,
          statusCode: response.statusCode,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final meta = _parseUploadResponse(json);
      if (meta == null) {
        return const Nip96UploadFailure(
          message: 'Server returned success but no file metadata',
        );
      }
      return Nip96UploadSuccess(metadata: meta);
    } on Object catch (e) {
      return Nip96UploadFailure(message: e.toString());
    }
  }

  @override
  Future<bool> deleteFile(
    String fileUrl, {
    required String serverBaseUrl,
    required Future<String> Function(String url, String method) buildNip98Auth,
  }) async {
    try {
      final info = await fetchServerInfo(serverBaseUrl);
      final uri = Uri.parse('${info.apiUrl}/$fileUrl');

      final authToken = await buildNip98Auth(uri.toString(), 'DELETE');
      final response = await _http
          .delete(uri, headers: {'Authorization': 'Nostr $authToken'})
          .timeout(const Duration(seconds: 15));

      return response.statusCode == 200 || response.statusCode == 204;
    } on Object {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  Nip96FileMetadata? _parseUploadResponse(Map<String, dynamic> json) {
    // NIP-96 response format wraps metadata in a `nip94_event` field.
    final nip94 = json['nip94_event'] as Map<String, dynamic>?;
    final tags = nip94 != null
        ? (nip94['tags'] as List?)
                  ?.map((t) => (t as List).map((e) => e.toString()).toList())
                  .toList() ??
              []
        : (json['tags'] as List?)
                  ?.map((t) => (t as List).map((e) => e.toString()).toList())
                  .toList() ??
              [];

    String? url;
    String? mimeType;
    int? size;
    String? sha256;
    ({int width, int height})? dimensions;
    String? blurhash;
    String? thumbUrl;
    String? magnetUri;
    String? torrentInfoHash;

    for (final tag in tags) {
      if (tag.length < 2) continue;
      switch (tag[0]) {
        case 'url':
          url = tag[1];
        case 'm':
          mimeType = tag[1];
        case 'size':
          size = int.tryParse(tag[1]);
        case 'x' || 'ox':
          sha256 = tag[1];
        case 'dim':
          final parts = tag[1].split('x');
          if (parts.length == 2) {
            final w = int.tryParse(parts[0]);
            final h = int.tryParse(parts[1]);
            if (w != null && h != null) dimensions = (width: w, height: h);
          }
        case 'blurhash':
          blurhash = tag[1];
        case 'thumb':
          thumbUrl = tag[1];
        case 'magnet':
          magnetUri = tag[1];
        case 'i':
          torrentInfoHash = tag[1];
      }
    }

    // Fallback: some servers return url at the top level.
    url ??= json['url'] as String?;

    if (url == null || url.isEmpty) return null;

    return Nip96FileMetadata(
      url: url,
      mimeType: mimeType,
      size: size,
      sha256: sha256,
      dimensions: dimensions,
      blurhash: blurhash,
      thumbUrl: thumbUrl,
      magnetUri: magnetUri,
      torrentInfoHash: torrentInfoHash,
    );
  }
}

// ---------------------------------------------------------------------------
// NIP-98: HTTP Auth helper
// ---------------------------------------------------------------------------

/// Builds a NIP-98 HTTP Auth event payload (base64 of JSON-encoded kind 27235).
///
/// [url] is the request URL. [method] is the HTTP method (uppercase).
/// [payload] is the optional request body bytes (used for payload hash).
/// [signEvent] is a callback that signs the event and returns the full
/// JSON-encoded [NostrEvent] string.
///
/// Returns a base64-encoded string to use in `Authorization: Nostr <token>`.
Future<String> buildNip98AuthToken({
  required String url,
  required String method,
  Uint8List? payload,
  required Future<String> Function(Map<String, dynamic> event) signEvent,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final tags = <List<String>>[
    ['u', url],
    ['method', method.toUpperCase()],
  ];

  if (payload != null && payload.isNotEmpty) {
    // SHA-256 hash of the payload, hex-encoded.
    // Importers provide this if they want body integrity protection.
    // We include the tag slot but leave hashing to the caller.
    final sha256Hex = _sha256Hex(payload);
    tags.add(['payload', sha256Hex]);
  }

  final unsignedEvent = {
    'kind': 27235,
    'created_at': now,
    'tags': tags,
    'content': '',
  };

  final signedJson = await signEvent(unsignedEvent);
  final bytes = utf8.encode(signedJson);
  return base64.encode(bytes);
}

String _sha256Hex(Uint8List bytes) {
  final digest = SHA256Digest();
  final hash = digest.process(bytes);
  return hash
      .fold(
        StringBuffer(),
        (buf, b) => buf..write(b.toRadixString(16).padLeft(2, '0')),
      )
      .toString();
}
