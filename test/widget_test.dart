import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 最小冒烟测试。
///
/// 刻意**不引用** `lib/main.dart` 里的具体 widget（如 MyApp / MyHomePage），
/// 因此 Phase 3 重写主界面、给入口改名后，这里不会失效。
void main() {
  testWidgets('Flutter 测试环境可用', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
