/// Результат операции с возможной ошибкой
class Result<T> {
  final T? data;
  final String? error;
  final bool success;

  Result._({this.data, this.error, required this.success});

  factory Result.ok(T? data) {
    return Result._(data: data, success: true);
  }

  factory Result.err(String error) {
    return Result._(error: error, success: false);
  }
}