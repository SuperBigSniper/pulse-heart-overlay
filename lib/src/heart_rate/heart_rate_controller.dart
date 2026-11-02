import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'heart_rate_measurement.dart';

enum MonitorStatus { idle, connecting, connected, disconnecting, error }

class HeartRateSample {
  const HeartRateSample({
    required this.beatsPerMinute,
    required this.recordedAt,
  });

  final int beatsPerMinute;
  final DateTime recordedAt;
}

class HeartRateSessionException implements Exception {
  const HeartRateSessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HeartRateController extends ChangeNotifier {
  static const heartRateServiceUuid = '180d';
  static const heartRateMeasurementUuid = '2a37';

  final Map<String, BleDevice> _scanResults = <String, BleDevice>{};
  final List<HeartRateSample> _history = <HeartRateSample>[];

  StreamSubscription<AvailabilityState>? _availabilitySubscription;
  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<Uint8List>? _valueSubscription;
  Timer? _scanTimer;
  Timer? _clockTimer;
  Timer? _demoTimer;

  BleDevice? _connectedDevice;
  BleDevice? _pendingDevice;
  BleCharacteristic? _heartRateCharacteristic;
  AvailabilityState _availability = AvailabilityState.unknown;
  MonitorStatus _status = MonitorStatus.idle;
  DateTime? _sessionStartedAt;
  DateTime? _lastReadingAt;
  String? _errorMessage;
  int? _currentBpm;
  int? _minimumBpm;
  int? _maximumBpm;
  double? _latestRrIntervalMs;
  bool? _sensorContactDetected;
  bool _initialized = false;
  bool _isScanning = false;
  bool _scanHeartRateOnly = true;
  bool _isDemo = false;
  bool _manualDisconnect = false;
  bool _disposed = false;
  int _demoTick = 0;

  AvailabilityState get availability => _availability;
  MonitorStatus get status => _status;
  bool get isScanning => _isScanning;
  bool get isDemo => _isDemo;
  bool get isBusy =>
      _status == MonitorStatus.connecting ||
      _status == MonitorStatus.disconnecting;
  bool get hasReading => _currentBpm != null;
  bool get bluetoothReady => _availability == AvailabilityState.poweredOn;
  bool get usingHeartRateFilter => _scanHeartRateOnly;
  BleDevice? get connectedDevice => _connectedDevice;
  String? get errorMessage => _errorMessage;
  DateTime? get sessionStartedAt => _sessionStartedAt;
  DateTime? get lastReadingAt => _lastReadingAt;
  int? get currentBpm => _currentBpm;
  int? get minimumBpm => _minimumBpm;
  int? get maximumBpm => _maximumBpm;
  double? get latestRrIntervalMs => _latestRrIntervalMs;
  bool? get sensorContactDetected => _sensorContactDetected;
  List<HeartRateSample> get history => List.unmodifiable(_history);

  bool get readingIsStale {
    final lastReadingAt = _lastReadingAt;
    if (lastReadingAt == null) {
      return true;
    }
    return DateTime.now().difference(lastReadingAt).inSeconds > 8;
  }

  int? get averageBpm {
    if (_history.isEmpty) {
      return null;
    }
    final total = _history.fold<int>(
      0,
      (sum, sample) => sum + sample.beatsPerMinute,
    );
    return (total / _history.length).round();
  }

  List<BleDevice> get scanDevices {
    final devices = _scanResults.values.toList();
    devices.sort((left, right) {
      final leftSupportsHeartRate = _advertisesHeartRate(left);
      final rightSupportsHeartRate = _advertisesHeartRate(right);
      if (leftSupportsHeartRate != rightSupportsHeartRate) {
        return leftSupportsHeartRate ? -1 : 1;
      }
      return (right.rssi ?? -127).compareTo(left.rssi ?? -127);
    });
    return devices;
  }

  String get statusLabel {
    if (_isDemo) {
      return '演示模式';
    }
    return switch (_status) {
      MonitorStatus.idle => '未连接',
      MonitorStatus.connecting => '正在连接',
      MonitorStatus.connected => readingIsStale ? '等待数据' : '正在接收',
      MonitorStatus.disconnecting => '正在断开',
      MonitorStatus.error => '连接中断',
    };
  }

  String get availabilityLabel {
    return switch (_availability) {
      AvailabilityState.poweredOn => '蓝牙已开启',
      AvailabilityState.poweredOff => '蓝牙已关闭',
      AvailabilityState.unauthorized => '蓝牙权限未开启',
      AvailabilityState.unsupported => '当前设备不支持蓝牙',
      AvailabilityState.resetting => '蓝牙正在重置',
      AvailabilityState.unknown => '正在检查蓝牙',
    };
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _availabilitySubscription = UniversalBle.availabilityStream.listen(
      _handleAvailabilityChange,
    );
    _scanSubscription = UniversalBle.scanStream.listen(
      _handleScanResult,
      onError: (Object error) {
        _setError('扫描失败：${_readableError(error)}');
      },
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status == MonitorStatus.connected || _isDemo) {
        _notify();
      }
    });

