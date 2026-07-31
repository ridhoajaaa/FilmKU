import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_constants.dart';
import '../constants/app_constants.dart';
import '../local/settings_service.dart';
import 'api_exception.dart';

/// Central HTTP client for TMDB. Reads the API key at request time from
/// [SettingsService] so the app works without a rebuild after entering a key
/// (the build-time dart-define acts as a default fallback).
class ApiClient {
  ApiClient({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: ApiConstants.apiTimeoutSeconds),
        receiveTimeout: const Duration(seconds: ApiConstants.apiTimeoutSeconds),
        headers: {'Accept': 'application/json'},
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final key = _resolveApiKey();
          if (key.isNotEmpty) {
            options.queryParameters['api_key'] = key;
          }
          handler.next(options);
        },
      ),
    );
    return dio;
  }

  /// Runtime setting wins; falls back to the build-time dart-define.
  static String _resolveApiKey() {
    final fromSettings = SettingsService.instance.apiKey;
    if (fromSettings.isNotEmpty) return fromSettings;
    return AppConstants.tmdbApiKey;
  }

  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    try {
      final response =
          await _dio.get<dynamic>(path, queryParameters: queryParameters);
      return response.data;
    } on DioException catch (e) {
      throw ApiException(
        _messageFor(e),
        statusCode: e.response?.statusCode,
        endPoint: path,
      );
    } catch (e) {
      throw ApiException.fromError(e);
    }
  }

  String _messageFor(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401) {
      return 'TMDB API key is missing or invalid. Add it in Settings.';
    }
    if (code == 404) return 'Resource not found (404).';
    if (code == 429) return 'Rate limit reached. Try again in a moment.';
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Request timed out. Try again.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'No internet connection. Check your network.';
    }
    return 'Something went wrong. Please try again.';
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
