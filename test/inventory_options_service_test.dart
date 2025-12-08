import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kokonuts_bookkeeping/services/inventory_options_service.dart';

void main() {
  test('fetchLotNumberSettings returns prefix and integer lot number', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/option/lot_number_prefix')) {
        return http.Response(jsonEncode({'value': 'ABC'}), 200);
      }
      if (request.url.path.endsWith('/option/next_lot_number')) {
        return http.Response(jsonEncode({'value': '38'}), 200);
      }
      return http.Response('Not Found', 404);
    });

    final service = InventoryOptionsService(client: client);
    final settings =
        await service.fetchLotNumberSettings(headers: const <String, String>{});

    expect(settings.prefix, 'ABC');
    expect(settings.nextLotNumber, 38);
  });

  test('fetchLotNumberSettings reads nested option values', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/option/lot_number_prefix')) {
        return http.Response(
          jsonEncode({
            'status': true,
            'result': {
              'id': '682',
              'name': 'lot_number_prefix',
              'value': 'LOT',
              'autoload': '1',
            },
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/option/next_lot_number')) {
        return http.Response(
          jsonEncode({
            'status': true,
            'result': {
              'id': '683',
              'name': 'next_lot_number',
              'value': '98',
              'autoload': '1',
            },
          }),
          200,
        );
      }
      return http.Response('Not Found', 404);
    });

    final service = InventoryOptionsService(client: client);
    final settings =
        await service.fetchLotNumberSettings(headers: const <String, String>{});

    expect(settings.prefix, 'LOT');
    expect(settings.nextLotNumber, 98);
  });

  test('fetchLotNumberSettings rejects non-numeric lot number', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/option/lot_number_prefix')) {
        return http.Response(jsonEncode({'value': 'ABC'}), 200);
      }
      if (request.url.path.endsWith('/option/next_lot_number')) {
        return http.Response(jsonEncode({'value': 'invalid'}), 200);
      }
      return http.Response('Not Found', 404);
    });

    final service = InventoryOptionsService(client: client);

    expect(
      () => service.fetchLotNumberSettings(headers: const <String, String>{}),
      throwsA(isA<InventoryOptionsException>()),
    );
  });
}
