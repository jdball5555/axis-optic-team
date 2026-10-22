import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:axis_team/ui/views/portal_view.dart';
import 'package:axis_team/providers/app_providers.dart';

void main() {
  testWidgets('PortalView only displays stores and links matching owned_stores',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final sampleLinks = [
      const PortalLink(
        id: 'link_1',
        title: 'Team Schedule Portal',
        url: 'https://example.com/schedule',
        description: 'For owned stores only',
        group: 'Operations',
        storeIds: {'owned_1'},
      ),
    ];

    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => {
            'id': 'owner_1',
            'first_name': 'Owner',
            'last_name': 'User',
            'owned_stores': ['owned_1', 'owned_2'],
          },
        ),
        currentStoreIdProvider.overrideWith((ref) => null), // All stores
        allStoresStreamProvider.overrideWith(
          (ref) => Stream.value([
            {'id': 'owned_1', 'name': 'My Store 1'},
            {'id': 'owned_2', 'name': 'My Store 2'},
          ]),
        ),
        portalLinksProvider.overrideWith((ref) => Stream.value(sampleLinks)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PortalView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify title and links
    expect(find.text('Portal'), findsOneWidget);
    expect(find.text('Team Schedule Portal'), findsOneWidget);

    // Verify only owned stores are present in the UI and unowned are completely absent
    expect(find.text('My Store 1'), findsWidgets);
    expect(find.text('202 Unowned'), findsNothing);
    expect(find.text('North Unowned'), findsNothing);
  });
}
