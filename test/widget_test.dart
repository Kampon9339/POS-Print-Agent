import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_print_agent/main.dart';
import 'package:pos_print_agent/modules/print_engine/mock_print_backend.dart';
import 'package:pos_print_agent/shared/services/service_locator.dart';

void main() {
  testWidgets(
    'POS Print Agent Thai Desktop UI renders and navigates all screens',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBackend = MockPrintBackend();
      final container = AgentServiceContainer.createForTest(
        osBackend: mockBackend,
        tcpBackend: mockBackend,
      );
      addTearDown(() async => container.shutdown());

      await tester.pumpWidget(PosPrintAgentApp(services: container));
      await tester.pumpAndSettle();

      // 1. Verify Dashboard screen (Thai)
      expect(
        find.textContaining('แผงควบคุมระบบพิมพ์ (POS Print Agent Dashboard)'),
        findsOneWidget,
      );

      // 2. Navigate to Printers screen
      await tester.tap(find.text('เครื่องพิมพ์ (Printers)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('จัดการเครื่องพิมพ์และกฎการส่งพิมพ์'),
        findsOneWidget,
      );

      // 2a. Open Add Printer Dialog and verify no overflow occurs
      await tester.tap(find.text('เพิ่มเครื่องพิมพ์ใหม่'));
      await tester.pumpAndSettle();
      expect(find.text('เพิ่มเครื่องพิมพ์ใหม่ (Add Printer)'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();

      // 3. Navigate to Print Queue screen
      await tester.tap(find.text('คิวงานพิมพ์ (Print Queue)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('คิวงานพิมพ์ใบเสร็จ (Print Queue)'),
        findsOneWidget,
      );

      // 4. Navigate to Print History screen
      await tester.tap(find.text('ประวัติการพิมพ์ (History)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('ประวัติการพิมพ์ใบเสร็จ (Print History)'),
        findsOneWidget,
      );

      // 5. Navigate to POS Pairing screen
      await tester.tap(find.text('การเชื่อมต่อ POS (Pairing)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('การเชื่อมต่อ Web POS และการจับคู่อุปกรณ์'),
        findsOneWidget,
      );

      // 6. Navigate to Settings screen
      await tester.tap(find.text('ตั้งค่าระบบ (Settings)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('ตั้งค่าระบบและรูปแบบใบเสร็จ'),
        findsOneWidget,
      );
    },
  );
}
