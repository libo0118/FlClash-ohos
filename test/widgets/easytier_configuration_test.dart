import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/config/easytier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  const props = EasyTierProps(
    enable: true,
    networkName: 'office-net',
    networkSecret: 'secret',
    peerUrls: ['tcp://gateway.invalid:11010'],
  );

  testWidgets('configuration validates peer URLs before saving', (
    tester,
  ) async {
    await _openConfiguration(tester, props);
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'https://gateway.invalid',
    );
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    tester.state<ScrollableState>(_formScroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Enter valid EasyTier peer URLs, for example tcp://host:11010.',
      ),
      findsOneWidget,
    );
    expect(find.byType(EasyTierConfigurationDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'configuration rejects a supplemental CIDR that overlaps the VPN',
    (tester) async {
      await _openConfiguration(tester, props);
      final cidrs = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == '10.144.144.0/24\n192.168.50.0/24',
      );
      await tester.scrollUntilVisible(
        cidrs,
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(cidrs, '172.19.0.0/30');
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FormPage>(find.byType(FormPage)).error,
        contains('They must not overlap 172.19.0.0/30'),
      );
      tester.state<ScrollableState>(_formScroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('They must not overlap 172.19.0.0/30'),
        findsOneWidget,
      );
      expect(find.byType(EasyTierConfigurationDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'secret is hidden and multiline fields grow with their contents',
    (tester) async {
      await _openConfiguration(tester, props);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isTrue,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(2)).maxLines,
        isNull,
      );
      final cidrs = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == '10.144.144.0/24\n192.168.50.0/24',
      );
      await tester.scrollUntilVisible(cidrs, 250, scrollable: _formScroll);
      expect(tester.widget<TextField>(cidrs).maxLines, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('valid configuration returns the saved values from the form', (
    tester,
  ) async {
    EasyTierProps? saved;
    await _openConfiguration(tester, props, onSaved: (value) => saved = value);
    await tester.enterText(find.byType(TextFormField).at(0), ' office-net-2 ');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(saved, props.copyWith(networkName: 'office-net-2'));
    expect(find.byType(EasyTierConfigurationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Finder get _formScroll => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

Future<void> _openConfiguration(
  WidgetTester tester,
  EasyTierProps props, {
  ValueChanged<EasyTierProps?>? onSaved,
}) async {
  const size = Size(390, 900);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TestApp(
      overrides: [viewSizeProvider.overrideWithBuild((_, _) => size)],
      child: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await showFormSheet<EasyTierProps>(
                context: context,
                builder: (_) => EasyTierConfigurationDialog(props: props),
              );
              onSaved?.call(result);
            },
            child: const Text('Configure'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Configure'));
  await tester.pumpAndSettle();
}
