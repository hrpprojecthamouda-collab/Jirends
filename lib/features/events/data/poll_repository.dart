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
    required this.myOptionIds,
    required this.voterCount,
    required this.votes,
  });

  final Poll poll;
  final List<PollOption> options;
  final Map<String, int> tallies; // optionId -> votes
  /// Every option the caller has backed. A member may pick several.
  final Set<String> myOptionIds;

  /// Distinct people who voted — NOT the same as [totalVotes] once members can
  /// back several options each. Comes from a member-gated RPC because an open
  /// poll hides other members' vote rows (VIS-7).
  ///
  /// Null when that RPC is unavailable (e.g. the database has not had
  /// polls_multivote.sql applied yet). Callers omit the figure rather than
  /// guessing — `totalVotes` is NOT a stand-in, since one member may back
  /// several options.
  final int? voterCount;
  /// Who voted for what, always populated. Ballot secrecy while a poll is open
  /// (the old VIS-7) was deliberately retired — members may see each other's
  /// votes at any time. Still member-scoped: a non-member reads none of it.
  final List<PollVote> votes;

  /// Total votes cast across all options. With multi-select this can exceed
  /// [voterCount] — use that one when you mean "how many people".
  int get totalVotes => tallies.values.fold(0, (a, b) => a + b);
  int votesFor(String optionId) => tallies[optionId] ?? 0;

  /// Everyone who backed [optionId], for the press-and-hold voters panel.
  List<PollVote> votersFor(String optionId) =>
      [for (final v in votes) if (v.optionId == optionId) v];
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
      final myOptionsByPoll = <String, Set<String>>{};
      for (final r in myVoteRows) {
        (myOptionsByPoll[r['poll_id'] as String] ??= <String>{})
            .add(r['option_id'] as String);
      }

      // All tallies for the event in one round-trip (member-gated RPC).
      final tallyRows = await _client
          .rpc('poll_tallies_for_event', params: {'p_event': eventId});
      final talliesByPoll = <String, Map<String, int>>{};
      for (final r in (tallyRows as List)) {
        final row = r as Map;
        (talliesByPoll[row['poll_id'] as String] ??= {})[
            row['option_id'] as String] = (row['votes'] as num).toInt();
      }

      // Distinct voters per poll (see the RPC's comment in polls.sql).
      //
      // Deliberately non-fatal: this is one optional figure on a preview, and
      // an older database that predates polls_multivote.sql simply has no such
      // function. Letting that failure escape would take down the entire polls
      // view — questions, options, votes and all — over a missing count. On
      // failure every poll just reports an unknown voter count.
      var votersByPoll = <String, int>{};
      try {
        final voterRows = await _client
            .rpc('poll_voter_counts_for_event', params: {'p_event': eventId});
        votersByPoll = {
          for (final r in (voterRows as List))
            (r as Map)['poll_id'] as String: (r['voters'] as num).toInt(),
        };
      } catch (_) {
        // Leave it empty -> voterCount stays null per poll.
      }

      // Every vote in the event, in ONE query rather than one per poll. Open
      // polls included: members may now see who voted at any time.
      final voteRows = await _client
          .from('poll_votes')
          .select('id, poll_id, option_id, user_id, '
              'voter:profiles!poll_votes_user_id_fkey(*)')
          .eq('event_id', eventId);
      final votesByPoll = <String, List<PollVote>>{};
      for (final r in voteRows) {
        (votesByPoll[r['poll_id'] as String] ??= <PollVote>[])
            .add(PollVote.fromJson(r));
      }

      final views = <PollView>[];
      for (final poll in polls) {
        final opts = options.where((o) => o.pollId == poll.id).toList();
        final tallies = talliesByPoll[poll.id] ?? const <String, int>{};
        views.add(PollView(
          poll: poll,
          options: opts,
          tallies: tallies,
          myOptionIds: myOptionsByPoll[poll.id] ?? const <String>{},
          voterCount: votersByPoll[poll.id],
          votes: votesByPoll[poll.id] ?? const [],
        ));
      }
      return views;
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// [values] pairs 1:1 with [labels] and is required for day/time kinds
  /// (day: 'YYYY-MM-DD', time: 'HH:mm') — it's what gets applied to the event
  /// when the poll closes. Pass null for general/place.
  Future<void> createPoll(
    String eventId, {
    required String question,
    required PollKind kind,
    required PollMode mode,
    required List<String> labels,
    List<String?>? values,
  }) async {
    final uid = _uid;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    assert(values == null || values.length == labels.length,
        'values must pair 1:1 with labels');
    try {
      // Atomic RPC (SECURITY INVOKER, so RLS still applies): poll + options in
      // one call — a failure can't leave an option-less poll behind. Keep the
      // label/value pairing intact: only drop entries whose label is empty.
      final keep = [
        for (var i = 0; i < labels.length; i++)
          if (labels[i].trim().isNotEmpty) i,
      ];
      await _client.rpc('create_poll_with_options', params: {
        'p_event': eventId,
        'p_question': question.trim(),
        'p_kind': kind.name,
        'p_mode':
            mode == PollMode.weightedRandom ? 'weighted_random' : 'majority',
        'p_labels': [for (final i in keep) labels[i].trim()],
        if (values != null) 'p_values': [for (final i in keep) values[i]],
      });
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Cast or change the caller's vote (one per poll). Upserts on (poll_id,user_id).
  /// Toggle one option for the caller: back it if they haven't, withdraw it if
  /// they have. Members may back several options in the same poll, so this no
  /// longer replaces an existing vote — it only ever touches [optionId].
  ///
  /// Requires the widened `unique (poll_id, user_id, option_id)` key; against
  /// the old per-poll key a second option is rejected (see
  /// polls_multivote.sql).
  Future<void> vote(String pollId, String eventId, String optionId) async {
    final uid = _uid;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    try {
      final existing = await _client
          .from('poll_votes')
          .select('id')
          .eq('poll_id', pollId)
          .eq('option_id', optionId)
          .eq('user_id', uid)
          .maybeSingle();

      if (existing != null) {
        await _client
            .from('poll_votes')
            .delete()
            .eq('id', existing['id'] as String);
        return;
      }

      await _client.from('poll_votes').insert({
        'poll_id': pollId,
        'event_id': eventId,
        'option_id': optionId,
        'user_id': uid,
      });
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
