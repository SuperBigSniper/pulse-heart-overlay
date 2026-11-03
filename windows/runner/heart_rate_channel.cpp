#include "heart_rate_channel.h"

#include <flutter/encodable_value.h>

#include <chrono>

namespace winrt {
using namespace Windows::Devices::Bluetooth;
using namespace Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace Windows::Foundation;
using namespace Windows::Storage::Streams;
}  // namespace winrt

namespace {

constexpr winrt::guid kHeartRateServiceUuid{
    0x0000180d, 0x0000, 0x1000, {0x80, 0x00, 0x00, 0x80, 0x5f, 0x9b, 0x34, 0xfb}};
constexpr winrt::guid kHeartRateMeasurementUuid{
    0x00002a37, 0x0000, 0x1000, {0x80, 0x00, 0x00, 0x80, 0x5f, 0x9b, 0x34, 0xfb}};

// "74:fb:17:c3:44:cf" -> 0x74fb17c344cf. Returns 0 on malformed input.
std::uint64_t ParseBluetoothAddress(const std::string& text) {
  std::string digits;
  digits.reserve(text.size());
  for (const char c : text) {
    if (c != ':' && c != '-') {
      digits.push_back(c);
    }
  }
  if (digits.empty() || digits.size() > 12) {
    return 0;
  }
  std::uint64_t value = 0;
  for (const char c : digits) {
    const int nibble = [&c]() -> int {
      if (c >= '0' && c <= '9') return c - '0';
      if (c >= 'a' && c <= 'f') return c - 'a' + 10;
      if (c >= 'A' && c <= 'F') return c - 'A' + 10;
      return -1;
    }();
    if (nibble < 0) {
      return 0;
    }
    value = (value << 4) | static_cast<std::uint64_t>(nibble);
  }
  return value;
}

std::string GattStatusText(winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattCommunicationStatus status) {
  using GattCommunicationStatus = winrt::Windows::Devices::Bluetooth::
      GenericAttributeProfile::GattCommunicationStatus;
  switch (status) {
    case GattCommunicationStatus::Success:
      return "success";
    case GattCommunicationStatus::Unreachable:
      return "unreachable";
    case GattCommunicationStatus::ProtocolError:
      return "protocol error";
    case GattCommunicationStatus::AccessDenied:
      return "access denied";
    default:
      return "status " + std::to_string(static_cast<int>(status));
  }
}

}  // namespace

// ---------------------------------------------------------------------------
// UiThreadHandler
// ---------------------------------------------------------------------------

HeartRateChannel::UiThreadHandler::UiThreadHandler(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowMessage(hwnd, message, wparam, lparam);
      });
}

HeartRateChannel::UiThreadHandler::~UiThreadHandler() { Shutdown(); }

void HeartRateChannel::UiThreadHandler::Post(std::function<void()> func) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!accepting_) {
      return;
    }
    queued_.emplace_back(std::move(func));
  }
  Notify();
}

void HeartRateChannel::UiThreadHandler::Shutdown() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!accepting_) {
      return;
    }
    accepting_ = false;
    queued_.clear();
  }
  registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
}

void HeartRateChannel::UiThreadHandler::Notify() {
  const HWND window = hwnd_.load();
  if (window != nullptr) {
    PostMessage(window, kWmCallQueuedFunctions, 0,
                reinterpret_cast<LPARAM>(this));
  }
}

std::optional<LRESULT> HeartRateChannel::UiThreadHandler::HandleWindowMessage(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (hwnd_.load() == nullptr) {
    hwnd_.store(hwnd);
    Notify();  // Make sure queued functions are processed.
  }
  if (message == kWmCallQueuedFunctions &&
      lparam == reinterpret_cast<LPARAM>(this)) {
    std::list<std::function<void()>> queued;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!accepting_) {
        return std::nullopt;
      }
      std::swap(queued, queued_);
    }
    for (auto& func : queued) {
      func();
    }
  }
  return std::nullopt;
}

// ---------------------------------------------------------------------------
// HeartRateChannel
// ---------------------------------------------------------------------------

std::shared_ptr<HeartRateChannel> HeartRateChannel::Create(
    flutter::PluginRegistrarWindows* registrar) {
  // Private constructor: route through raw new instead of make_shared.
  return std::shared_ptr<HeartRateChannel>(
      new HeartRateChannel(registrar, PrivateTag()));
}

HeartRateChannel::HeartRateChannel(flutter::PluginRegistrarWindows* registrar,
                                   PrivateTag)
    : registrar_(registrar) {
  ui_thread_handler_ = std::make_unique<UiThreadHandler>(registrar);
  channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "pulse/heart_rate",
          &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

HeartRateChannel::~HeartRateChannel() {
  Unsubscribe();
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
  if (ui_thread_handler_) {
    ui_thread_handler_->Shutdown();
  }
}

void HeartRateChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "subscribe") {
    std::string address_text;
    if (const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      const auto entry = arguments->find(flutter::EncodableValue("address"));
      if (entry != arguments->end()) {
        if (const auto* address_value = std::get_if<std::string>(&entry->second)) {
          address_text = *address_value;
        }
      }
    }
    const std::uint64_t address = ParseBluetoothAddress(address_text);
    if (address == 0) {
      result->Error("invalid_address",
                    "Malformed Bluetooth address: " + address_text);
      return;
    }
    Unsubscribe();
    std::uint64_t generation = 0;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      address_ = address;
      generation = ++subscribe_generation_;
    }
    SubscribeAsync(shared_from_this(), address, generation);
    result->Success();
    return;
  }
  if (call.method_name() == "unsubscribe") {
    Unsubscribe();
    result->Success();
    return;
  }
  result->NotImplemented();
}

