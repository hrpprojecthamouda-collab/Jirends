/// InviteRepository — join-by-link.
///
/// `event_invites` has RLS enabled and NO policies, so none of this touches the
/// table directly: every call is a SECURITY DEFINER RPC that re-implements its
/// own authorization. A readable token table would let anyone who could SELECT
/// it join every event in the project.
///
/// VISIBILITY: a token grants MEMBERSHIP, and sight follows from membership as
/// it always has. `peek_invite` deliberately returns a title and a head-count
/// and nothing else — not the description, not the roster, and not even the
/// event id, so a caller who has not joined has nothing to probe with.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';

/// What an invite looks like before you accept it.
class InvitePreview {
  const InvitePreview({
    required this.eventTitle,
    required this.startsAt,
    required this.organizerLabel,
    required this.memberCount,
    required this.alreadyMember,
  });

  final String eventTitle;
  final DateTime? startsAt;
  final String organizerLabel;
  final int memberCount;

  /// You are already in this event — the join screen offers "Open" rather than
  /// "Join", and re-redeeming is a no-op server-side either way.
  final bool alreadyMember;

  static InvitePreview fromRow(Map<String, dynamic> r) => InvitePreview(
        eventTitle: (r['event_title'] as String?) ?? '',
        startsAt: r['event_starts_at'] == null
            ? null
            : DateTime.parse(r['event_starts_at'] as String),
        organizerLabel: (r['organizer_label'] as String?) ?? '',
        memberCount: (r['member_count'] as num?)?.toInt() ?? 0,
        alreadyMember: (r['already_member'] as bool?) ?? false,
      );
}

class InviteRepository {
  InviteRepository(this._client);
  final SupabaseClient _client;

  /// Mint a link for an event. Organizers only (enforced in the RPC).
  Future<String> createInvite(String eventId) async {
    try {
      final token =
          await _client.rpc('create_event_invite', params: {'p_event': eventId});
      return token as String;
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// What is behind this token, or null if it is unknown, expired or revoked.
  ///
  /// Those three cases are deliberately indistinguishable: the RPC returns no
  /// rows for all of them, so the link cannot be used as an oracle for which
  /// tokens are real.
  Future<InvitePreview?> peek(String token) async {
    try {
      final rows = await _client.rpc('peek_invite', params: {'p_token': token});
      final list = (rows as List).cast<Map<String, dynamic>>();
      return list.isEmpty ? null : InvitePreview.fromRow(list.first);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Redeem the token and return the event id. Idempotent: redeeming a link you
  /// have already used returns the same event instead of failing.
  Future<String> join(String token) async {
    try {
      final id = await _client
          .rpc('join_event_with_token', params: {'p_token': token});
      return id as String;
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> revoke(String token) async {
    try {
      await _client.rpc('revoke_event_invite', params: {'p_token': token});
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final inviteRepositoryProvider = Provider<InviteRepository>((ref) {
  return InviteRepository(ref.watch(supabaseClientProvider));
});
