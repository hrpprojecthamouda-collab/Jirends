import 'package:flutter_test/flutter_test.dart';
import 'package:jirends/features/auth/data/profile.dart';

void main() {
  group('Profile.handle', () {
    test('is null until both nickname and tagline are set', () {
      const noHandle = Profile(id: 'u1');
      expect(noHandle.hasHandle, isFalse);
      expect(noHandle.handle, isNull);

      const partial = Profile(id: 'u1', nickname: 'Sparrow');
      expect(partial.hasHandle, isFalse);
      expect(partial.handle, isNull);
    });

    test('renders nickname#tagline once both are set', () {
      const p = Profile(id: 'u1', nickname: 'Sparrow', tagline: 'TheCrew');
      expect(p.hasHandle, isTrue);
      expect(p.handle, 'Sparrow#TheCrew');
    });

    test('round-trips through JSON with snake_case keys', () {
      final json = {
        'id': 'u1',
        'nickname': 'Sparrow',
        'tagline': 'TheCrew',
        'avatar_url': 'https://example.com/a.png',
      };
      final p = Profile.fromJson(json);
      expect(p.avatarUrl, 'https://example.com/a.png');
      expect(p.toJson()['avatar_url'], 'https://example.com/a.png');
    });
  });
}
