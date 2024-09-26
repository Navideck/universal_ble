class ConnectionException implements Exception {
  String message;
  ConnectionException([this.message = "Operation Canceled"]);

  @override
  String toString() => message;
}
