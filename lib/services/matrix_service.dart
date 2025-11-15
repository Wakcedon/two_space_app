// Placeholder MatrixService shim.
//
// The project currently uses `ChatMatrixService` (REST) as the Matrix
// backend adapter. The previous `MatrixService` referenced `matrix_sdk` and
// caused unresolved native dependencies during initial migration. Keep this
// shim so other files that import `matrix_service.dart` continue to build.
// Replace with a full Matrix SDK integration later (when libolm and native
// bindings are added).

class MatrixService {
  MatrixService._();
  static final instance = MatrixService._();

  Never implemented() => throw UnimplementedError('Use ChatMatrixService for REST-based Matrix access or implement MatrixService with matrix_sdk later.');
}
