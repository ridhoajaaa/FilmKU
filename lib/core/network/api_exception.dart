import 'dart:io';

/// Exception thrown by the API layer with a user-friendly message.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.endPoint});

  final String message;
  final int? statusCode;
  final String? endPoint;

  /// Wraps any error into an [ApiException] with a readable message.
  factory ApiException.fromError(Object error) {
    if (error is ApiException) return error;
    if (error is SocketException) {
      return const ApiException(
        'No internet connection. Check your network and try again.',
      );
    }
    return ApiException(error.toString());
  }

  @override
  String toString() => message;
}
