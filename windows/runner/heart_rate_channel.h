#ifndef RUNNER_HEART_RATE_CHANNEL_H_
#define RUNNER_HEART_RATE_CHANNEL_H_

#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <list>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

// Bridges the heart rate service (0x180D / 0x2A37) into Flutter over a single
// method channel named "pulse/heart_rate".
//
// Unlike universal_ble's Windows implementation, discovery is scoped to the
// heart rate service only (GetGattServicesForUuidAsync), so the band's
// protected HID service (0x1812) is never enumerated. This avoids requiring
// bonding merely to enumerate the HID service.
//
// Lifetime: instances are shared_ptr-managed. Native async operations and
// event handlers capture a shared_ptr, so the object outlives any in-flight
// callback even if the UI thread drops its reference meanwhile.
class HeartRateChannel : public std::enable_shared_from_this<HeartRateChannel> {
 public:
  static std::shared_ptr<HeartRateChannel> Create(
      flutter::PluginRegistrarWindows* registrar);

  ~HeartRateChannel();

  HeartRateChannel(const HeartRateChannel&) = delete;
  HeartRateChannel& operator=(const HeartRateChannel&) = delete;

 private:
  struct PrivateTag {
    explicit PrivateTag() = default;
  };

  HeartRateChannel(flutter::PluginRegistrarWindows* registrar, PrivateTag);

  // Dart -> native methods.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Connects to |address|, resolves 0x180D/0x2A37 and enables notifications.
  // |generation| invalidates the attempt when a newer subscribe request wins.
  winrt::fire_and_forget SubscribeAsync(std::shared_ptr<HeartRateChannel> self,
                                        std::uint64_t address,
                                        std::uint64_t generation);
  // Releases the GATT session, if any. Safe to call when not subscribed.
  void Unsubscribe();

  // GATT callbacks (WinRT thread pool).
  void OnValueChanged(
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
          GattCharacteristic const& sender,
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
          GattValueChangedEventArgs const& args,
      std::uint64_t generation);
  void OnConnectionStatusChanged(
      winrt::Windows::Devices::Bluetooth::BluetoothLEDevice const& sender,
      winrt::Windows::Foundation::IInspectable const& args,
      std::uint64_t generation);

  bool IsGenerationCurrent(std::uint64_t generation);

  // Dart-facing notifications. Must be invoked on the platform thread.
  void NotifyState(const std::string& state, const std::string& detail);
  void NotifyValue(const std::vector<std::uint8_t>& bytes);

  // Marshals WinRT thread-pool callbacks back onto the platform thread via a
  // top-level window message (same pattern as the universal_ble plugin).
  class UiThreadHandler {
   public:
    explicit UiThreadHandler(flutter::PluginRegistrarWindows* registrar);
    ~UiThreadHandler();

    UiThreadHandler(const UiThreadHandler&) = delete;
    UiThreadHandler& operator=(const UiThreadHandler&) = delete;

    void Post(std::function<void()> func);
    void Shutdown();

   private:
    static constexpr UINT kWmCallQueuedFunctions = WM_APP + 0x3b1;

    std::optional<LRESULT> HandleWindowMessage(HWND hwnd, UINT message,
                                               WPARAM wparam, LPARAM lparam);
    void Notify();

    flutter::PluginRegistrarWindows* registrar_;
    int window_proc_id_ = 0;
    std::atomic<HWND> hwnd_{nullptr};
    std::list<std::function<void()>> queued_;
    std::mutex mutex_;
    bool accepting_ = true;
  };

  void PostToUiThread(std::function<void()> func);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<UiThreadHandler> ui_thread_handler_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  std::mutex mutex_;
  bool subscribed_ = false;
  std::uint64_t address_ = 0;
  // Incremented per subscribe request so a superseded in-flight connect
  // coroutine abandons instead of registering stale callbacks.
  std::uint64_t subscribe_generation_ = 0;
  winrt::Windows::Devices::Bluetooth::BluetoothLEDevice device_{nullptr};
  winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
      GattCharacteristic measurement_{nullptr};
  winrt::event_token value_changed_token_{};
  winrt::event_token connection_status_token_{};
};

#endif  // RUNNER_HEART_RATE_CHANNEL_H_
