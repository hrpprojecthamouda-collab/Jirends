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

  /// Live stream of an event's polls (fully composed). Re-fetches the whole set
  /// whenever the polls/options/votes for this event change.
  Stream<List<PollView>> watchPolls(String eventId) {
    return _client
        .from('polls')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .asyncMap((_) => fetchPolls(eventId));
  }

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

      final views = <PollView>[];
      for (final poll in polls) {
        final opts = options.where((o) => o.pollId == poll.id).toList();
        final tallyRows = await _client.rpc('poll_tallies', params: {'p_poll': poll.id});
        final tallies = <String, int>{
          for (final r in (tallyRows as List))
            (r as Map)['option_id'] as String: (r['votes'] as num).toInt(),
        };
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
      final pollRow = await _client
          .from('polls')
          .insert({
            'event_id': eventId,
            'question': question.trim(),
            'kind': kind.name,
            'mode': mode == PollMode.weightedRandom ? 'weighted_random' : 'majority',
            'created_by': uid,
          })
          .select()
          .single();
      final pollId = pollRow['id'] as String;
      final cleaned = labels
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      await _client.from('poll_options').insert([
        for (var i = 0; i < cleaned.length; i++)
          {'poll_id': pollId, 'event_id': eventId, 'label': cleaned[i], 'position': i + 1},
      ]);
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
