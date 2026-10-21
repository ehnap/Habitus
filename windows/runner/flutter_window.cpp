#include "flutter_window.h"

#include <dwmapi.h>
#include <map>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "window_manager/window_manager_plugin.h"

namespace {

std::map<HWND, WNDPROC> g_lyrics_procs;
std::map<HWND, WNDPROC> g_lyrics_child_procs;

void ClearLyricsBackdrop(HWND hwnd) {
  if (hwnd == nullptr) {
    return;
  }
  // Win11 otherwise paints an opaque system sheet behind the Flutter view.
  // These attributes are not an accent policy. Window styles, including
  // WS_EX_LAYERED, are left alone.
  const BOOL host_backdrop = FALSE;
  ::DwmSetWindowAttribute(hwnd, 17, &host_backdrop, sizeof(host_backdrop));
  const DWORD backdrop_none = 1;  // DWMSBT_NONE
  ::DwmSetWindowAttribute(hwnd, 38, &backdrop_none, sizeof(backdrop_none));
  const DWORD square_corners = 1;  // DWMWCP_DONOTROUND
  ::DwmSetWindowAttribute(hwnd, 33, &square_corners, sizeof(square_corners));
  const COLORREF no_color = 0xFFFFFFFE;  // DWMWA_COLOR_NONE
  ::DwmSetWindowAttribute(hwnd, 34, &no_color, sizeof(no_color));
  ::DwmSetWindowAttribute(hwnd, 35, &no_color, sizeof(no_color));
}

void ApplyLyricsTransparency(HWND hwnd) {
  // DwmExtendFrameIntoClientArea can dispatch WM_SIZE back into this proc.
  static bool applying = false;
  if (applying || hwnd == nullptr) {
    return;
  }
  applying = true;
  ClearLyricsBackdrop(hwnd);
  const MARGINS margins{-1, -1, -1, -1};
  ::DwmExtendFrameIntoClientArea(hwnd, &margins);
  applying = false;
}

// Keeps the glass frame extended after window_manager resets it while
// applying a hidden title bar. The lyrics engine is never destroyed.
LRESULT CALLBACK HabitusLyricsWndProc(HWND hwnd,
                                      UINT message,
                                      WPARAM wparam,
                                      LPARAM lparam) {
  if (message == WM_ERASEBKGND) {
    return 1;
  }
  if ((message == WM_SHOWWINDOW && wparam == TRUE) || message == WM_SIZE ||
      message == WM_DWMCOMPOSITIONCHANGED || message == WM_THEMECHANGED) {
    ApplyLyricsTransparency(hwnd);
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
  ApplyLyricsTransparency(root);
}

// Flutter's child view erases with the system window color (white) before the
// first transparent frame. Swallow that erase on the lyrics view only.
LRESULT CALLBACK HabitusLyricsChildProc(HWND hwnd,
                                        UINT message,
                                        WPARAM wparam,
                                        LPARAM lparam) {
  if (message == WM_ERASEBKGND) {
    return 1;
  }
  const auto found = g_lyrics_child_procs.find(hwnd);
  const WNDPROC previous = found == g_lyrics_child_procs.end() ? nullptr : found->second;
  if (message == WM_NCDESTROY && previous != nullptr) {
    ::SetWindowLongPtr(hwnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(previous));
    g_lyrics_child_procs.erase(hwnd);
  }
  if (previous != nullptr) {
    return ::CallWindowProc(previous, hwnd, message, wparam, lparam);
  }
  return ::DefWindowProc(hwnd, message, wparam, lparam);
}

void InstallLyricsChildErase(HWND view) {
  if (view == nullptr || g_lyrics_child_procs.find(view) != g_lyrics_child_procs.end()) {
    return;
  }
  const auto previous = reinterpret_cast<WNDPROC>(::SetWindowLongPtr(
      view, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(HabitusLyricsChildProc)));
  if (previous != nullptr) {
    g_lyrics_child_procs.emplace(view, previous);
  }
}

// Flutter 3.47.7 (engine deb287481e) does not export
// FlutterView::SetBackgroundColor or
// FlutterDesktopViewControllerSetBackgroundColor. flutter_view.h only exposes
// GetNativeWindow and GetGraphicsAdapter. The lyrics scene writes ARGB 0
// itself, and this stops the child HWND from erasing white behind it.
void PrepareLyricsView(flutter::FlutterView* view) {
  if (view == nullptr) {
    return;
  }
  HWND hwnd = view->GetNativeWindow();
  InstallLyricsChildErase(hwnd);
}

void RegisterLyricsPlugins(flutter::FlutterViewController* controller) {
  // Audio and storage plugins on this engine crash or quit the process when
  // the window is torn down. The lyrics view only needs window_manager.
  // desktop_multi_window registers itself after this callback.
  WindowManagerPluginRegisterWithRegistrar(
      controller->engine()->GetRegistrarForPlugin("WindowManagerPlugin"));
  flutter::FlutterView* flutter_view = controller->view();
  if (flutter_view == nullptr) {
    return;
  }
  PrepareLyricsView(flutter_view);
  HWND view = flutter_view->GetNativeWindow();
  HWND root = ::GetAncestor(view, GA_ROOT);
  ClearLyricsBackdrop(view);
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
