import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kabuk/services/media_transcoding_service.dart';

void main() {
  group('MediaTranscodingService', () {
    late MediaTranscodingService transcodingService;
    late Uint8List testImageBytes;

    setUp(() {
      transcodingService = MediaTranscodingService();
      
      // Create a test image
      final image = img.Image(width: 100, height: 100);
      // Fill with a red color
      for (var i = 0; i < image.width; i++) {
        for (var j = 0; j < image.height; j++) {
          image.setPixel(i, j, img.ColorRgb8(255, 0, 0));
        }
      }
      testImageBytes = Uint8List.fromList(img.encodeJpg(image));
    });

    test('optimizes image with max dimensions', () async {
      final optimized = await transcodingService.optimizeImage(
        testImageBytes,
        maxWidth: 50,
        maxHeight: 50,
      );

      final decodedOptimized = img.decodeImage(optimized);
      expect(decodedOptimized?.width, lessThanOrEqualTo(50));
      expect(decodedOptimized?.height, lessThanOrEqualTo(50));
    });

    test('maintains aspect ratio during resize', () async {
      final optimized = await transcodingService.optimizeImage(
        testImageBytes,
        maxWidth: 50,
        maxHeight: 50,
      );

      final decodedOptimized = img.decodeImage(optimized);
      expect(decodedOptimized?.width, equals(decodedOptimized?.height));
    });

    test('extracts image metadata correctly', () async {
      // Create a temporary file
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/test_image.jpg');
      await tempFile.writeAsBytes(testImageBytes);

      final metadata = await transcodingService.getMediaMetadata(tempFile.path);
      
      expect(metadata['width'], equals(100));
      expect(metadata['height'], equals(100));
      expect(metadata['format'], equals('jpg'));
      expect(metadata['extension'], equals('.jpg'));

      // Cleanup
      await tempFile.delete();
    });

    test('handles invalid image gracefully', () async {
      final invalidBytes = Uint8List.fromList([1, 2, 3, 4]);
      
      expect(
        () => transcodingService.optimizeImage(invalidBytes),
        throwsException,
      );
    });
  });
}