    await _refreshAvailability();
  }

  Future<void> refreshAvailability() => _refreshAvailability();

  Future<void> startScan({required bool heartRateOnly}) async {
    if (isBusy) {
      return;
    }
    if (_isScanning) {
      await stopScan(notify: false);
    }

    _errorMessage = null;
    _scanHeartRateOnly = heartRateOnly;
    _scanResults.clear();
    _isScanning = true;
    _notify();

    try {
      await UniversalBle.requestPermissions();
      await _refreshAvailability();
      if (_availability != AvailabilityState.poweredOn) {
        throw HeartRateSessionException(availabilityLabel);
      }

      await UniversalBle.startScan(
        scanFilter: heartRateOnly
            ? ScanFilter(withServices: const [heartRateServiceUuid])
            : null,
        skipDuplicates: true,
      );

      if (defaultTargetPlatform != TargetPlatform.windows) {
        try {
          final systemDevices = await UniversalBle.getSystemDevices(
            withServices: heartRateOnly
                ? const [heartRateServiceUuid]
                : const [],
          );
          for (final device in systemDevices) {
            _addScanResult(device);
          }
        } on Object {
          // System devices are an optional shortcut; a live scan still works.
        }
      }

      _scanTimer?.cancel();
      _scanTimer = Timer(const Duration(seconds: 14), () {
        unawaited(stopScan());
      });
      _notify();
    } on Object catch (error) {
      _isScanning = false;
      _setError(_scanError(error));
    }
  }

  Future<void> stopScan({bool notify = true}) async {
    _scanTimer?.cancel();
    _scanTimer = null;
    final wasScanning = _isScanning;
    _isScanning = false;

    if (wasScanning) {
      try {
        await UniversalBle.stopScan();
      } on Object {
        // The radio may already be off or the app may be shutting down.
      }
    }
    if (notify) {
      _notify();
    }
  }

  Future<bool> connect(BleDevice device) async {
    if (_isDemo) {
      _stopDemo(notify: false);
    }
    if (isBusy) {
      return false;
    }

    await stopScan(notify: false);
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    await _disconnectTransport(showStatus: false);
    _clearMeasurement();
    _errorMessage = null;
    _status = MonitorStatus.connecting;
    _pendingDevice = device;
    _manualDisconnect = false;
    _notify();

    try {
      await UniversalBle.requestPermissions();
      final characteristic = await _openHeartRateSession(device);
      _heartRateCharacteristic = characteristic;
      _valueSubscription = characteristic.onValueReceived.listen(
        _handleHeartRateValue,
        onError: (Object error) {
          _setError('心率数据读取失败：${_readableError(error)}');
        },
      );

      _connectedDevice = device;
      _pendingDevice = null;
      _status = MonitorStatus.connected;
      _sessionStartedAt = DateTime.now();
      _connectionSubscription = UniversalBle.connectionStream(device.deviceId)
          .listen(_handleConnectionChange);
      _notify();

      unawaited(_readInitialValue(characteristic));
      return true;
    } on Object catch (error) {
      await _disconnectTransport(showStatus: false);
      _pendingDevice = null;
      _status = MonitorStatus.error;
      _errorMessage = _connectionError(error);
      _notify();
      return false;
    }
  }

  Future<BleCharacteristic> _openHeartRateSession(BleDevice device) async {
    try {
      return await _connectAndSubscribe(device);
    } on Object catch (error) {
      if (!isBluetoothAccessDenied(error)) {
        rethrow;
      }

      // Windows often keeps a GATT session open after a failed discovery.
      // Fully disconnect, wait, then retry once before surfacing AccessDenied.
      await _disconnectTransport(showStatus: false);
      _pendingDevice = device;
      await Future<void>.delayed(const Duration(milliseconds: 900));
      return _connectAndSubscribe(device);
    }
  }

  Future<BleCharacteristic> _connectAndSubscribe(BleDevice device) async {
    await UniversalBle.connect(
      device.deviceId,
      timeout: const Duration(seconds: 20),
    );
    final services = await device.discoverServices(
      timeout: const Duration(seconds: 20),
    );
    final heartRateService = services.where(
      (service) =>
          BleUuidParser.compareStrings(service.uuid, heartRateServiceUuid),
    );
    if (heartRateService.isEmpty) {
      throw const HeartRateSessionException(
        '该设备没有提供标准心率服务（0x180D），可能使用厂商私有协议。',
      );
    }

    final characteristic = heartRateService.first.getCharacteristic(
      heartRateMeasurementUuid,
    );
    final supportsNotify = characteristic.properties.contains(
      CharacteristicProperty.notify,
    );
    final supportsIndicate = characteristic.properties.contains(
      CharacteristicProperty.indicate,
    );
    if (!supportsNotify && !supportsIndicate) {
      throw const HeartRateSessionException('心率特征不支持实时通知。');
    }

    var subscribed = false;
    if (supportsNotify) {
      try {
        await characteristic.notifications.subscribe();
        subscribed = true;
      } on Object {
        // Some devices advertise both modes but only accept indications.
      }
    }
    if (!subscribed && supportsIndicate) {
      await characteristic.indications.subscribe();
      subscribed = true;
    }
    if (!subscribed) {
      throw const HeartRateSessionException('无法订阅心率实时通知。');
    }
    return characteristic;
  }

  Future<void> disconnect() async {
    if (_isDemo) {
      _stopDemo();
      return;
    }
    if (_connectedDevice == null &&
        _status != MonitorStatus.connecting &&
        _status != MonitorStatus.error) {
      return;
    }

    _status = MonitorStatus.disconnecting;
    _manualDisconnect = true;
    _notify();
    await _disconnectTransport(showStatus: false);
    _status = MonitorStatus.idle;
    _errorMessage = null;
    _notify();
  }

  Future<void> toggleDemo() async {
    if (_isDemo) {
      _stopDemo();
      return;
    }
    if (_connectedDevice != null || isBusy) {
      await disconnect();
    }
    _startDemo();
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    _notify();
  }

  Future<void> _refreshAvailability() async {
    try {
      _availability = await UniversalBle.getBluetoothAvailabilityState();
    } on Object {
      _availability = AvailabilityState.unknown;
    }
    _notify();
  }

  void _handleAvailabilityChange(AvailabilityState availability) {
    _availability = availability;
    if (availability != AvailabilityState.poweredOn && _isScanning) {
      unawaited(stopScan(notify: false));
    }
    _notify();
  }

  void _handleScanResult(BleDevice device) {
    if (!_isScanning) {
      return;
    }
    _addScanResult(device);
  }

  void _addScanResult(BleDevice device) {
    final existing = _scanResults[device.deviceId];
    if (existing == null ||
        (device.rssi ?? -127) > (existing.rssi ?? -127) ||
        (device.name?.isNotEmpty ?? false)) {
      _scanResults[device.deviceId] = device;
      _notify();
    }
  }

  Future<void> _readInitialValue(BleCharacteristic characteristic) async {
    try {
      final value = await characteristic.read(
        timeout: const Duration(seconds: 6),
      );
      _handleHeartRateValue(value);
    } on Object {
      // Not every heart-rate characteristic is readable; notifications remain
      // the primary data source.
    }
  }

  void _handleHeartRateValue(Uint8List value) {
    final measurement = HeartRateMeasurement.tryParse(value);
    if (measurement == null) {
      return;
    }

    _currentBpm = measurement.beatsPerMinute;
    _minimumBpm = math.min(
      _minimumBpm ?? measurement.beatsPerMinute,
      measurement.beatsPerMinute,
    );
    _maximumBpm = math.max(
      _maximumBpm ?? measurement.beatsPerMinute,
      measurement.beatsPerMinute,
    );
    if (measurement.rrIntervalsMs.isNotEmpty) {
      _latestRrIntervalMs = measurement.rrIntervalsMs.last;
    }
    _sensorContactDetected = measurement.sensorContactDetected;
    _lastReadingAt = DateTime.now();
    _history.add(
      HeartRateSample(
        beatsPerMinute: measurement.beatsPerMinute,
        recordedAt: _lastReadingAt!,
      ),
    );
    if (_history.length > 180) {
      _history.removeRange(0, _history.length - 180);
    }
    _notify();
  }

  void _handleConnectionChange(bool connected) {
    if (connected || _status != MonitorStatus.connected || _manualDisconnect) {
      return;
    }
    unawaited(_handleUnexpectedDisconnect());
  }

  Future<void> _handleUnexpectedDisconnect() async {
    await _disconnectTransport(showStatus: false);
    _status = MonitorStatus.error;
    _errorMessage = '手环连接已断开，请重新连接。';
    _notify();
  }

  Future<void> _disconnectTransport({required bool showStatus}) async {
    final device = _connectedDevice ?? _pendingDevice;
    if (showStatus && device != null) {
      _status = MonitorStatus.disconnecting;
      _notify();
    }

    await _valueSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _valueSubscription = null;
    _connectionSubscription = null;

    final characteristic = _heartRateCharacteristic;
    if (characteristic != null) {
      try {
        await characteristic.unsubscribe();
      } on Object {
        // The peripheral may already be gone.
      }
    }
    _heartRateCharacteristic = null;

    if (device != null) {
      try {
        await UniversalBle.disconnect(
          device.deviceId,
          timeout: const Duration(seconds: 8),
        );
      } on Object {
        // Disconnect is best effort during failure and shutdown paths.
      }
    }

    _connectedDevice = null;
    _pendingDevice = null;
    _clearMeasurement();
  }

  void _startDemo() {
    _isDemo = true;
    _status = MonitorStatus.idle;
    _errorMessage = null;
    _clearMeasurement();
    _sessionStartedAt = DateTime.now();
    _demoTick = 0;
    _recordDemoBeat();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      _recordDemoBeat();
    });
    _notify();
  }

  void _recordDemoBeat() {
    final phase = _demoTick / 16 * math.pi * 2;
    final bpm = (84 + math.sin(phase) * 34).round().clamp(50, 118);
    final rrIntervalMs = 60000 / bpm;
    _demoTick++;
    _handleHeartRateValue(Uint8List.fromList(<int>[0x06, bpm, 0, 0]));
    _latestRrIntervalMs = rrIntervalMs;
    _sensorContactDetected = true;
  }

  void _stopDemo({bool notify = true}) {
    _demoTimer?.cancel();
    _demoTimer = null;
    _isDemo = false;
    _status = MonitorStatus.idle;
    _clearMeasurement();
    if (notify) {
      _notify();
    }
  }

  void _clearMeasurement() {
    _currentBpm = null;
    _minimumBpm = null;
    _maximumBpm = null;
    _latestRrIntervalMs = null;
    _sensorContactDetected = null;
    _lastReadingAt = null;
    _sessionStartedAt = null;
    _history.clear();
  }

  void _setError(String message) {
    _errorMessage = message;
    _notify();
  }

  String _scanError(Object error) {
    if (error is HeartRateSessionException) {
      return error.message;
    }
    return '无法开始扫描：${_readableError(error)}';
  }

  String _connectionError(Object error) {
    if (error is HeartRateSessionException) {
      return error.message;
    }
    if (isBluetoothAccessDenied(error)) {
      return bluetoothAccessDeniedGuidance();
    }
    final message = _readableError(error);
    if (message.toLowerCase().contains('timeout')) {
      return '连接超时，请让手环靠近电脑后重试。';
    }
    return '连接失败：$message';
  }

  String _readableError(Object error) {
    final text = error.toString();
    return text
        .replaceFirst('Exception: ', '')
        .replaceFirst('ConnectionException: ', '')
        .replaceFirst('UniversalBleException: ', '');
  }

  bool _advertisesHeartRate(BleDevice device) {
    return device.services.any(
      (service) => BleUuidParser.compareStrings(service, heartRateServiceUuid),
    );
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scanTimer?.cancel();
    _clockTimer?.cancel();
    _demoTimer?.cancel();
    unawaited(_availabilitySubscription?.cancel());
    unawaited(_scanSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    unawaited(_valueSubscription?.cancel());
    unawaited(_disconnectTransport(showStatus: false));
    super.dispose();
  }
}

bool advertisesHeartRateService(BleDevice device) {
  return device.services.any(
    (service) => BleUuidParser.compareStrings(
      service,
      HeartRateController.heartRateServiceUuid,
    ),
  );
}

bool isBluetoothAccessDenied(Object error) {
  if (error is UniversalBleException) {
    if (error.code == UniversalBleErrorCode.accessDenied ||
        error.code == UniversalBleErrorCode.bluetoothUnauthorized) {
      return true;
    }
  }
  final message = error.toString().toLowerCase();
  return message.contains('accessdenied') ||
      message.contains('access denied') ||
      message.contains('access is denied') ||
      message.contains('拒绝访问');
}

String bluetoothAccessDeniedGuidance() {
  return 'Windows 拒绝访问手环。请先在系统「设置 → 蓝牙和其他设备」中断开或'
      '忽略该手环，并关闭其他正在使用它的应用后重试。便携版不会弹出独立授权窗口。';
}
