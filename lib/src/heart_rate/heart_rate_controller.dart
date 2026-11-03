import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

import 'heart_rate_measurement.dart';
import 'heart_rate_subscription.dart';
import 'windows_heart_rate_channel.dart';

enum MonitorStatus { idle, receiving, error }

/// Dumps every raw advertisement of the selected device to the console.
/// Off by default: advertisements arrive many times per second and flood
/// the output; enable only when debugging broadcast payloads.
const bool verboseAdvertisementLog = false;

class HeartRateSample {
  const HeartRateSample({
    required this.beatsPerMinute,
    required this.recordedAt,
  });

  final int beatsPerMinute;
  final DateTime recordedAt;
}

/// Receives heart rate from advertisements and the standard Heart Rate
/// Profile.
///
/// Scanning and measurement parsing are shared by desktop platforms. When the
/// selected device exposes 0x180D, the controller also opens a GATT session and
/// subscribes to 0x2A37. Windows hands that GATT session to the runner because
/// its native implementation can scope service discovery to the heart-rate
/// service; macOS uses universal_ble's CoreBluetooth-backed implementation.
class HeartRateController extends ChangeNotifier {
  static const heartRateServiceUuid = '180d';
  static const heartRateMeasurementUuid = '2a37';
  static const _lastDeviceIdKey = 'heartRate.lastDeviceId';
  static const _lastDeviceNameKey = 'heartRate.lastDeviceName';

  /// Bluetooth SIG company identifier advertised by Xiaomi bands.
  static const xiaomiCompanyId = 0x0157;

  /// Newer Xiaomi bands (8/10/11) expose "heart rate broadcast" through the
  /// standard Heart Rate Profile: the advertisement only carries the 180D
  /// UUID, the measurements arrive as GATT notifications on 2A37.
  /// The first connect performs a full GATT service discovery over the
  /// encrypted link; on Mi Band this (including the bulky HID service)
  /// regularly exceeds 12s, so keep a generous ceiling.
  static const _gattConnectTimeout = Duration(seconds: 30);
  static const _pairingTimeout = Duration(seconds: 30);
  static const _gattDisconnectTimeout = Duration(seconds: 8);
  static const _gattRetryMinimum = Duration(seconds: 2);
  static const _gattRetryMaximum = Duration(seconds: 60);

  final Map<String, BleDevice> _scanResults = <String, BleDevice>{};
  final List<HeartRateSample> _history = <HeartRateSample>[];

  /// Windows uses the runner's native heart rate channel, which scopes GATT
  /// discovery to 0x180D/0x2A37 and never touches the protected HID service.
  static final bool _useWindowsHeartLink = !kIsWeb && Platform.isWindows;
  final WindowsHeartRateChannel? _windowsHeartLink = _useWindowsHeartLink
      ? WindowsHeartRateChannel()
      : null;
  StreamSubscription<WindowsHeartLinkEvent>? _windowsLinkSubscription;

  StreamSubscription<AvailabilityState>? _availabilitySubscription;
  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<Uint8List>? _measurementSubscription;
  StreamSubscription<BleConnectionChange>? _gattConnectionSubscription;
  Timer? _scanTimer;
  Timer? _clockTimer;
  Timer? _demoTimer;
  Timer? _gattRetryTimer;
  Duration _gattRetryDelay = _gattRetryMinimum;
  bool _gattBusy = false;
  bool _gattConnected = false;
  int _gattAttemptGeneration = 0;
  bool _pairingRequested = false;
  DateTime? _lastGattSkipLogAt;
  String _lastGattSkipReason = '';

  BleDevice? _selectedDevice;
  String? _lastDeviceId;
  String? _lastDeviceName;
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
  bool _disposed = false;
  int _demoTick = 0;
  String _lastUnparsedAdvSignature = '';
  DateTime? _lastAdvLogAt;
  int _suppressedAdvLogs = 0;
  DateTime? _lastParseLogAt;

