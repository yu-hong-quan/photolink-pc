import 'package:flutter_test/flutter_test.dart';
import 'package:photolink_pc/main.dart';

void main() {
  testWidgets('PhotoLinkPcApp smoke', (WidgetTester tester) async {
    // 桌面端 main 依赖 window_manager，单测只验证组件可构建
    await tester.pumpWidget(const PhotoLinkPcApp());
    expect(find.textContaining('PhotoLink'), findsWidgets);
  });
}