winrt::fire_and_forget HeartRateChannel::SubscribeAsync(
    std::shared_ptr<HeartRateChannel> self, std::uint64_t address,
    std::uint64_t generation) {
  // Suppresses stale error/state reports from superseded attempts.
  auto notify_current = [self, generation](const std::string& state,
                                           const std::string& detail) {
    {
      std::lock_guard<std::mutex> lock(self->mutex_);
      if (generation != self->subscribe_generation_) {
        return;
      }
    }
    self->NotifyState(state, detail);
  };
  try {
    auto device =
        co_await winrt::BluetoothLEDevice::FromBluetoothAddressAsync(address);
    if (!device) {
      notify_current("error", "Failed to get device");
      co_return;
    }

    {
      std::lock_guard<std::mutex> lock(self->mutex_);
      if (generation != self->subscribe_generation_) {
        co_return;  // Superseded by a newer subscribe request.
      }
    }

    // Scope discovery to the heart rate service only. This never touches the
    // band's protected HID service (0x1812), so no pairing is required.
    auto services_result = co_await device.GetGattServicesForUuidAsync(
        kHeartRateServiceUuid, winrt::BluetoothCacheMode::Uncached);
    // The first uncached query initiates the connection; right after a scan it
    // can transiently report Unreachable. Retry once before giving up.
    if (services_result.Status() !=
        winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
            GattCommunicationStatus::Success) {
      co_await winrt::resume_after(std::chrono::milliseconds(400));
      services_result = co_await device.GetGattServicesForUuidAsync(
          kHeartRateServiceUuid, winrt::BluetoothCacheMode::Uncached);
    }
    if (services_result.Status() !=
        winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
            GattCommunicationStatus::Success) {
      notify_current("error",
                     "Heart rate service discovery failed: " +
                         GattStatusText(services_result.Status()));
      co_return;
    }
    // GetGattServicesForUuidAsync yields a GattDeviceServicesResult: pick the
    // heart rate service out of the (typically single-element) list.
    winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattDeviceService
        service{nullptr};
    for (auto const& candidate : services_result.Services()) {
      if (candidate.Uuid() == kHeartRateServiceUuid) {
        service = candidate;
        break;
      }
    }
    if (!service) {
      notify_current("error", "Band does not expose the 0x180D service");
      co_return;
    }

    auto characteristics_result =
        co_await service.GetCharacteristicsForUuidAsync(
            kHeartRateMeasurementUuid, winrt::BluetoothCacheMode::Uncached);
    if (characteristics_result.Status() !=
        winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
            GattCommunicationStatus::Success) {
      notify_current(
          "error",
          "Heart rate measurement lookup failed: " +
              GattStatusText(characteristics_result.Status()));
      co_return;
    }
    auto characteristics = characteristics_result.Characteristics();
    if (characteristics.Size() == 0) {
      notify_current("error", "0x2A37 characteristic missing");
      co_return;
    }
    auto characteristic = characteristics.GetAt(0);

    const auto properties = characteristic.CharacteristicProperties();
    const bool supports_notify =
        (properties &
         winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
             GattCharacteristicProperties::Notify) !=
        winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
            GattCharacteristicProperties::None;
    const bool supports_indicate =
        (properties &
         winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
             GattCharacteristicProperties::Indicate) !=
        winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
            GattCharacteristicProperties::None;
    if (!supports_notify && !supports_indicate) {
      notify_current("error",
                     "0x2A37 does not support notify or indicate");
      co_return;
    }

    using GattCommunicationStatus =
        winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
            GattCommunicationStatus;
    using GattClientCharacteristicConfigurationDescriptorValue =
        winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
            GattClientCharacteristicConfigurationDescriptorValue;

    GattCommunicationStatus cccd_status = GattCommunicationStatus::Unreachable;
    std::string subscription_mode;
    if (supports_notify) {
      cccd_status =
          co_await characteristic
              .WriteClientCharacteristicConfigurationDescriptorAsync(
                  GattClientCharacteristicConfigurationDescriptorValue::
                      Notify);
      subscription_mode = "notify";
    }

    // Some devices advertise Notify but only accept Indicate in practice.
    if (cccd_status != GattCommunicationStatus::Success &&
        supports_indicate) {
      cccd_status =
          co_await characteristic
              .WriteClientCharacteristicConfigurationDescriptorAsync(
                  GattClientCharacteristicConfigurationDescriptorValue::
                      Indicate);
      subscription_mode = "indicate";
    }
    if (cccd_status != GattCommunicationStatus::Success) {
      notify_current(
          "error",
          "Enabling heart-rate " +
              (subscription_mode.empty() ? std::string("subscription")
                                         : subscription_mode) +
              " failed: " + GattStatusText(cccd_status));
      co_return;
    }

    {
      std::lock_guard<std::mutex> lock(self->mutex_);
      if (generation != self->subscribe_generation_) {
        co_return;  // Superseded while connecting.
      }
      // Events hold shared_ptr copies, so registration is safe even if the
      // UI thread releases the channel meanwhile.
      self->device_ = device;
      self->measurement_ = characteristic;
      self->value_changed_token_ = characteristic.ValueChanged(
          [self, generation](
              const winrt::Windows::Devices::Bluetooth::
                  GenericAttributeProfile::GattCharacteristic& sender,
              const winrt::Windows::Devices::Bluetooth::
                  GenericAttributeProfile::GattValueChangedEventArgs& args) {
            self->OnValueChanged(sender, args, generation);
          });
      self->connection_status_token_ = device.ConnectionStatusChanged(
          [self, generation](
              const winrt::Windows::Devices::Bluetooth::BluetoothLEDevice&
                  sender,
              const winrt::Windows::Foundation::IInspectable& args) {
            self->OnConnectionStatusChanged(sender, args, generation);
          });
      self->subscribed_ = true;
    }
    notify_current("ready", "");
  } catch (const winrt::hresult_error& error) {
    notify_current("error", winrt::to_string(error.message()));
  } catch (...) {
    notify_current("error", "Unknown native error");
  }
}

