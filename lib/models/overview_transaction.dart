import 'package:intl/intl.dart';

import '../services/bills_service.dart';
import '../services/expenses_service.dart';
import '../services/purchase_order_detail_service.dart';
import '../services/purchase_orders_service.dart';

class OverviewTransaction {
  final String id;
  final DateTime date;
  final String number;
  final String? name;
  final String? expenseName;
  final String vendor;
  final String type;
  final double amount;
  final String status;
  final String? paymentMode;

  OverviewTransaction({
    required this.id,
    required this.date,
    required this.number,
    this.name,
    this.expenseName,
    required this.vendor,
    required this.type,
    required this.amount,
    required this.status,
    this.paymentMode,
  });

  String get formattedDate {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  String get formattedAmount {
    return NumberFormat.simpleCurrency(name: '').format(amount);
  }

  String get displayName {
    if (type.toLowerCase() == 'bill' &&
        expenseName != null &&
        expenseName!.trim().isNotEmpty) {
      return expenseName!;
    }
    if (name != null && name!.trim().isNotEmpty) {
      return name!;
    }
    return number;
  }

  factory OverviewTransaction.fromExpense(Expense expense) {
    return OverviewTransaction(
      id: expense.id,
      date: expense.date ?? DateTime.now(),
      number: expense.name.isEmpty ? '—' : expense.name,
      name: expense.name.isEmpty ? null : expense.name,
      vendor: expense.vendor.isEmpty ? '—' : expense.vendor,
      type: 'Expense',
      amount: expense.amount ?? 0.0,
      status: 'Paid',
      paymentMode: _emptyToNull(expense.paymentMode),
    );
  }

  factory OverviewTransaction.fromBill(Bill bill) {
    return OverviewTransaction(
      id: bill.id,
      date: bill.billDate ?? DateTime.now(),
      number: bill.id.isEmpty ? 'Bill' : 'Bill #${bill.id}',
      name: bill.payments.isNotEmpty
          ? bill.payments.first.payBillItemName
          : null,
      expenseName: bill.expenseName,
      vendor: bill.vendorName?.isNotEmpty == true ? bill.vendorName! : 'Unknown',
      type: 'Bill',
      amount: bill.totalAmount ?? 0.0,
      status: bill.status.label.isEmpty ? '—' : bill.status.label,
    );
  }

  factory OverviewTransaction.fromBillPayment(
    BillPayment payment,
    String vendorName, {
    String? expenseName,
  }) {
    final resolvedReference = payment.referenceNo ?? payment.id;
    return OverviewTransaction(
      id: payment.id,
      date: payment.date ?? DateTime.now(),
      number: (resolvedReference == null || resolvedReference.isEmpty) ? '—' : resolvedReference,
      name: payment.payBillItemName,
      expenseName: expenseName,
      vendor: vendorName.isEmpty ? 'Unknown' : vendorName,
      type: 'Bill',
      amount: payment.amount ?? 0.0,
      status: 'Paid',
      paymentMode: 'Bank Transfer',
    );
  }

  factory OverviewTransaction.fromPurchaseOrder(PurchaseOrder po) {
    return OverviewTransaction(
      id: po.id,
      date: po.orderDate ?? DateTime.now(),
      number: po.number.isEmpty ? '—' : po.number,
      name: po.name.isEmpty ? null : po.name,
      vendor: po.vendorName.isEmpty ? 'Unknown' : po.vendorName,
      type: 'Purchase Order',
      amount: po.totalAmount ?? 0.0,
      status: _mapDeliveryStatus(po.deliveryStatus),
    );
  }

  factory OverviewTransaction.fromPurchaseOrderPayment(
    PurchaseOrderPayment payment,
    String poNumber,
    String vendorName, {
    String? purchaseOrderName,
  }) {
    return OverviewTransaction(
      id: payment.id ?? '',
      date: payment.date ?? DateTime.now(),
      number: (payment.reference.isEmpty) ? '—' : payment.reference,
      name: purchaseOrderName,
      vendor: vendorName.isEmpty ? 'Unknown' : vendorName,
      type: 'Purchase Order',
      amount: payment.amountValue ?? 0.0,
      status: 'Paid',
      paymentMode: _emptyToNull(payment.paymentModeName ?? payment.method),
    );
  }

  static String _mapDeliveryStatus(int status) {
    switch (status) {
      case 0:
        return 'Undelivered';
      case 1:
        return 'Delivered';
      case 2:
        return 'Shipping';
      default:
        return 'Status $status';
    }
  }

  static String? _emptyToNull(String? value) {
    if (value == null || value.trim().isEmpty || value == '—') {
      return null;
    }
    return value;
  }
}
