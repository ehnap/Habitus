#include "flutter_window.h"

#include <dwmapi.h>
#include <map>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "window_manager/window_manager_plugin.h"

namespace {

std::map<HWND, WNDPROC> g_lyrics_procs;

// A transparent Flutter color only clears the scene. Windows 11 still paints
// an opaque rounded sheet behind it; these calls drop that sheet. WS_EX_LAYERED
// is not used: it is uniform alpha or a color key, and either hides the window
// or fringes the text.
struct AccentPolicy {
  int state;
  int flags;
  int color;
  int animation;
};

struct WindowCompositionAttributeData {
  int attribute;
  PVOID data;
  ULONG size;
};

using SetWindowCompositionAttributeFn = BOOL(WINAPI*)(HWND, WindowCompositionAttributeData*);

void SetAccentPolicy(HWND hwnd) {
  const HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
  if (user32 == nullptr) {
    return;
  }
  const auto set_attribute = reinterpret_cast<SetWindowCompositionAttributeFn>(
      ::GetProcAddress(user32, "SetWindowCompositionAttribute"));
  if (set_attribute == nullptr) {
    return;
  }
  // ACCENT_ENABLE_TRANSPARENTGRADIENT, color 0. Flags match window_manager so
  // Windows 10 still punches a hole; the backdrop below is what Win11 adds.
  AccentPolicy policy{2, 2, 0, 0};
  WindowCompositionAttributeData data{19, &policy, sizeof(policy)};
  set_attribute(hwnd, &data);
}

void ClearLyricsBackdrop(HWND hwnd) {
  if (hwnd == nullptr) {
    return;
  }
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

void ApplyLyricsTransparency(HWND hwnd, bool frame_changed) {
  // DwmExtendFrameIntoClientArea and SetWindowPos can dispatch WM_SIZE.
  static bool applying = false;
  if (applying || hwnd == nullptr) {
    return;
  }
  applying = true;

  LONG_PTR style = ::GetWindowLongPtr(hwnd, GWL_STYLE);
  const LONG_PTR updated_style =
      (style & ~static_cast<LONG_PTR>(WS_CAPTION | WS_SYSMENU)) | WS_POPUP | WS_THICKFRAME;
  if (updated_style != style) {
    ::SetWindowLongPtr(hwnd, GWL_STYLE, updated_style);
    frame_changed = true;
  }
  LONG_PTR ex_style = ::GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  const LONG_PTR updated_ex = ex_style & ~static_cast<LONG_PTR>(WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE |
                                                                WS_EX_DLGMODALFRAME | WS_EX_STATICEDGE |
                                                                WS_EX_LAYERED);
  if (updated_ex != ex_style) {
    ::SetWindowLongPtr(hwnd, GWL_EXSTYLE, updated_ex);
    frame_changed = true;
  }

  // Drop the Win11 mica sheet, rounded corners, and border. Square corners
  // also drop the rounded window's shadow card. Integer attributes stay valid
  // on SDKs that have not named them yet.
  ClearLyricsBackdrop(hwnd);

  const MARGINS margins{-1, -1, -1, -1};
  ::DwmExtendFrameIntoClientArea(hwnd, &margins);

  // After the backdrop is cleared. Doing this earlier lets Win11 paint a sheet
  // over the transparent gradient.
  SetAccentPolicy(hwnd);

  if (frame_changed) {
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }
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
    ApplyLyricsTransparency(hwnd, message != WM_SIZE);
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
  ApplyLyricsTransparency(root, true);
}

void RegisterLyricsPlugins(flutter::FlutterViewController* controller) {
  // Audio and storage plugins on this engine crash or quit the process when
  // the window is torn down. The lyrics view only needs window_manager.
  // desktop_multi_window registers itself after this callback.
  WindowManagerPluginRegisterWithRegistrar(
      controller->engine()->GetRegistrarForPlugin("WindowManagerPlugin"));
  HWND view = controller->view()->GetNativeWindow();
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
