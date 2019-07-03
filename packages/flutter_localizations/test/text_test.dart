// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Text baseline with CJK locale', (WidgetTester tester) async {
    // This test in combination with 'Text baseline with EN locale' verify the baselines
    // used to align text with ideographic baselines is reasonable. We are currently
    // using the alphabetic baseline to lay out as the ideographic baseline is not yet
    // properly implemented. When the ideographic baseline is better defined and implemented,
    // the values of this test should change very slightly. See the issue this is based off
    // of: https://github.com/flutter/flutter/issues/25782.
    final Key targetKey = UniqueKey();
    await tester.pumpWidget(
      MaterialApp(
        routes: <String, WidgetBuilder>{
          '/next': (BuildContext context) {
            return const Text('Next');
          },
        },
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[
          Locale('en', 'US'),
          Locale('es', 'ES'),
          Locale('zh', 'CN'),
        ],
        locale: const Locale('zh', 'CN'),
        home: Material(
          child: Center(
            child: Builder(
              key: targetKey,
              builder: (BuildContext context) {
                return PopupMenuButton<int>(
                  onSelected: (int value) {
                    Navigator.pushNamed(context, '/next');
                  },
                  itemBuilder: (BuildContext context) {
                    return [
                      PopupMenuItem(
                        value: 1,
                        child: Text(
                          'hello, world',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                      PopupMenuItem(
                        value: 2,
                        child: Text(
                          '你好，世界',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                    ];
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(targetKey));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // finish the menu animation

    expect(find.text('hello, world'), findsOneWidget);
    expect(find.text('你好，世界'), findsOneWidget);

    Offset topLeft = tester.getTopLeft(find.text('hello, world'));
    Offset topRight = tester.getTopRight(find.text('hello, world'));
    Offset bottomLeft = tester.getBottomLeft(find.text('hello, world'));
    Offset bottomRight = tester.getBottomRight(find.text('hello, world'));

    expect(topLeft, Offset(392.0, 298.3999996185303));
    expect(topRight, Offset(596.0, 298.3999996185303));
    expect(bottomLeft, Offset(392.0, 315.3999996185303));
    expect(bottomRight, Offset(596.0, 315.3999996185303));

    topLeft = tester.getTopLeft(find.text('你好，世界'));
    topRight = tester.getTopRight(find.text('你好，世界'));
    bottomLeft = tester.getBottomLeft(find.text('你好，世界'));
    bottomRight = tester.getBottomRight(find.text('你好，世界'));

    expect(topLeft, Offset(392.0, 346.3999996185303));
    expect(topRight, Offset(477.0, 346.3999996185303));
    expect(bottomLeft, Offset(392.0, 363.3999996185303));
    expect(bottomRight, Offset(477.0, 363.3999996185303));
  });

  testWidgets('Text baseline with EN locale', (WidgetTester tester) async {
    // This test in combination with 'Text baseline with CJK locale' verify the baselines
    // used to align text with ideographic baselines is reasonable. We are currently
    // using the alphabetic baseline to lay out as the ideographic baseline is not yet
    // properly implemented. When the ideographic baseline is better defined and implemented,
    // the values of this test should change very slightly. See the issue this is based off
    // of: https://github.com/flutter/flutter/issues/25782.
    final Key targetKey = UniqueKey();
    await tester.pumpWidget(
      MaterialApp(
        routes: <String, WidgetBuilder>{
          '/next': (BuildContext context) {
            return const Text('Next');
          },
        },
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[
          Locale('en', 'US'),
          Locale('es', 'ES'),
          Locale('zh', 'CN'),
        ],
        locale: const Locale('en', 'US'),
        home: Material(
          child: Center(
            child: Builder(
              key: targetKey,
              builder: (BuildContext context) {
                return PopupMenuButton<int>(
                  onSelected: (int value) {
                    Navigator.pushNamed(context, '/next');
                  },
                  itemBuilder: (BuildContext context) {
                    return [
                      PopupMenuItem(
                        value: 1,
                        child: Text(
                          'hello, world',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                      PopupMenuItem(
                        value: 2,
                        child: Text(
                          '你好，世界',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                    ];
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(targetKey));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // finish the menu animation

    expect(find.text('hello, world'), findsOneWidget);
    expect(find.text('你好，世界'), findsOneWidget);

    Offset topLeft = tester.getTopLeft(find.text('hello, world'));
    Offset topRight = tester.getTopRight(find.text('hello, world'));
    Offset bottomLeft = tester.getBottomLeft(find.text('hello, world'));
    Offset bottomRight = tester.getBottomRight(find.text('hello, world'));


    expect(topLeft, Offset(392.0, 299.19999980926514));
    expect(topRight, Offset(584.0, 299.19999980926514));
    expect(bottomLeft, Offset(392.0, 315.19999980926514));
    expect(bottomRight, Offset(584.0, 315.19999980926514));

    topLeft = tester.getTopLeft(find.text('你好，世界'));
    topRight = tester.getTopRight(find.text('你好，世界'));
    bottomLeft = tester.getBottomLeft(find.text('你好，世界'));
    bottomRight = tester.getBottomRight(find.text('你好，世界'));

    expect(topLeft, Offset(392.0, 347.19999980926514));
    expect(topRight, Offset(472.0, 347.19999980926514));
    expect(bottomLeft, Offset(392.0, 363.19999980926514));
    expect(bottomRight, Offset(472.0, 363.19999980926514));
  });
}
