import 'package:equatable/equatable.dart';

/// Base class for all domain and infrastructure failures in AI Sub Mini.
abstract class Failure extends Equatable {
  final String message;
  final String? details;

  const Failure(this.message, [this.details]);

  @override
  List<Object?> get props => [message, details];

  @override
  String toString() => details != null ? '$message: $details' : message;
}

class StorageFailure extends Failure {
  const StorageFailure(super.message, [super.details]);
}

class ModelInferenceFailure extends Failure {
  const ModelInferenceFailure(super.message, [super.details]);
}

class MediaExtractionFailure extends Failure {
  const MediaExtractionFailure(super.message, [super.details]);
}

class TranslationFailure extends Failure {
  const TranslationFailure(super.message, [super.details]);
}

class LanguageError extends Failure {
  const LanguageError(super.message, [super.details]);
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message, [super.details]);
}
