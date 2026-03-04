import 'package:flutter_test/flutter_test.dart';
import 'package:kokonuts_bookkeeping/screens/accounts_tab.dart';
import 'package:kokonuts_bookkeeping/services/accounts_service.dart';

Account _account({required String typeName, required String primaryBalance}) {
  return Account(
    id: '1',
    name: 'Test',
    parentAccountId: null,
    typeName: typeName,
    detailTypeName: null,
    balance: primaryBalance,
    primaryBalance: primaryBalance,
    isActive: true,
  );
}

void main() {
  group('accountPrimaryBalanceTextForDisplay', () {
    test('keeps debit-normal assets positive for debit balance', () {
      final account = _account(typeName: 'Current assets', primaryBalance: '30000');

      expect(accountPrimaryBalanceTextForDisplay(account), '30000.00');
    });

    test('flips debit-normal assets sign when api returns negative debit balance', () {
      final account = _account(typeName: 'Current assets', primaryBalance: '-38.49');

      expect(accountPrimaryBalanceTextForDisplay(account), '38.49');
    });

    test('flips credit-normal liabilities sign for display', () {
      final account = _account(typeName: 'Non-current liabilities', primaryBalance: '-30000');

      expect(accountPrimaryBalanceTextForDisplay(account), '30000.00');
    });

    test('flips credit-normal revenue sign for display', () {
      final account = _account(typeName: 'Revenue', primaryBalance: '-1452.1');

      expect(accountPrimaryBalanceTextForDisplay(account), '1452.10');
    });

    test('keeps debit-normal expenses sign unchanged', () {
      final account = _account(typeName: 'Expenses', primaryBalance: '102.6');

      expect(accountPrimaryBalanceTextForDisplay(account), '102.60');
    });
  });
}
