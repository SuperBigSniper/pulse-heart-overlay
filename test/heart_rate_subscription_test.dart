import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/heart_rate/heart_rate_subscription.dart';

void main() {
  test('uses notifications when the device accepts them', () async {
    var notifyCalls = 0;
    var indicateCalls = 0;

    await subscribeNotifyThenIndicate(
      subscribeNotify: () async {
        notifyCalls++;
      },
      subscribeIndicate: () async {
        indicateCalls++;
      },
    );

    expect(notifyCalls, 1);
    expect(indicateCalls, 0);
  });

  test('falls back to indications when notifications fail', () async {
    var notifyCalls = 0;
    var indicateCalls = 0;
    Object? notifyFailure;

    await subscribeNotifyThenIndicate(
      subscribeNotify: () async {
        notifyCalls++;
        throw StateError('notify rejected');
      },
      subscribeIndicate: () async {
        indicateCalls++;
      },
      onNotifyFailure: (error) => notifyFailure = error,
    );

    expect(notifyCalls, 1);
    expect(indicateCalls, 1);
    expect(notifyFailure, isA<StateError>());
  });

  test('reports both failures when indications also fail', () async {
    await expectLater(
      subscribeNotifyThenIndicate(
        subscribeNotify: () async {
          throw StateError('notify rejected');
        },
        subscribeIndicate: () async {
          throw StateError('indicate rejected');
        },
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          allOf(contains('Notify'), contains('Indicate')),
        ),
      ),
    );
  });
}
