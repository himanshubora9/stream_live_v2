import 'package:flutter_test/flutter_test.dart';

import 'package:stream_live_v2/main.dart';

void main() {
  testWidgets('login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Viva Live Login'), findsOneWidget);
    expect(find.text('Login & Continue'), findsOneWidget);
  });
}
