import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:two_space_app/screens/chat_screen.dart';

void main() {
  testWidgets('ChatScreen builds and shows input', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(peerId: 'test-peer', title: 'Тест')));
    // Allow async init to run
    await tester.pump(const Duration(seconds: 1));

    // Expect to find the message input field hint
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Сообщение'), findsOneWidget);
  });
}
