import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ProcessedChatImage {
  const ProcessedChatImage({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

class ImagePreparationException implements Exception {
  const ImagePreparationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ImageProcessingService {
  static const maxUploadBytes = 5 * 1024 * 1024;
  static const encryptedImageOverheadBytes = 28;
  static const maxWidth = 1280;

  ProcessedChatImage process(Uint8List sourceBytes) {
    final contentType = _detectContentType(sourceBytes);
    if (contentType == null) {
      throw const ImagePreparationException(
        'Choose a JPG, JPEG, PNG, or WebP image.',
      );
    }

    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const ImagePreparationException(
        'This image could not be opened. Try another photo.',
      );
    }

    final oriented = img.bakeOrientation(decoded);
    final resized = oriented.width > maxWidth
        ? img.copyResize(oriented, width: maxWidth)
        : oriented;
    final compressed = Uint8List.fromList(img.encodeJpg(resized, quality: 80));
    if (compressed.lengthInBytes + encryptedImageOverheadBytes >
        maxUploadBytes) {
      throw const ImagePreparationException(
        'This image is still larger than 5 MB after compression. Choose a smaller image.',
      );
    }

    return ProcessedChatImage(bytes: compressed, contentType: 'image/jpeg');
  }

  String? _detectContentType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }
}
