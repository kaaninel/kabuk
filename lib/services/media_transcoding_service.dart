import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

class MediaTranscodingService {
  static final MediaTranscodingService _instance = MediaTranscodingService._internal();
  
  factory MediaTranscodingService() {
    return _instance;
  }

  MediaTranscodingService._internal();

  Future<Uint8List> optimizeImage(Uint8List bytes, {
    int? maxWidth,
    int? maxHeight,
    int quality = 85,
  }) async {
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');

    var processedImage = image;
    
    if (maxWidth != null || maxHeight != null) {
      final scale = _calculateResizeScale(
        image.width, 
        image.height,
        maxWidth ?? image.width,
        maxHeight ?? image.height,
      );
      
      if (scale < 1.0) {
        processedImage = img.copyResize(
          image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round(),
          interpolation: img.Interpolation.linear,
        );
      }
    }

    final extension = '.jpg';
    Uint8List optimizedBytes;
    
    switch (extension) {
      case '.jpg':
      case '.jpeg':
        optimizedBytes = Uint8List.fromList(img.encodeJpg(processedImage, quality: quality));
        break;
      case '.png':
        optimizedBytes = Uint8List.fromList(img.encodePng(processedImage));
        break;
      default:
        optimizedBytes = Uint8List.fromList(img.encodeJpg(processedImage, quality: quality));
    }

    return optimizedBytes;
  }

  double _calculateResizeScale(
    int originalWidth,
    int originalHeight,
    int maxWidth,
    int maxHeight,
  ) {
    var widthScale = maxWidth / originalWidth;
    var heightScale = maxHeight / originalHeight;
    return widthScale < heightScale ? widthScale : heightScale;
  }

  Future<Map<String, dynamic>> getMediaMetadata(String filePath) async {
    final extension = path.extension(filePath).toLowerCase();
    final metadata = <String, dynamic>{
      'filename': path.basename(filePath),
      'extension': extension,
      'size': await File(filePath).length(),
      'lastModified': await File(filePath).lastModified(),
    };

    try {
      if (extension == '.jpg' || extension == '.jpeg' || extension == '.png') {
        final bytes = await File(filePath).readAsBytes();
        final image = img.decodeImage(bytes);
        if (image != null) {
          metadata['width'] = image.width;
          metadata['height'] = image.height;
          metadata['format'] = extension.substring(1);
        }
      }
    } catch (e) {
      // Ignore metadata extraction errors
    }

    return metadata;
  }
}