import 'package:equatable/equatable.dart';
import 'package:http/http.dart' as http;

class ProgressResult extends Equatable {
  const ProgressResult({
    required this.count,
    required this.total,
    this.response,
  });

  const ProgressResult.empty() : this(count: 0, total: 0, response: null);

  bool get isEmpty => this == const ProgressResult.empty();

  /// The number of bytes uploaded.
  final int count;

  /// The total number of bytes to upload.
  final int total;

  /// The response from the server.
  final http.Response? response;

  /// The progress of the upload as a percentage.
  double get progress => count / total;

  ProgressResult copyWith({
    int? count,
    int? total,
    http.Response? response,
  }) {
    return ProgressResult(
      count: count ?? this.count,
      total: total ?? this.total,
      response: response ?? this.response,
    );
  }

  @override
  List<Object?> get props => [count, total, response];
}
