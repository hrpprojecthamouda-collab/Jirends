/// The @-mention picker that sits above a comment compose field.
///
/// Typing `@` opens a list of the event's MEMBERS; picking one inserts the full
/// `@nickname#tagline` handle, which is what the database trigger parses (see
/// comment_mentions.sql). Nobody should have to type a handle by hand — they
/// contain a `#` and an exact-case nickname, and getting either wrong means the
/// mention silently does nothing.
///
/// Members only, and that is a visibility rule rather than a convenience: a
/// mention notification names its event, so it may only reach somebody who can
/// already see that event. Offering a non-member here would invite the author
/// to tag someone who then gets nothing, and on a surprise event the picker
/// itself must never hint that the target exists.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/data/profile.dart';
import '../../../profile/presentation/user_avatar.dart';
import '../../data/event_member.dart';

/// An active mention being typed: where the `@` is, and what has been typed
/// since. Null when the caret is not inside a mention.
class MentionQuery {
  const MentionQuery({required this.start, required this.text});

  /// Index of the `@` in the field.
  final int start;

  /// What the user has typed after the `@`, lowercased for matching.
  final String text;
}

/// Find the mention the caret is currently inside, if any.
///
/// A mention starts at an `@` that is at the very start of the text or follows
/// whitespace — so an email address does not open the picker — and runs to the
/// caret. Whitespace ends it: once you type a space the mention is over.
MentionQuery? mentionQueryAt(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;

  var i = caret - 1;
  while (i >= 0) {
    final ch = text[i];
    if (ch == '@') {
      final before = i == 0 ? ' ' : text[i - 1];
      if (before.trim().isNotEmpty) return null; // mid-word @, e.g. an email
      return MentionQuery(
        start: i,
        text: text.substring(i + 1, caret).toLowerCase(),
      );
    }
    // A space (or newline) before finding an @ means we are not in a mention.
    if (ch.trim().isEmpty) return null;
    i--;
  }
  return null;
}

/// Members whose handle matches [query], best-effort and case-insensitive.
/// An empty query lists everyone, so a bare `@` is useful immediately.
List<EventMember> matchMembers(List<EventMember> members, String query) {
  if (query.isEmpty) return members;
  return [
    for (final m in members)
      if ((m.profile.handle ?? '').toLowerCase().contains(query)) m,
  ];
}

/// Replace the in-progress mention with [profile]'s full handle and return the
/// new text plus where the caret should land (just past the inserted handle
/// and its trailing space).
({String text, int caret}) applyMention(
  String text,
  MentionQuery query,
  Profile profile,
) {
  final handle = profile.handle;
  if (handle == null) return (text: text, caret: query.start);
  final end = query.start + 1 + query.text.length;
  final inserted = '@$handle ';
  return (
    text: text.replaceRange(query.start, end, inserted),
    caret: query.start + inserted.length,
  );
}

/// The dropdown itself. Renders nothing when there is nothing to suggest, so
/// the caller can place it unconditionally.
class MentionSuggestions extends StatelessWidget {
  const MentionSuggestions({
    super.key,
    required this.matches,
    required this.onPick,
  });

  final List<EventMember> matches;
  final ValueChanged<Profile> onPick;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: matches.length,
        itemBuilder: (context, i) {
          final m = matches[i];
          return ListTile(
            dense: true,
            leading: UserAvatar(profile: m.profile, radius: 16),
            title: Text(m.profile.handle ?? '…'),
            trailing: m.isOrganizer
                ? Icon(Icons.star, size: 16, color: AppColors.primary)
                : null,
            onTap: () => onPick(m.profile),
          );
        },
      ),
    );
  }
}
