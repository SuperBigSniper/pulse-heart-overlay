typedef BleSubscription = Future<void> Function();

/// Tries notifications first, then falls back to indications.
///
/// Some heart-rate characteristics advertise Notify but only accept
/// Indicate in practice, so the first subscription mode is not enough to
/// determine which one the device will actually enable.
Future<void> subscribeNotifyThenIndicate({
  required BleSubscription subscribeNotify,
  required BleSubscription subscribeIndicate,
  void Function(Object error)? onNotifyFailure,
}) async {
  Object? notifyError;
  try {
    await subscribeNotify();
    return;
  } on Object catch (error) {
    notifyError = error;
    onNotifyFailure?.call(error);
  }

  try {
    await subscribeIndicate();
  } on Object catch (indicateError) {
    throw Exception(
      '无法订阅心率实时数据：'
      'Notify 失败 ($notifyError)，Indicate 失败 ($indicateError)',
    );
  }
}
