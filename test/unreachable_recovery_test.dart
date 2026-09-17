// What a reader whose network cannot reach V2EX actually sees, and where the
// button takes them. The proxy field is no use if the failure that needs it
// reads as a generic network error.
import 'package:codora/core/models.dart';
import 'package:codora/sources/v2ex_source.dart';
import 'package:codora/widgets/error_view.dart';
import 'package:codora/features/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final connectionFailed = DioException.connectionTimeout(
  timeout: const Duration(seconds: 15),
  requestOptions: RequestOptions(path: '/api/topics/hot.json'),
);

late ProviderContainer container;

Future<void> showError(WidgetTester tester, Object error) async {
  container = await pumpApp(tester, ErrorView(error: error));
}

void main() {
  resetBootstrapState();

  testWidgets('an unreachable V2EX explains the proxy, not "网络错误"',
      (tester) async {
    await showError(tester, V2exSource().unreachableError(connectionFailed));

    expect(find.text('连不上 V2EX'), findsOneWidget);
    expect(find.textContaining('代理地址'), findsOneWidget);
    expect(find.text('到设置里更新这个站点的凭据。'), findsNothing,
        reason: 'the generic credential line is wrong for a routing problem');
    expect(find.text('前往设置'), findsOneWidget);
  });

  testWidgets('its button lands on the tab holding the proxy field',
      (tester) async {
    await showError(tester, V2exSource().unreachableError(connectionFailed));
    container.read(settingsTabProvider.notifier).state = SettingsTab.general;

    await tester.tap(find.text('前往设置'));
    await tester.pumpAndSettle();

    expect(container.read(navProvider), NavTarget.settings);
    expect(container.read(settingsTabProvider), SettingsTab.forums);
  });

  testWidgets('a credential problem still gets the credential wording',
      (tester) async {
    await showError(
        tester,
        AuthRequiredException(
            SiteId.v2ex, 'V2EX Token 无效或已过期', AuthRecovery.settings));

    expect(find.text('到设置里更新这个站点的凭据。'), findsOneWidget);
  });

  testWidgets('a plain failure is still shown plainly', (tester) async {
    await showError(tester, Exception('V2EX 限流了（HTTP 429），过一会儿再试'));

    expect(find.text('V2EX 限流了（HTTP 429），过一会儿再试'), findsOneWidget);
    expect(find.text('前往设置'), findsNothing);
  });
}
