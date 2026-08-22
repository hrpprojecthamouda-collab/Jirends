/// Detecting and inserting @mentions in a comment.
///
/// The database trigger parses `@nickname#tagline` out of the posted body, so
/// what this code inserts has to match that exactly — a mention that does not
/// parse fails silently, with no notification and nothing to see.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:jirends/features/auth/data/profile.dart';
import 'package:jirends/features/events/data/event_member.dart';
import 'package:jirends/features/events/presentation/widgets/mention_suggestions.dart';

EventMember _m(String nick, String tag, {bool organizer = false}) => EventMember(
      userId: '$nick-$tag',
      role: organizer ? MemberRole.organizer : MemberRole.member,
      rsvp: RsvpStatus.going,
      profile: Profile(id: '$nick-$tag', nickname: nick, tagline: tag),
    );

final _members = [
  _m('Moez', 'zahrouni', organizer: true),
  _m('besbes', 'zahrouni'),
  _m('fanfan', 'zah'),
];

void main() {
  group('detecting a mention', () {
    test('a bare @ at the start opens the picker', () {
      final q = mentionQueryAt('@', 1);
      expect(q, isNotNull);
      expect(q!.start, 0);
      expect(q.text, '');
    });

    test('@ after a space opens it, and collects what follows', () {
      final q = mentionQueryAt('hey @bes', 8);
      expect(q!.start, 4);
      expect(q.text, 'bes');
    });

    test('matching is case-insensitive', () {
      expect(mentionQueryAt('hey @BES', 8)!.text, 'bes');
    });

    test('an @ mid-word does NOT open it', () {
      // Otherwise typing an email address hijacks the field.
      expect(mentionQueryAt('mail me at moez@gmail', 21), isNull);
    });

    test('a space ends the mention', () {
      expect(mentionQueryAt('hey @besbes done', 16), isNull);
    });

    test('a newline ends it too', () {
      expect(mentionQueryAt('hey @besbes\nnext', 16), isNull);
    });

    test('the caret before the @ is not inside it', () {
      expect(mentionQueryAt('hey @besbes', 4), isNull);
    });

    test('a completed handle is still an open mention while adjacent', () {
      // The # is part of the handle, so typing it must not close the picker.
      final q = mentionQueryAt('hey @besbes#zah', 15);
      expect(q, isNotNull);
      expect(q!.text, 'besbes#zah');
    });
  });

  group('matching members', () {
    test('an empty query lists everyone', () {
      expect(matchMembers(_members, ''), hasLength(3));
    });

    test('matches on either half of the handle', () {
      expect(matchMembers(_members, 'bes').single.profile.nickname, 'besbes');
      expect(matchMembers(_members, 'zah'), hasLength(3));
    });

    test('no match is empty, not everyone', () {
      expect(matchMembers(_members, 'nobody'), isEmpty);
    });
  });

  group('inserting a mention', () {
    test('replaces the typed fragment with the full handle and a space', () {
      const text = 'hey @bes';
      final q = mentionQueryAt(text, text.length)!;
      final r = applyMention(text, q, _members[1].profile);

      // Exactly the shape the SQL trigger's regexp expects.
      expect(r.text, 'hey @besbes#zahrouni ');
      expect(r.caret, r.text.length);
    });

    test('keeps whatever follows the caret', () {
      const text = 'hey @bes and hello';
      final q = mentionQueryAt(text, 8)!;
      final r = applyMention(text, q, _members[1].profile);

      expect(r.text, 'hey @besbes#zahrouni  and hello');
      expect(r.caret, 'hey @besbes#zahrouni '.length);
    });

    test('a handleless profile is left alone rather than inserting garbage', () {
      const text = '@x';
      final q = mentionQueryAt(text, 2)!;
      final r = applyMention(text, q, const Profile(id: 'u'));
      expect(r.text, text);
    });
  });
}
