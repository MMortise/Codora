// V2EX's reply API lags about an hour behind. A thread posted minutes ago
// reports its reply count correctly and then hands back an empty list, so a
// brand-new discussion looked like it had no replies at all.
//
//   flutter test --dart-define=LIVE=true test/v2ex_fresh_replies_test.dart
import 'package:codora/core/models.dart';
import 'package:codora/sources/v2ex_source.dart';
import 'package:flutter_test/flutter_test.dart';

const live = bool.fromEnvironment('LIVE');

void main() {
  test('a freshly posted thread still shows its replies', () async {
    final src = V2exSource();

    // The newest thread that anyone has answered is exactly the case the API
    // cannot serve yet.
    final feed = await src.fetchTopics(
        const Section(id: 'latest', title: '最新'));
    final fresh = feed.items.firstWhere(
      (t) => (t.replyCount ?? 0) >= 2,
      orElse: () => throw StateError('no answered thread in the latest feed'),
    );

    final replies = await src.fetchReplies(fresh.id);
    expect(replies.items, isNotEmpty,
        reason: 'topic ${fresh.id} claims ${fresh.replyCount} replies');
    expect(replies.items.length, greaterThanOrEqualTo(fresh.replyCount! - 1),
        reason: 'the page should carry essentially all of them');

    final first = replies.items.first;
    expect(first.floor, 1);
    expect(first.author?.name, isNotEmpty);
    expect(first.content.trim(), isNotEmpty);
    expect(first.createdAt, isNotNull);
    expect(first.author?.avatarUrl, startsWith('https://'));

    // Floors run in order, without gaps.
    for (var i = 0; i < replies.items.length; i++) {
      expect(replies.items[i].floor, i + 1);
    }
  }, skip: !live);

  test('an older thread is unaffected', () async {
    final src = V2exSource();
    final hot = await src.fetchTopics(const Section(id: 'hot', title: '最热'));
    final busy = hot.items.firstWhere((t) => (t.replyCount ?? 0) > 20);
    final replies = await src.fetchReplies(busy.id);
    expect(replies.items.length, greaterThan(20));
  }, skip: !live);
}
