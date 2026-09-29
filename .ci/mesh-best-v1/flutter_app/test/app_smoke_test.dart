import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/app/best_app.dart';

void main() {
  testWidgets('Best v1 shell renders architecture status', (tester) async {
    await tester.pumpWidget(const BestApp());
    expect(find.text('Mesh Messenger Best v1'), findsOneWidget);
    expect(find.textContaining('M02 -> M07 -> M12'), findsOneWidget);
    expect(find.textContaining('experimental'), findsOneWidget);
  });
}
