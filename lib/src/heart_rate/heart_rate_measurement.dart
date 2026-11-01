class HeartRateMeasurement {
  const HeartRateMeasurement({
    required this.beatsPerMinute,
    this.rrIntervalsMs = const [],
    this.energyExpended,
    this.sensorContactDetected,
  });

  final int beatsPerMinute;
  final List<double> rrIntervalsMs;
  final int? energyExpended;
  final bool? sensorContactDetected;

  static HeartRateMeasurement? tryParse(List<int> bytes) {
    if (bytes.length < 2) {
      return null;
    }

    final flags = bytes[0];
    final usesUint16 = (flags & 0x01) != 0;
    var offset = 1;

    final int beatsPerMinute;
    if (usesUint16) {
      if (bytes.length < 3) {
        return null;
      }
      beatsPerMinute = bytes[1] | (bytes[2] << 8);
      offset = 3;
    } else {
      beatsPerMinute = bytes[1];
      offset = 2;
    }

    if (beatsPerMinute <= 0 || beatsPerMinute > 300) {
      return null;
    }

    final sensorContactSupported = (flags & 0x04) != 0;
    final bool? sensorContactDetected = sensorContactSupported
        ? (flags & 0x02) != 0
        : null;

    int? energyExpended;
    if ((flags & 0x08) != 0) {
      if (bytes.length < offset + 2) {
        return null;
      }
      energyExpended = bytes[offset] | (bytes[offset + 1] << 8);
      offset += 2;
    }

    final rrIntervals = <double>[];
    if ((flags & 0x10) != 0) {
      while (offset + 1 < bytes.length) {
        final rawRrInterval = bytes[offset] | (bytes[offset + 1] << 8);
        final milliseconds = rawRrInterval * 1000 / 1024;
        if (milliseconds >= 100 && milliseconds <= 4000) {
          rrIntervals.add(milliseconds);
        }
        offset += 2;
      }
    }

    return HeartRateMeasurement(
      beatsPerMinute: beatsPerMinute,
      rrIntervalsMs: List.unmodifiable(rrIntervals),
      energyExpended: energyExpended,
      sensorContactDetected: sensorContactDetected,
    );
  }
}
