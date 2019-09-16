// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui show StrutStyle;

import 'package:flutter/painting.dart';
import '../flutter_test_alternative.dart';

void main() {
  test('StrutStyle diagnostics test', () {
    final StrutStyle s0 = StrutStyle(
      fontFamily: 'Serif',
      fontSize: 14,
    );
    expect(
      s0.toString(),
      equals('StrutStyle(family: Serif, size: 14.0)'),
    );

    final StrutStyle s1 = StrutStyle(
      fontFamily: 'Serif',
      fontSize: 14,
      forceStrutHeight: true,
    );
    expect(s1.fontFamily, 'Serif');
    expect(s1.fontSize, 14.0);
    expect(s1, equals(s1));
    expect(
      s1.toString(),
      equals('StrutStyle(family: Serif, size: 14.0, <strut height forced>)'),
    );

    final StrutStyle s2 = StrutStyle(
      fontFamily: 'Serif',
      fontSize: 14,
      forceStrutHeight: false,
    );
    expect(
      s2.toString(),
      equals('StrutStyle(family: Serif, size: 14.0, <strut height normal>)'),
    );

    final StrutStyle s3 = StrutStyle();
    expect(
      s3.toString(),
      equals('StrutStyle'),
    );

    final StrutStyle s4 = StrutStyle(
      forceStrutHeight: false,
    );
    expect(
      s4.toString(),
      equals('StrutStyle(<strut height normal>)'),
    );

    final StrutStyle s5 = StrutStyle(
      forceStrutHeight: true,
    );
    expect(
      s5.toString(),
      equals('StrutStyle(<strut height forced>)'),
    );
  });
}
