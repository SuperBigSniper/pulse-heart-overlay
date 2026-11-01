import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/heart_rate/heart_rate_measurement.dart';

void main() {
  group('HeartRateMeasurement.tryParse', () {
    test('parses an 8-bit heart rate', () {
      final measurement = HeartRateMeasurement.tryParse(
        Uint8List.fromList([0x00, 72]),
      );

      expect(measurement, isNotNull);
      expect(measurement!.beatsPerMinute, 72);
      expect(measurement.sensorContactDetected, isNull);
    });

    test('parses a 16-bit heart rate and sensor contact', () {
      final measurement = HeartRateMeasurement.tryParse(
        Uint8List.fromList([0x07, 0x2C, 0x01]),
      );

      expect(measurement, isNotNull);
      expect(measurement!.beatsPerMinute, 300);
      expect(measurement.sensorContactDetected, isTrue);
    });

    test('parses energy expended and R-R intervals', () {
      final measurement = HeartRateMeasurement.tryParse(
        Uint8List.fromList([0x1E, 0x54, 0x64, 0x00, 0x00, 0x04, 0x00, 0x05]),
      );

      expect(measurement, isNotNull);
      expect(measurement!.beatsPerMinute, 84);
      expect(measurement.energyExpended, 100);
      expect(measurement.sensorContactDetected, isTrue);
      expect(measurement.rrIntervalsMs, hasLength(2));
      expect(measurement.rrIntervalsMs.first, closeTo(1000, 0.01));
      expect(measurement.rrIntervalsMs.last, closeTo(1250, 0.01));
    });

    test('rejects malformed or implausible values', () {
      expect(HeartRateMeasurement.tryParse([0x01, 0x2C]), isNull);
      expect(HeartRateMeasurement.tryParse([0x00, 0x00]), isNull);
      expect(HeartRateMeasurement.tryParse([0x01, 0x2D, 0x01]), isNull);
    });
  });
}
