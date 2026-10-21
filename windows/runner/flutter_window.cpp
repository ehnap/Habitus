#include "flutter_window.h"

#include <optional>

#include <flutter/standard_method_codec.h>

#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kLyricsChannel[] = "habitus.lyrics";

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int length = static_cast<int>(utf8.size());
  const int wide_length =
      ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), length, nullptr, 0);
  const DWORD flags = wide_length > 0 ? MB_ERR_INVALID_CHARS : 0;
  const int decoded = wide_length > 0
                          ? wide_length
                          : ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), length, nullptr, 0);
  if (decoded <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(decoded), L'\0');
  if (::MultiByteToWideChar(CP_UTF8, flags, utf8.data(), length, wide.data(), decoded) <= 0) {
    return std::wstring();
  }
  return wide;
}

std::wstring LyricArgument(const flutter::EncodableValue* args, const char* key) {
  if (args == nullptr || key == nullptr) {
    return std::wstring();
  }
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (map == nullptr) {
    return std::wstring();
  }
  const auto found = map->find(flutter::EncodableValue(std::string(key)));
  if (found == map->end()) {
    return std::wstring();
  }
  const auto* text = std::get_if<std::string>(&found->second);
  if (text == nullptr) {
    return std::wstring();
  }
  return Utf16FromUtf8(*text);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterLyricsChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (lyrics_channel_) {
    lyrics_channel_->SetMethodCallHandler(nullptr);
  }
  if (lyrics_window_) {
    lyrics_window_->SetClosedHandler(nullptr);
    lyrics_window_.reset();
  }
  lyrics_channel_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::RegisterLyricsChannel() {
  auto* engine = flutter_controller_->engine();
  if (engine == nullptr || engine->messenger() == nullptr) {
    return;
  }
  lyrics_window_ = std::make_unique<LyricsWindow>(GetHandle());
  lyrics_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), kLyricsChannel,
          &flutter::StandardMethodCodec::GetInstance());

  lyrics_window_->SetClosedHandler([this]() {
    if (lyrics_channel_) {
      lyrics_channel_->InvokeMethod("closed", nullptr);
    }
  });

  lyrics_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const std::string& method = call.method_name();
        if (method == "show") {
          if (lyrics_window_ && lyrics_window_->Show()) {
            result->Success();
          } else {
            result->Error("lyrics_window", "Could not show the lyrics window");
          }
          return;
        }
        if (method == "hide" || method == "close") {
          if (lyrics_window_) {
            lyrics_window_->Hide();
          }
          result->Success();
          return;
        }
        if (method == "lines") {
          if (lyrics_window_) {
            lyrics_window_->SetLines(LyricArgument(call.arguments(), "current"),
                                     LyricArgument(call.arguments(), "next"));
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
