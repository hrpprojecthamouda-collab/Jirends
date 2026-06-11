/// PollRepository — polls for one event: list/create/vote/close. RLS scopes
/// everything to event members; tallies come from the poll_tallies RPC (so open
/// polls show counts without leaking who voted), and the close/reopen RPCs
/// resolve the winner server-side. No client visibility logic.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'poll.dart';
import 'poll_option.dart';
import 'poll_vote.dart';

/// Everything the UI needs to render one poll.
class PollView {
  const PollView({
    required this.poll,
    required this.options,
    required this.tallies,
    required this.myOptionId,
    required this.closedVotes,
  });

  final Poll poll;
  final List<PollOption> options;
  final Map<String, int> tallies; // optionId -> votes
  final String? myOptionId; // the caller's chosen option, if any
  final List<PollVote> closedVotes; // who-voted-what; only after close

  int get totalVotes => tallies.values.fold(0, (a, b) => a + b);
  int votesFor(String optionId) => tallies[optionId] ?? 0;
}

class PollRepository {
  PollRepository(this._client);
  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  Future<List<PollView>> fetchPolls(String eventId) async {
    final uid = _uid;
    try {
      final pollRows = await _client
          .from('polls')
          .select()
          .eq('event_id', eventId)
          .order('created_at', ascending: false);
      final polls = pollRows.map(Poll.fromJson).toList();
      if (polls.isEmpty) return const [];

      final optRows = await _client
          .from('poll_options')
          .select()
          .eq('event_id', eventId)
          .order('position', ascending: true);
      final options = optRows.map(PollOption.fromJson).toList();

      // My own votes across this event's polls (RLS returns own rows always).
      final myVoteRows = uid == null
          ? const <Map<String, dynamic>>[]
          : await _client
              .from('poll_votes')
              .select('poll_id, option_id')
              .eq('event_id', eventId)
              .eq('user_id', uid);
      final myOptionByPoll = <String, String>{
        for (final r in myVoteRows)
          r['poll_id'] as String: r['option_id'] as String,
      };

      // All tallies for the event in one round-trip (member-gated RPC).
      final tallyRows = await _client
          .rpc('poll_tallies_for_event', params: {'p_event': eventId});
      final talliesByPoll = <String, Map<String, int>>{};
      for (final r in (tallyRows as List)) {
        final row = r as Map;
        (talliesByPoll[row['poll_id'] as String] ??= {})[
            row['option_id'] as String] = (row['votes'] as num).toInt();
      }

      final views = <PollView>[];
      for (final poll in polls) {
        final opts = options.where((o) => o.pollId == poll.id).toList();
        final tallies = talliesByPoll[poll.id] ?? const <String, int>{};
        // After close, fetch the full who-voted-what breakdown (RLS allows it).
        List<PollVote> closedVotes = const [];
        if (poll.isClosed) {
          final vrows = await _client
              .from('poll_votes')
              .select('id, poll_id, option_id, user_id, '
                  'voter:profiles!poll_votes_user_id_fkey(*)')
              .eq('poll_id', poll.id);
          closedVotes = vrows.map(PollVote.fromJson).toList();
        }
        views.add(PollView(
          poll: poll,
          options: opts,
          tallies: tallies,
          myOptionId: myOptionByPoll[poll.id],
          closedVotes: closedVotes,
        ));
      }
      return views;
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> createPoll(
    String eventId, {
    required String question,
    required PollKind kind,
    required PollMode mode,
    required List<String> labels,
  }) async {
    final uid = _uid;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      // Atomic RPC (SECURITY INVOKER, so RLS still applies): poll + options in
      // one call — a failure can't leave an option-less poll behind.
      await _client.rpc('create_poll_with_options', params: {
        'p_event': eventId,
        'p_question': question.trim(),
        'p_kind': kind.name,
        'p_mode':
            mode == PollMode.weightedRandom ? 'weighted_random' : 'majority',
        'p_labels': [
          for (final l in labels)
            if (l.trim().isNotEmpty) l.trim(),
        ],
      });
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Cast or change the caller's vote (one per poll). Upserts on (poll_id,user_id).
  Future<void> vote(String pollId, String eventId, String optionId) async {
    final uid = _uid;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      await _client.from('poll_votes').upsert({
        'poll_id': pollId,
        'event_id': eventId,
        'option_id': optionId,
        'user_id': uid,
      }, onConflict: 'poll_id,user_id');
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> clearVote(String pollId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _client
          .from('poll_votes')
          .delete()
          .eq('poll_id', pollId)
          .eq('user_id', uid);
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> closePoll(String pollId) async {
    try {
      await _client.rpc('close_poll', params: {'p_poll': pollId});
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> reopenPoll(String pollId) async {
    try {
      await _client.rpc('reopen_poll', params: {'p_poll': pollId});
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Future<void> deletePoll(String pollId) async {
    try {
      await _client.from('polls').delete().eq('id', pollId);
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final pollRepositoryProvider = Provider<PollRepository>((ref) {
  return PollRepository(ref.watch(supabaseClientProvider));
});
