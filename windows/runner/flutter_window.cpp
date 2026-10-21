#include "flutter_window.h"

#include <dwmapi.h>
#include <map>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "window_manager/window_manager_plugin.h"

namespace {

std::map<HWND, WNDPROC> g_lyrics_procs;

void ExtendLyricsFrame(HWND hwnd) {
  // DwmExtendFrameIntoClientArea can dispatch WM_SIZE back into this proc.
  static bool extending = false;
  if (extending || hwnd == nullptr) {
    return;
  }
  extending = true;
  const MARGINS margins{-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(hwnd, &margins);
  extending = false;
}

// Keeps the glass frame extended after window_manager resets it while
// applying a hidden title bar. The lyrics engine is never destroyed.
LRESULT CALLBACK HabitusLyricsWndProc(HWND hwnd,
                                      UINT message,
                                      WPARAM wparam,
                                      LPARAM lparam) {
  if ((message == WM_SHOWWINDOW && wparam == TRUE) || message == WM_SIZE) {
    ExtendLyricsFrame(hwnd);
  }
  const auto found = g_lyrics_procs.find(hwnd);
  const WNDPROC previous = found == g_lyrics_procs.end() ? nullptr : found->second;
  if (message == WM_NCDESTROY && previous != nullptr) {
    SetWindowLongPtr(hwnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(previous));
    g_lyrics_procs.erase(hwnd);
  }
  if (previous != nullptr) {
    return CallWindowProc(previous, hwnd, message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void InstallLyricsTransparency(HWND root) {
  if (root != nullptr && g_lyrics_procs.find(root) == g_lyrics_procs.end()) {
    const auto previous = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
        root, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(HabitusLyricsWndProc)));
    if (previous != nullptr) {
      g_lyrics_procs.emplace(root, previous);
    }
  }
  ExtendLyricsFrame(root);
}

void RegisterLyricsPlugins(flutter::FlutterViewController* controller) {
  // Audio and storage plugins on this engine crash or quit the process when
  // the window is torn down. The lyrics view only needs window_manager.
  // desktop_multi_window registers itself after this callback.
  WindowManagerPluginRegisterWithRegistrar(
      controller->engine()->GetRegistrarForPlugin("WindowManagerPlugin"));
  HWND view = controller->view()->GetNativeWindow();
  HWND root = ::GetAncestor(view, GA_ROOT);
  InstallLyricsTransparency(root == nullptr ? view : root);
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
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    RegisterLyricsPlugins(
        reinterpret_cast<flutter::FlutterViewController*>(controller));
  });
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
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
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
