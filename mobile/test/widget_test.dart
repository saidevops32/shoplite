import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoplite/main.dart';

void main() {
  testWidgets('ShopLite app renders', (WidgetTester tester) async {
    await tester.pumpWidget(const ShopLiteApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
