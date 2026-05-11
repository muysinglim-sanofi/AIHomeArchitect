import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GenerationService {
  late final Dio _dio;

  GenerationService() {
    _dio = Dio(BaseOptions(
      baseUrl: dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
    ));
  }

  /// Calls FastAPI /generate and returns the result map:
  /// { after_image_url, thumbnail_url, ai_message }
  Future<Map<String, dynamic>> generate({
    required String sessionId,
    required String prompt,
    required String beforeImageUrl,
    required String styleLabel,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/generate',
      data: FormData.fromMap({
        'session_id': sessionId,
        'prompt': prompt,
        'before_image_url': beforeImageUrl,
        'style_label': styleLabel,
      }),
    );
    return res.data!;
  }
}