void HeartRateChannel::OnValueChanged(
    const winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
        GattCharacteristic& sender,
    const winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
        GattValueChangedEventArgs& args,
    std::uint64_t generation) {
  if (!IsGenerationCurrent(generation)) {
    return;
  }
  const auto buffer = args.CharacteristicValue();
  std::vector<std::uint8_t> bytes(buffer.data(),
                                  buffer.data() + buffer.Length());
  PostToUiThread([this, generation, bytes = std::move(bytes)]() {
    if (bytes.empty() || !IsGenerationCurrent(generation)) {
      return;
    }
    NotifyValue(bytes);
  });
}

void HeartRateChannel::OnConnectionStatusChanged(
    const winrt::Windows::Devices::Bluetooth::BluetoothLEDevice& sender,
    const winrt::Windows::Foundation::IInspectable& /*args*/,
    std::uint64_t generation) {
  if (sender.ConnectionStatus() ==
      winrt::Windows::Devices::Bluetooth::BluetoothConnectionStatus::
          Disconnected &&
      IsGenerationCurrent(generation)) {
    PostToUiThread([this, generation]() {
      if (IsGenerationCurrent(generation)) {
        NotifyState("disconnected", "");
      }
    });
  }
}

bool HeartRateChannel::IsGenerationCurrent(std::uint64_t generation) {
  std::lock_guard<std::mutex> lock(mutex_);
  return generation == subscribe_generation_;
}

void HeartRateChannel::NotifyState(const std::string& state,
                                   const std::string& detail) {
  if (!channel_) {
    return;
  }
  flutter::EncodableMap event{
      {flutter::EncodableValue("type"), flutter::EncodableValue("state")},
      {flutter::EncodableValue("state"), flutter::EncodableValue(state)},
      {flutter::EncodableValue("detail"), flutter::EncodableValue(detail)},
  };
  channel_->InvokeMethod("onEvent",
                         std::make_unique<flutter::EncodableValue>(event));
}

void HeartRateChannel::NotifyValue(const std::vector<std::uint8_t>& bytes) {
  if (!channel_) {
    return;
  }
  flutter::EncodableMap event{
      {flutter::EncodableValue("type"), flutter::EncodableValue("value")},
      {flutter::EncodableValue("bytes"), flutter::EncodableValue(bytes)},
  };
  channel_->InvokeMethod("onEvent",
                         std::make_unique<flutter::EncodableValue>(event));
}

void HeartRateChannel::Unsubscribe() {
  winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
      GattCharacteristic characteristic{nullptr};
  winrt::Windows::Devices::Bluetooth::BluetoothLEDevice device{nullptr};
  {
    std::lock_guard<std::mutex> lock(mutex_);
    // Always invalidate an in-flight SubscribeAsync, even before it has
    // reached the subscribed state.
    ++subscribe_generation_;
    address_ = 0;
    if (!subscribed_) {
      return;
    }
    subscribed_ = false;
    characteristic = measurement_;
    device = device_;
    measurement_ = {nullptr};
    device_ = {nullptr};
  }
  // Unregister outside the lock: WinRT may wait for in-flight handlers that
  // take the same mutex.
  if (characteristic) {
    try {
      characteristic.ValueChanged(value_changed_token_);
    } catch (...) {
    }
  }
  if (device) {
    try {
      device.ConnectionStatusChanged(connection_status_token_);
    } catch (...) {
    }
    try {
      device.Close();
    } catch (...) {
    }
  }
}

void HeartRateChannel::PostToUiThread(std::function<void()> func) {
  if (ui_thread_handler_) {
    ui_thread_handler_->Post(std::move(func));
  }
}
