/// EventPhase — a row of public.event_type_phases: one phase in a type's linear
/// workflow. This is app CONFIG (read-only); the client renders the workflow
/// from these rows and never hardcodes the phase list.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'event_phase.freezed.dart';
part 'event_phase.g.dart';

@freezed
abstract class EventPhase with _$EventPhase {
  const factory EventPhase({
    required String key,
    required String label,
    required int position,
    required bool isTerminal,
  }) = _EventPhase;

  factory EventPhase.fromJson(Map<String, dynamic> json) =>
      _$EventPhaseFromJson(json);
}
