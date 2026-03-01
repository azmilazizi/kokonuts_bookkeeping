import 'package:flutter_test/flutter_test.dart';
import 'package:kokonuts_bookkeeping/services/purchase_orders_service.dart';

void main() {
  group('PurchaseOrder orderStatus parsing', () {
    test('maps direct return status string', () {
      final order = PurchaseOrder.fromJson({
        'id': '1',
        'order_status': 'return',
      });

      expect(order.orderStatus, 'return');
    });

    test('maps nested order_status map name to return', () {
      final order = PurchaseOrder.fromJson({
        'id': '2',
        'order_status': {
          'id': 3,
          'name': 'Return',
        },
      });

      expect(order.orderStatus, 'return');
    });

    test('maps delivery_status map status to delivered', () {
      final order = PurchaseOrder.fromJson({
        'id': '3',
        'delivery_status': {
          'status': 'Delivered',
        },
      });

      expect(order.orderStatus, 'delivered');
    });
  });
}
