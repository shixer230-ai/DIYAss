import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 用 ML Kit 本地中文 OCR 读一张图片，返回识别出的全部文字
/// 完全离线，中文模型已 bundled 进 APK（国产机无谷歌服务也能用）
Future<String> ocrImagePath(String path) async {
  final inputImage = InputImage.fromFilePath(path);
  final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
  try {
    final RecognizedText result = await recognizer.processImage(inputImage);
    return result.text;
  } finally {
    await recognizer.close();
  }
}