  AvailabilityState get availability => _availability;
  MonitorStatus get status => _status;
  bool get isScanning => _isScanning;
  bool get isDemo => _isDemo;
  bool get hasReading => _currentBpm != null;
  bool get bluetoothReady => _availability == AvailabilityState.poweredOn;
  BleDevice? get selectedDevice => _selectedDevice;
  String? get errorMessage => _errorMessage;
  DateTime? get sessionStartedAt => _sessionStartedAt;
  DateTime? get lastReadingAt => _lastReadingAt;
  int? get currentBpm => _currentBpm;
  int? get minimumBpm => _minimumBpm;
  int? get maximumBpm => _maximumBpm;
  double? get latestRrIntervalMs => _latestRrIntervalMs;
  bool? get sensorContactDetected => _sensorContactDetected;
  List<HeartRateSample> get history => List.unmodifiable(_history);

  /// The most recently used device, reconstructed from persisted state.
  BleDevice? get lastDevice {
    final id = _lastDeviceId;
    if (id == null) {
      return null;
    }
    return BleDevice(deviceId: id, name: _lastDeviceName);
  }

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
      MonitorStatus.idle => '未选择设备',
      MonitorStatus.receiving => readingIsStale ? '等待广播数据' : '正在接收',
      MonitorStatus.error => '接收中断',
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
    final windowsHeartLink = _windowsHeartLink;
    if (windowsHeartLink != null) {
      _windowsLinkSubscription = windowsHeartLink.events.listen(
        _handleWindowsLinkEvent,
      );
    }
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // The selected device is only reachable through its advertisements,
      // so keep the scan alive whenever it drops for any reason.
      if (_selectedDevice != null &&
          !_isDemo &&
          !_isScanning &&
          !_gattConnected &&
          _availability == AvailabilityState.poweredOn) {
        unawaited(_startPersistentScan());
      }
      if (_selectedDevice != null &&
          !_isDemo &&
          _status == MonitorStatus.receiving &&
          readingIsStale) {
        _logStaleWatchdog();
      }
      if (_status == MonitorStatus.receiving || _isDemo) {
        _notify();
      }
    });

    try {
      final preferences = await SharedPreferences.getInstance();
      _lastDeviceId = preferences.getString(_lastDeviceIdKey);
      _lastDeviceName = preferences.getString(_lastDeviceNameKey);
    } on Object {
      // Persistence is optional; scanning still works without it.
    }

    await _refreshAvailability();
    if (_lastDeviceId != null && _availability == AvailabilityState.poweredOn) {
      // Restore the previous session hands-free: selecting the device is
      // enough, its broadcasts carry the readings.
      unawaited(selectDevice(lastDevice!));
    }
  }

  Future<void> refreshAvailability() => _refreshAvailability();

  Future<void> startScan({required bool heartRateOnly}) async {
    if (_isScanning) {
      await stopScan(notify: false);
    }

    _errorMessage = null;
    _scanResults.clear();
    final rememberedDevice = lastDevice;
    if (rememberedDevice != null) {
      // Some bands stop advertising after a GATT disconnect. Keep the last
      // device visible so it can still be reached by a direct GATT connection.
      _scanResults[rememberedDevice.deviceId] = rememberedDevice;
    }
    _scanHeartRateOnly = heartRateOnly;
    _isScanning = true;
    _notify();

    try {
      await _refreshAvailability();
      if (_availability != AvailabilityState.poweredOn) {
        throw Exception(availabilityLabel);
      }

      // Scan without a platform service filter. Some bands stop advertising
      // 0x180D after disconnect, and Xiaomi heart rate may only be present in
      // manufacturer data. Filter candidates in Dart instead.
      await UniversalBle.startScan(skipDuplicates: true);

      // Without a selected device the scan is dialog-driven and stops after
      // a window; with one selected it must run continuously.
      if (_selectedDevice == null) {
        _scanTimer?.cancel();
        _scanTimer = Timer(const Duration(seconds: 14), () {
          unawaited(stopScan());
        });
      }
      _notify();
    } on Object catch (error) {
      _isScanning = false;
      _setError('无法开始扫描：${_readableError(error)}');
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

  /// Selects a band, starts persistent advertisement scanning, and opens the
  /// standard Heart Rate Profile session when the band exposes it.
  Future<void> selectDevice(BleDevice device) async {
    if (_isDemo) {
      _stopDemo(notify: false);
    }

    final previousDeviceId = _selectedDevice?.deviceId;
    await stopScan(notify: false);
    if (previousDeviceId != null) {
      await _releaseGattSession(previousDeviceId);
    }
    _selectedDevice = device;
    _pairingRequested = false;
    _status = MonitorStatus.receiving;
    _errorMessage = null;
    _clearMeasurement();
    _sessionStartedAt = DateTime.now();
    _notify();

    unawaited(_rememberDevice(device));
    await _startPersistentScan();
    // Bands that stream via the standard Heart Rate Profile need a GATT
    // link; broadcast-only bands keep working through the scan above.
    unawaited(_ensureGattSession());
  }

  /// Stops listening and clears the selection.
  Future<void> disconnect() async {
    if (_isDemo) {
      _stopDemo(notify: false);
    }
    if (_selectedDevice == null && _status != MonitorStatus.error) {
      return;
    }

    final deviceId = _selectedDevice?.deviceId;
    await stopScan(notify: false);
    await _releaseGattSession(deviceId);
    _pairingRequested = false;
    _selectedDevice = null;
    _status = MonitorStatus.idle;
    _errorMessage = null;
    _clearMeasurement();
    _notify();
  }

  Future<void> toggleDemo() async {
    if (_isDemo) {
      _stopDemo();
      await _resumeSelectedDevice();
      return;
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

  Future<void> _startPersistentScan() async {
    if (_disposed ||
        _isScanning ||
        _availability != AvailabilityState.poweredOn) {
      return;
    }
    _isScanning = true;
    _notify();

    try {
      // Unfiltered: the heart rate may arrive in the 180D service data or in
      // the Xiaomi manufacturer payload, and the filter must not drop either.
      // skipDuplicates must stay off here: a band whose BPM holds steady
      // re-broadcasts byte-identical packets, and deduplication would silence
      // them until the reading goes stale and the animation stops.
      await UniversalBle.startScan(skipDuplicates: false);
      _log('persistent scan started for ${_selectedDevice?.deviceId}');
    } on Object catch (error) {
      _isScanning = false;
      _setError('无法开始扫描：${_readableError(error)}');
      return;
    }
    _notify();
  }

  /// Opens the standard Heart Rate Profile session for the selected band:
  /// connect → discover 180D → subscribe to 2A37 notifications.
  ///
  /// Safe to call repeatedly: while a session is up, an attempt is in
  /// flight, or a retry is pending, the call returns without doing anything.
  Future<void> _ensureGattSession() async {
    final selected = _selectedDevice;
    if (_disposed ||
        _isDemo ||
        selected == null ||
        _gattBusy ||
        _gattConnected ||
        _gattRetryTimer?.isActive == true ||
        _availability != AvailabilityState.poweredOn) {
      _logGattSkip();
      return;
    }
    _gattBusy = true;
    final generation = ++_gattAttemptGeneration;
    _lastGattSkipLogAt = null;

    // Windows: hand the whole GATT session to the runner's native channel.
    // It only enumerates 0x180D/0x2A37, so the protected HID service is never
    // touched and bonding is not needed merely to enumerate HID. _gattBusy
    // stays true until a ready/error event arrives.
    if (_useWindowsHeartLink) {
      _log('native gatt connect attempt for ${selected.deviceId}');
      try {
        await _windowsHeartLink!.subscribe(selected.deviceId);
      } on Object catch (error) {
        if (generation == _gattAttemptGeneration) {
          _gattBusy = false;
          _log('native subscribe failed: ${_readableError(error)}');
          _scheduleGattRetry();
        }
      }
      return;
    }

    _log(
      'gatt connect attempt '
      '(pairingRequested=$_pairingRequested)',
    );
    try {
      try {
        await UniversalBle.connect(
          selected.deviceId,
          timeout: _gattConnectTimeout,
        );
      } on Object catch (error) {
        final message = _readableError(error);
        if (!_isCurrentGattAttempt(generation, selected.deviceId)) {
          rethrow;
        }
        // Windows: the band's protected HID service (1812) denies
        // characteristic enumeration until the device is bonded to the
        // OS, which aborts the plugin's connect-time service discovery.
        // Request system pairing once, then retry the connection.
        if (message.contains('AccessDenied') && !_pairingRequested) {
          _pairingRequested = true;
          _log(
            'connect blocked by protected service (1812), '
            'requesting system pairing — confirm the Windows prompt '
            'and the band screen if one appears',
          );
          await UniversalBle.pair(selected.deviceId, timeout: _pairingTimeout);
          if (!_isCurrentGattAttempt(generation, selected.deviceId)) {
            await _disconnectGatt(selected.deviceId);
            return;
          }
          _log('pairing done, retrying connect');
          await UniversalBle.connect(
            selected.deviceId,
            timeout: _gattConnectTimeout,
          );
        } else {
          rethrow;
        }
      }
      if (!_isCurrentGattAttempt(generation, selected.deviceId)) {
        await _disconnectGatt(selected.deviceId);
        return;
      }
      final services = await UniversalBle.discoverServices(selected.deviceId);
      if (!_isCurrentGattAttempt(generation, selected.deviceId)) {
        await _disconnectGatt(selected.deviceId);
        return;
      }
      BleService? heartRateService;
      BleCharacteristic? measurementCharacteristic;
      for (final service in services) {
        if (!BleUuidParser.compareStrings(service.uuid, heartRateServiceUuid)) {
          continue;
        }
        for (final characteristic in service.characteristics) {
          if (BleUuidParser.compareStrings(
            characteristic.uuid,
            heartRateMeasurementUuid,
          )) {
            heartRateService = service;
            measurementCharacteristic = characteristic;
            break;
          }
        }
        if (heartRateService != null) {
          break;
        }
      }
      if (heartRateService == null || measurementCharacteristic == null) {
        throw Exception('手环未提供 180D/2A37 心率特征');
      }

      final serviceUuid = heartRateService.uuid;
      final measurementUuid = measurementCharacteristic.uuid;
      await subscribeNotifyThenIndicate(
        subscribeNotify: () => UniversalBle.subscribeNotifications(
          selected.deviceId,
          serviceUuid,
          measurementUuid,
        ),
        subscribeIndicate: () => UniversalBle.subscribeIndications(
          selected.deviceId,
          serviceUuid,
          measurementUuid,
        ),
        onNotifyFailure: (error) {
          _log(
            'notify subscription failed, trying indications: '
            '${_readableError(error)}',
          );
        },
      );
      if (!_isCurrentGattAttempt(generation, selected.deviceId)) {
        await _disconnectGatt(selected.deviceId);
        return;
      }
      unawaited(_measurementSubscription?.cancel());
      _measurementSubscription =
          UniversalBle.characteristicValueStream(
            selected.deviceId,
            measurementUuid,
          ).listen(
            (value) {
              if (_isCurrentGattAttempt(generation, selected.deviceId)) {
                _handleMeasurementValue(value);
              }
            },
            onError: (Object error) {
              if (_isCurrentGattAttempt(generation, selected.deviceId)) {
                _log('measurement stream error: ${_readableError(error)}');
                _scheduleGattRetry();
              }
            },
          );
      unawaited(_gattConnectionSubscription?.cancel());
      _gattConnectionSubscription =
          UniversalBle.connectionChangeStream(selected.deviceId)
              .listen((change) {
                if (_isCurrentGattAttempt(generation, selected.deviceId)) {
                  _handleGattConnectionChange(change);
                }
              });

      _gattConnected = true;
      _gattRetryDelay = _gattRetryMinimum;
      // Connected: the band stops advertising and the scan is redundant.
      // The clock timer restarts scanning automatically if the link drops.
      await stopScan(notify: false);
      _log('gatt session ready, listening on 2A37');
      _notify();
    } on Object catch (error) {
      if (_isCurrentGattAttempt(generation, selected.deviceId)) {
        _log('gatt session failed: ${_readableError(error)}');
        _scheduleGattRetry();
      }
    } finally {
      if (generation == _gattAttemptGeneration) {
        _gattBusy = false;
      }
    }
  }

  bool _isCurrentGattAttempt(int generation, String deviceId) {
    return !_disposed &&
        _selectedDevice?.deviceId == deviceId &&
        generation == _gattAttemptGeneration;
  }

  Future<void> _releaseGattSession(String? deviceId) async {
    _gattAttemptGeneration++;
    _gattRetryTimer?.cancel();
    _gattRetryTimer = null;
    _gattBusy = false;
    _teardownGattSession();
    if (deviceId == null) {
      return;
    }
    if (_useWindowsHeartLink) {
      try {
        await _windowsHeartLink!.unsubscribe();
      } on Object catch (error) {
        _log('native unsubscribe failed: ${_readableError(error)}');
      }
    } else {
      await _disconnectGatt(deviceId);
    }
  }

  /// Explains why a GATT attempt was skipped, throttled so the per-second
  /// advertisement flow cannot flood the console while still surfacing a
  /// stuck state (e.g. pairing waiting for user consent).
  void _logGattSkip() {
    if (_disposed) {
      return;
    }
    String reason;
    if (_isDemo) {
      reason = 'demo';
    } else if (_selectedDevice == null) {
      reason = 'no selected device';
    } else if (_gattBusy) {
      reason = 'attempt already in flight (waiting for connect/pair?)';
    } else if (_gattConnected) {
      reason = 'already connected';
    } else if (_gattRetryTimer?.isActive == true) {
      reason =
          'retry backoff active (next attempt within '
          '${_gattRetryDelay.inSeconds}s)';
    } else if (_availability != AvailabilityState.poweredOn) {
      reason = 'bluetooth not ready';
    } else {
      reason = 'unknown guard';
    }
    final now = DateTime.now();
    final lastLogAt = _lastGattSkipLogAt;
    final reasonChanged = reason != _lastGattSkipReason;
    if (!reasonChanged &&
        lastLogAt != null &&
        now.difference(lastLogAt) < const Duration(seconds: 10)) {
      return;
    }
    _lastGattSkipLogAt = now;
    _lastGattSkipReason = reason;
    _log('gatt attempt skipped: $reason');
  }

  /// Events from the runner's native heart rate channel (Windows only).
  void _handleWindowsLinkEvent(WindowsHeartLinkEvent event) {
    if (_selectedDevice == null) {
      return;
    }
    final bytes = event.bytes;
    if (bytes != null) {
      _handleMeasurementValue(bytes);
      return;
    }
    switch (event.state) {
      case WindowsHeartLinkState.ready:
        _gattBusy = false;
        _gattConnected = true;
        _gattRetryDelay = _gattRetryMinimum;
        _lastGattSkipLogAt = null;
        _lastGattSkipReason = '';
        _log('native gatt session ready, listening on 2A37');
        // Connected: the band stops advertising and the scan is redundant.
        unawaited(stopScan(notify: false));
        _notify();
      case WindowsHeartLinkState.disconnected:
        _log(
          'native gatt link lost'
          '${event.detail == null || event.detail!.isEmpty ? '' : ': ${event.detail}'}',
        );
        _handleWindowsLinkDown();
      case WindowsHeartLinkState.error:
        _log('native gatt error: ${event.detail}');
        _handleWindowsLinkDown();
      case WindowsHeartLinkState.connecting:
        break;
      case null:
        break;
    }
  }

  void _handleWindowsLinkDown() {
    _gattBusy = false;
    _gattConnected = false;
    _scheduleGattRetry();
  }

  void _handleGattConnectionChange(BleConnectionChange change) {
    final selected = _selectedDevice;
    if (selected == null ||
        change.deviceId.toLowerCase() != selected.deviceId.toLowerCase()) {
      return;
    }
    if (change.isConnected || _gattConnected == change.isConnected) {
      return;
    }
    _log(
      'gatt link lost'
      '${change.error == null ? '' : ': ${change.error}'}',
    );
    _teardownGattSession();
    _scheduleGattRetry();
  }

  void _handleMeasurementValue(Uint8List value) {
    if (_isDemo) {
      return;
    }
    final measurement = HeartRateMeasurement.tryParse(value);
    if (measurement == null) {
      _log('unparsed measurement notification: ${_hexOf(value)}');
      return;
    }
    _logParsedMeasurement(measurement);
    _recordMeasurement(measurement);
  }

  void _scheduleGattRetry() {
    if (_disposed || _isDemo || _selectedDevice == null) {
      return;
    }
    _teardownGattSession();
    _gattRetryTimer?.cancel();
    _gattRetryTimer = Timer(_gattRetryDelay, () {
      unawaited(_ensureGattSession());
    });
    _log('gatt retry in ${_gattRetryDelay.inSeconds}s');
    final doubled = _gattRetryDelay * 2;
    _gattRetryDelay = doubled < _gattRetryMaximum ? doubled : _gattRetryMaximum;
    _notify();
  }

  void _teardownGattSession() {
    _gattConnected = false;
    // Native side is a no-op when no session is up.
    unawaited(_windowsHeartLink?.unsubscribe());
    unawaited(_measurementSubscription?.cancel());
    _measurementSubscription = null;
    unawaited(_gattConnectionSubscription?.cancel());
    _gattConnectionSubscription = null;
  }

  Future<void> _disconnectGatt(String deviceId) async {
    try {
      await UniversalBle.disconnect(deviceId, timeout: _gattDisconnectTimeout);
    } on Object catch (error) {
      // The link may already be gone; nothing to recover.
      _log('gatt disconnect failed: ${_readableError(error)}');
    }
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
    if (availability != _availability) {
      _log('availability: ${availability.name}');
    }
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

    final selected = _selectedDevice;
    if (selected != null) {
      if (device.deviceId == selected.deviceId) {
        // Fold the freshest advertisement data (name, RSSI) into the
        // selected device so the UI stays current.
        mergeBleDevice(selected, device);
        _logAdvertisement(device);
        _processAdvertisement(device);
        // Fresh advertisement means the band is reachable: (re)open the
        // GATT session unless one is already up or backing off.
        if (!_isDemo) {
          unawaited(_ensureGattSession());
        }
      }
    } else {
      _processAdvertisement(device);
    }
  }

  /// Dumps every raw advertisement from the selected device so broadcast
  /// reception can be verified straight from the console output.
  void _logAdvertisement(BleDevice device) {
    if (!verboseAdvertisementLog) {
      return;
    }
    final now = DateTime.now();
    final lastLogAt = _lastAdvLogAt;
    if (lastLogAt != null &&
        now.difference(lastLogAt) < const Duration(milliseconds: 800)) {
      // Keep counting so bursts still show up as a suppressed total.
      _suppressedAdvLogs++;
      return;
    }
    final suppressed = _suppressedAdvLogs;
    _suppressedAdvLogs = 0;
    _lastAdvLogAt = now;

    final serviceData = device.serviceData.entries
        .map((entry) => '${entry.key}=[${_hexOf(entry.value)}]')
        .join(' ');
    final manufacturerData = device.manufacturerDataList
        .map(
          (data) =>
              '0x${data.companyId.toRadixString(16).padLeft(4, '0')}='
              '[${_hexOf(data.payload)}]',
        )
        .join(' ');
    _log(
      'adv "${device.name ?? ''}" (${device.deviceId}) '
      'rssi=${device.rssi ?? '??'} '
      'services=${device.services.isEmpty ? '-' : device.services} '
      'serviceData=${serviceData.isEmpty ? '-' : serviceData} '
      'manufacturerData=${manufacturerData.isEmpty ? '-' : manufacturerData}'
      '${suppressed > 0 ? ' (+$suppressed suppressed)' : ''}',
    );
  }

  String _hexOf(List<int> bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  void _addScanResult(BleDevice device) {
    final selected = _selectedDevice;
    final isRelevant = selected == null
        ? !_scanHeartRateOnly || isHeartRateCandidate(device)
        : device.deviceId == selected.deviceId || _advertisesHeartRate(device);
    if (!isRelevant) {
      return;
    }

    final existing = _scanResults[device.deviceId];
    if (existing == null) {
      _scanResults[device.deviceId] = device;
      _notify();
      return;
    }
    if (mergeBleDevice(existing, device)) {
      _notify();
    }
  }

  void _processAdvertisement(BleDevice device) {
    if (_isDemo) {
      return;
    }
    final measurement = _extractMeasurement(device);
    if (measurement != null) {
      _logParsedMeasurement(measurement);
      _recordMeasurement(measurement);
    }
  }

  void _logParsedMeasurement(HeartRateMeasurement measurement) {
    final now = DateTime.now();
    final lastLogAt = _lastParseLogAt;
    if (lastLogAt != null &&
        now.difference(lastLogAt) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastParseLogAt = now;
    _log('parsed bpm=${measurement.beatsPerMinute}');
  }

  /// Reads the heart rate out of a broadcast payload.
  HeartRateMeasurement? _extractMeasurement(BleDevice device) {
    // Primary: 180D service data carrying a standard heart rate measurement.
    for (final entry in device.serviceData.entries) {
      if (BleUuidParser.compareStrings(entry.key, heartRateServiceUuid)) {
        final measurement = HeartRateMeasurement.tryParse(entry.value);
        if (measurement != null) {
          return measurement;
        }
      }
    }

    // Fallback: Xiaomi manufacturer payload (company 0x0157).
    for (final data in device.manufacturerDataList) {
      if (data.companyId != xiaomiCompanyId) {
        continue;
      }
      final bpm = _parseXiaomiHeartRate(data.payload);
      if (bpm != null) {
        return HeartRateMeasurement(beatsPerMinute: bpm);
      }
      _logUnparsedAdvertisement(device, data);
    }
    return null;
  }

  /// Parses the BPM out of Xiaomi's broadcast manufacturer payload.
  ///
  /// Observed layout (heart rate broadcast): `02 02 01 <bpm> ...` where the
  /// third byte marks "heart rate present" and the fourth byte is the BPM.
  int? _parseXiaomiHeartRate(List<int> payload) {
    if (payload.length >= 4 && payload[2] == 0x01) {
      final bpm = payload[3];
      if (bpm >= 30 && bpm <= 250) {
        return bpm;
      }
    }
    return null;
  }

  void _logUnparsedAdvertisement(BleDevice device, ManufacturerData data) {
    if (!verboseAdvertisementLog) {
      return;
    }
    final signature = '${device.deviceId}:${data.payloadRadix16}';
    if (signature == _lastUnparsedAdvSignature) {
      return;
    }
    _lastUnparsedAdvSignature = signature;
    _log(
      'unparsed Xiaomi advertisement from ${device.deviceId}: '
      '${data.payloadRadix16}',
    );
  }

  void _recordMeasurement(HeartRateMeasurement measurement) {
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
    if (_history.length == 1) {
      _log('first reading: bpm=${measurement.beatsPerMinute}');
    }
    _notify();
  }

  Future<void> _rememberDevice(BleDevice device) async {
    _lastDeviceId = device.deviceId;
    _lastDeviceName = device.name;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_lastDeviceIdKey, device.deviceId);
      final name = device.name;
      if (name != null && name.isNotEmpty) {
        await preferences.setString(_lastDeviceNameKey, name);
      } else {
        await preferences.remove(_lastDeviceNameKey);
      }
    } on Object {
      // Persistence is best effort; the session itself is unaffected.
    }
  }

  void _startDemo() {
    _gattRetryTimer?.cancel();
    _gattRetryTimer = null;
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
    _recordMeasurement(
      HeartRateMeasurement(beatsPerMinute: bpm, sensorContactDetected: true),
    );
    _latestRrIntervalMs = rrIntervalMs;
  }

  void _stopDemo({bool notify = true}) {
    _demoTimer?.cancel();
    _demoTimer = null;
    final hasSelectedDevice = _selectedDevice != null;
    _isDemo = false;
    _status = hasSelectedDevice ? MonitorStatus.receiving : MonitorStatus.idle;
    _clearMeasurement();
    if (hasSelectedDevice) {
      _sessionStartedAt = DateTime.now();
      _gattRetryDelay = _gattRetryMinimum;
    }
    if (notify) {
      _notify();
    }
  }

  Future<void> _resumeSelectedDevice() async {
    final selected = _selectedDevice;
    if (_disposed || selected == null || _isDemo) {
      return;
    }
    if (!_gattConnected && !_isScanning) {
      await _startPersistentScan();
    }
    await _ensureGattSession();
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

  void _logStaleWatchdog() {
    final now = DateTime.now();
    final lastLogAt = _lastParseLogAt;
    if (lastLogAt != null &&
        now.difference(lastLogAt) < const Duration(seconds: 5)) {
      return;
    }
    _lastParseLogAt = now;
    final lastReadingAt = _lastReadingAt;
    _log(
      'no fresh reading for >8s '
      '(last reading: ${lastReadingAt == null ? 'never' : lastReadingAt.toIso8601String()}, '
      'scanning=$_isScanning, gatt=$_gattConnected)',
    );
  }

  void _log(String message) {
    debugPrint('[HeartRate] $message');
  }

  @override
  void dispose() {
    _disposed = true;
    _scanTimer?.cancel();
    _clockTimer?.cancel();
    _demoTimer?.cancel();
    _gattRetryTimer?.cancel();
    _teardownGattSession();
    final deviceId = _selectedDevice?.deviceId;
    if (deviceId != null) {
      if (_useWindowsHeartLink) {
        unawaited(_windowsHeartLink!.unsubscribe());
      } else {
        unawaited(_disconnectGatt(deviceId));
      }
    }
    unawaited(_windowsLinkSubscription?.cancel());
    unawaited(_availabilitySubscription?.cancel());
    unawaited(_scanSubscription?.cancel());
    unawaited(stopScan(notify: false));
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

bool isHeartRateCandidate(BleDevice device) {
  if (advertisesHeartRateService(device)) {
    return true;
  }
  if (device.serviceData.keys.any(
    (service) => BleUuidParser.compareStrings(
      service,
      HeartRateController.heartRateServiceUuid,
    ),
  )) {
    return true;
  }
  return device.manufacturerDataList.any(
    (data) => data.companyId == HeartRateController.xiaomiCompanyId,
  );
}

bool mergeBleDevice(BleDevice current, BleDevice incoming) {
  var changed = false;

  if ((current.name?.isEmpty ?? true) && (incoming.name?.isNotEmpty ?? false)) {
    current.name = incoming.name;
    current.rawName = incoming.rawName;
    changed = true;
  }
  if (incoming.rssi != null &&
      (current.rssi == null || incoming.rssi! > current.rssi!)) {
    current.rssi = incoming.rssi;
    changed = true;
  }
  if (incoming.services.any((service) => !current.services.contains(service))) {
    current.services = {
      ...current.services,
      ...incoming.services,
    }.toList(growable: false);
    changed = true;
  }
  if (incoming.paired != null && current.paired != incoming.paired) {
    current.paired = incoming.paired;
    changed = true;
  }
  if (incoming.isSystemDevice == true && current.isSystemDevice != true) {
    current.isSystemDevice = true;
    changed = true;
  }
  return changed;
}
