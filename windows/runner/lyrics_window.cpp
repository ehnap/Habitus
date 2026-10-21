#include "lyrics_window.h"

#include <d2d1.h>
#include <dwrite.h>
#include <dwrite_2.h>
#include <windowsx.h>

#include <new>

namespace {

constexpr wchar_t kClassName[] = L"HabitusLyricsLayer";

// Owned tool window. Layered so the bitmap's alpha is the window.
// Not WS_EX_APPWINDOW, so it does not get a taskbar button.
// Not WS_EX_TRANSPARENT, so the text area can drag and the close button
// can be clicked.
constexpr DWORD kExStyle = WS_EX_LAYERED | WS_EX_TOOLWINDOW;
constexpr int kLogicalWidth = 560;
constexpr int kLogicalHeight = 112;

static_assert((kExStyle & WS_EX_APPWINDOW) == 0,
              "lyrics window must not take a taskbar button");
static_assert((kExStyle & WS_EX_TRANSPARENT) == 0,
              "lyrics window must receive clicks");
static_assert((kExStyle & WS_EX_LAYERED) == WS_EX_LAYERED,
              "lyrics window is layered");
static_assert((kExStyle & WS_EX_TOOLWINDOW) == WS_EX_TOOLWINDOW,
              "lyrics window is a tool window");

// HabitusColors.nightInk #F3F0E8. Straight alpha; the premultiplied target
// multiplies it on draw.
constexpr float kInkR = 243.0f / 255.0f;
constexpr float kInkG = 240.0f / 255.0f;
constexpr float kInkB = 232.0f / 255.0f;

constexpr float kTextLeft = 16.0f;
constexpr float kTextGap = 8.0f;
constexpr float kCloseSize = 32.0f;
constexpr float kCloseMargin = 8.0f;
constexpr float kCurrentFont = 16.0f;
constexpr float kNextFont = 13.0f;
constexpr float kCurrentBox = 24.0f;
constexpr float kNextBox = 20.0f;
constexpr float kLineGap = 6.0f;

struct DipBox {
  float left;
  float top;
  float right;
  float bottom;
};

DipBox CloseBox() {
  const float left = static_cast<float>(kLogicalWidth) - kCloseMargin - kCloseSize;
  const float top = (static_cast<float>(kLogicalHeight) - kCloseSize) / 2.0f;
  return DipBox{left, top, left + kCloseSize, top + kCloseSize};
}

int ScalePx(int logical, UINT dpi) {
  if (dpi == 0) {
    dpi = 96;
  }
  const int scaled = ::MulDiv(logical, static_cast<int>(dpi), 96);
  return scaled < 1 ? 1 : scaled;
}

template <typename T>
void ReleaseCom(T*& pointer) {
  if (pointer != nullptr) {
    pointer->Release();
    pointer = nullptr;
  }
}

bool FontFamilyExists(IDWriteFactory* factory, const wchar_t* name) {
  if (factory == nullptr || name == nullptr) {
    return false;
  }
  IDWriteFontCollection* collection = nullptr;
  if (FAILED(factory->GetSystemFontCollection(&collection, FALSE)) ||
      collection == nullptr) {
    return false;
  }
  UINT32 index = 0;
  BOOL exists = FALSE;
  const HRESULT found = collection->FindFamilyName(name, &index, &exists);
  collection->Release();
  return SUCCEEDED(found) && exists == TRUE;
}

void DrawOutlinedText(ID2D1RenderTarget* target,
                      IDWriteTextLayout* layout,
                      float x,
                      float y,
                      ID2D1Brush* fill,
                      ID2D1Brush* ring,
                      ID2D1Brush* halo) {
  if (target == nullptr || layout == nullptr || fill == nullptr) {
    return;
  }
  const float halo_offsets[][2] = {
      {-2.0f, 0.0f},  {2.0f, 0.0f},  {0.0f, -2.0f}, {0.0f, 2.0f},
      {-2.0f, -2.0f}, {2.0f, -2.0f}, {-2.0f, 2.0f}, {2.0f, 2.0f},
  };
  if (halo != nullptr) {
    for (const auto& offset : halo_offsets) {
      target->DrawTextLayout(D2D1::Point2F(x + offset[0], y + offset[1]), layout,
                             halo);
    }
  }
  const float ring_offsets[][2] = {
      {-1.0f, 0.0f},  {1.0f, 0.0f},  {0.0f, -1.0f}, {0.0f, 1.0f},
      {-1.0f, -1.0f}, {1.0f, -1.0f}, {-1.0f, 1.0f}, {1.0f, 1.0f},
  };
  if (ring != nullptr) {
    for (const auto& offset : ring_offsets) {
      target->DrawTextLayout(D2D1::Point2F(x + offset[0], y + offset[1]), layout,
                             ring);
    }
  }
  target->DrawTextLayout(D2D1::Point2F(x, y), layout, fill);
}

struct ScopedBitmap {
  HDC screen = nullptr;
  HDC mem = nullptr;
  HBITMAP dib = nullptr;
  HGDIOBJ previous = nullptr;
  void* bits = nullptr;

  ~ScopedBitmap() {
    if (mem != nullptr && previous != nullptr) {
      ::SelectObject(mem, previous);
    }
    if (dib != nullptr) {
      ::DeleteObject(dib);
    }
    if (mem != nullptr) {
      ::DeleteDC(mem);
    }
    if (screen != nullptr) {
      ::ReleaseDC(nullptr, screen);
    }
  }

  ScopedBitmap(const ScopedBitmap&) = delete;
  ScopedBitmap& operator=(const ScopedBitmap&) = delete;
  ScopedBitmap() = default;
};

}  // namespace

struct LyricsWindow::Devices {
  ID2D1Factory* d2d = nullptr;
  IDWriteFactory* dwrite = nullptr;
  IDWriteFontFallback* fallback = nullptr;
  IDWriteTextFormat* current_format = nullptr;
  IDWriteTextFormat* next_format = nullptr;
  ID2D1StrokeStyle* stroke = nullptr;
  IDWriteRenderingParams* rendering = nullptr;

  Devices() = default;
  Devices(const Devices&) = delete;
  Devices& operator=(const Devices&) = delete;
  ~Devices() { Release(); }

  void Release() {
    ReleaseCom(current_format);
    ReleaseCom(next_format);
    ReleaseCom(rendering);
    ReleaseCom(stroke);
    ReleaseCom(fallback);
    ReleaseCom(dwrite);
    ReleaseCom(d2d);
  }

  bool Ensure() {
    if (d2d != nullptr && dwrite != nullptr) {
      return true;
    }
    Release();
    D2D1_FACTORY_OPTIONS options{};
    options.debugLevel = D2D1_DEBUG_LEVEL_NONE;
    if (FAILED(::D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
                                   __uuidof(ID2D1Factory), &options,
                                   reinterpret_cast<void**>(&d2d))) ||
        d2d == nullptr) {
      d2d = nullptr;
      return false;
    }
    if (FAILED(::DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,
                                     __uuidof(IDWriteFactory),
                                     reinterpret_cast<IUnknown**>(&dwrite))) ||
        dwrite == nullptr) {
      Release();
      return false;
    }
    CreateFallback();
    CreateRenderingParams();
    const D2D1_STROKE_STYLE_PROPERTIES stroke_props = D2D1::StrokeStyleProperties(
        D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND,
        D2D1_LINE_JOIN_ROUND);
    if (FAILED(d2d->CreateStrokeStyle(&stroke_props, nullptr, 0, &stroke))) {
      stroke = nullptr;
    }
    current_format = CreateFormat(kCurrentFont, DWRITE_FONT_WEIGHT_SEMI_BOLD);
    next_format = CreateFormat(kNextFont, DWRITE_FONT_WEIGHT_NORMAL);
    return true;
  }

  void CreateFallback() {
    if (!FontFamilyExists(dwrite, L"Microsoft YaHei") &&
        !FontFamilyExists(dwrite, L"Microsoft YaHei UI")) {
      return;
    }
    IDWriteFactory2* factory2 = nullptr;
    if (FAILED(dwrite->QueryInterface(IID_PPV_ARGS(&factory2))) ||
        factory2 == nullptr) {
      return;
    }
    IDWriteFontFallbackBuilder* builder = nullptr;
    if (FAILED(factory2->CreateFontFallbackBuilder(&builder)) || builder == nullptr) {
      factory2->Release();
      return;
    }
    const DWRITE_UNICODE_RANGE cjk[] = {
        {0x3000, 0x303F}, {0x3040, 0x30FF}, {0x31F0, 0x31FF}, {0x3400, 0x4DBF},
        {0x4E00, 0x9FFF}, {0xF900, 0xFAFF}, {0xFF00, 0xFFEF},
    };
    const wchar_t* yahei[] = {L"Microsoft YaHei", L"Microsoft YaHei UI"};
    const HRESULT cjk_mapped =
        builder->AddMapping(cjk, 7, yahei, 2, nullptr, nullptr, nullptr, 1.0f);
    const wchar_t* rest[] = {L"Segoe UI", L"Microsoft YaHei"};
    const HRESULT rest_mapped =
        builder->AddMapping(nullptr, 0, rest, 2, nullptr, nullptr, nullptr, 1.0f);
    if (FAILED(cjk_mapped) || FAILED(rest_mapped)) {
      builder->Release();
      factory2->Release();
      return;
    }
    if (FAILED(builder->CreateFontFallback(&fallback))) {
      fallback = nullptr;
    }
    builder->Release();
    factory2->Release();
  }

  void CreateRenderingParams() {
    IDWriteRenderingParams* defaults = nullptr;
    FLOAT gamma = 1.8f;
    FLOAT contrast = 0.5f;
    DWRITE_RENDERING_MODE mode = DWRITE_RENDERING_MODE_NATURAL_SYMMETRIC;
    if (SUCCEEDED(dwrite->CreateRenderingParams(&defaults)) && defaults != nullptr) {
      gamma = defaults->GetGamma();
      contrast = defaults->GetEnhancedContrast();
      mode = defaults->GetRenderingMode();
      defaults->Release();
    }
    // ClearType level 0 and flat pixel geometry keep the glyphs grayscale.
    if (FAILED(dwrite->CreateCustomRenderingParams(
            gamma, contrast, 0.0f, DWRITE_PIXEL_GEOMETRY_FLAT, mode, &rendering))) {
      rendering = nullptr;
    }
  }

  IDWriteTextFormat* CreateFormat(float size, DWRITE_FONT_WEIGHT weight) {
    IDWriteTextFormat* format = nullptr;
    const wchar_t* family =
        FontFamilyExists(dwrite, L"Segoe UI") ? L"Segoe UI" : L"Microsoft YaHei";
    if (FAILED(dwrite->CreateTextFormat(family, nullptr, weight, DWRITE_FONT_STYLE_NORMAL,
                                        DWRITE_FONT_STRETCH_NORMAL, size, L"zh-CN",
                                        &format)) ||
        format == nullptr) {
      return nullptr;
    }
    if (fallback != nullptr) {
      IDWriteTextFormat1* format1 = nullptr;
      if (SUCCEEDED(format->QueryInterface(IID_PPV_ARGS(&format1))) &&
          format1 != nullptr) {
        format1->SetFontFallback(fallback);
        format1->Release();
      }
    }
    format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_LEADING);
    format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_NEAR);
    DWRITE_TRIMMING trimming{};
    trimming.granularity = DWRITE_TRIMMING_GRANULARITY_CHARACTER;
    IDWriteInlineObject* ellipsis = nullptr;
    if (SUCCEEDED(dwrite->CreateEllipsisTrimmingSign(format, &ellipsis)) &&
        ellipsis != nullptr) {
      format->SetTrimming(&trimming, ellipsis);
      ellipsis->Release();
    }
    return format;
  }
};

LyricsWindow::LyricsWindow(HWND owner) : owner_(owner) {}

LyricsWindow::~LyricsWindow() {
  closed_ = nullptr;
  HWND hwnd = hwnd_;
  hwnd_ = nullptr;
  if (hwnd != nullptr && ::IsWindow(hwnd)) {
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
    ::DestroyWindow(hwnd);
  }
  ReleaseDevices();
}

bool LyricsWindow::Show() {
  if (!EnsureCreated()) {
    return false;
  }
  Paint();
  ::ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  ::SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  return true;
}

void LyricsWindow::Hide() {
  if (hwnd_ != nullptr) {
    ::ShowWindow(hwnd_, SW_HIDE);
  }
}

void LyricsWindow::SetLines(const std::wstring& current, const std::wstring& next) {
  current_ = current;
  next_ = next;
  if (hwnd_ != nullptr && ::IsWindowVisible(hwnd_)) {
    Paint();
  }
}

void LyricsWindow::SetClosedHandler(std::function<void()> handler) {
  closed_ = std::move(handler);
}

bool LyricsWindow::EnsureCreated() {
  if (hwnd_ != nullptr) {
    return true;
  }
  if (owner_ == nullptr) {
    return false;
  }
  WNDCLASSEXW existing{};
  existing.cbSize = sizeof(existing);
  const HINSTANCE instance = ::GetModuleHandleW(nullptr);
  if (!::GetClassInfoExW(instance, kClassName, &existing)) {
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = LyricsWindow::WndProc;
    window_class.hInstance = instance;
    window_class.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
    window_class.lpszClassName = kClassName;
    if (::RegisterClassExW(&window_class) == 0) {
      return false;
    }
  }
  const UINT dpi = WindowDpi();
  const int width = ScalePx(kLogicalWidth, dpi);
  const int height = ScalePx(kLogicalHeight, dpi);
  int x = 0;
  int y = 0;
  InitialOrigin(dpi, width, height, &x, &y);
  // hwndParent of a WS_POPUP is the owner. GetWindowLongPtr(GWLP_HWNDPARENT)
  // returns that owner. The popup is destroyed with the main window.
  HWND created = ::CreateWindowExW(kExStyle, kClassName, L"", WS_POPUP, x, y, width,
                                   height, owner_, nullptr, instance, this);
  if (created == nullptr) {
    hwnd_ = nullptr;
    return false;
  }
  hwnd_ = created;
  LONG_PTR ex_style = ::GetWindowLongPtrW(hwnd_, GWLP_EXSTYLE);
  ex_style |= static_cast<LONG_PTR>(WS_EX_LAYERED | WS_EX_TOOLWINDOW);
  ex_style &= ~static_cast<LONG_PTR>(WS_EX_APPWINDOW | WS_EX_TRANSPARENT);
  ::SetWindowLongPtrW(hwnd_, GWLP_EXSTYLE, ex_style);
  ::SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  return true;
}

void LyricsWindow::InitialOrigin(UINT dpi, int width, int height, int* x, int* y) const {
  RECT owner_rect{};
  if (owner_ == nullptr || !::GetWindowRect(owner_, &owner_rect)) {
    owner_rect = RECT{0, 0, 0, 0};
  }
  LONG left = owner_rect.left + ScalePx(32, dpi);
  LONG top = owner_rect.top + ScalePx(64, dpi);
  const HMONITOR monitor = ::MonitorFromWindow(
      owner_ != nullptr ? owner_ : hwnd_, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (::GetMonitorInfoW(monitor, &info)) {
    const RECT& work = info.rcWork;
    if (left + width > work.right) {
      left = work.right - width;
    }
    if (top + height > work.bottom) {
      top = work.bottom - height;
    }
    if (left < work.left) {
      left = work.left;
    }
    if (top < work.top) {
      top = work.top;
    }
  }
  *x = static_cast<int>(left);
  *y = static_cast<int>(top);
}

bool LyricsWindow::EnsureDevices() {
  if (devices_ == nullptr) {
    devices_ = new (std::nothrow) Devices();
    if (devices_ == nullptr) {
      return false;
    }
  }
  return devices_->Ensure();
}

void LyricsWindow::ReleaseDevices() {
  delete devices_;
  devices_ = nullptr;
}

UINT LyricsWindow::WindowDpi() const {
  UINT dpi = 0;
  if (hwnd_ != nullptr) {
    dpi = ::GetDpiForWindow(hwnd_);
  }
  if (dpi == 0 && owner_ != nullptr) {
    dpi = ::GetDpiForWindow(owner_);
  }
  return dpi == 0 ? 96 : dpi;
}

void LyricsWindow::Paint() {
  if (hwnd_ == nullptr || painting_) {
    return;
  }
  painting_ = true;
  const UINT dpi = WindowDpi();
  const int width = ScalePx(kLogicalWidth, dpi);
  const int height = ScalePx(kLogicalHeight, dpi);
  const size_t bytes =
      static_cast<size_t>(width) * static_cast<size_t>(height) * 4u;

  ScopedBitmap bitmap;
  bitmap.screen = ::GetDC(nullptr);
  if (bitmap.screen == nullptr) {
    painting_ = false;
    return;
  }
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  bitmap.dib = ::CreateDIBSection(bitmap.screen, &info, DIB_RGB_COLORS, &bitmap.bits,
                                  nullptr, 0);
  bitmap.mem = ::CreateCompatibleDC(bitmap.screen);
  if (bitmap.dib == nullptr || bitmap.bits == nullptr || bitmap.mem == nullptr) {
    painting_ = false;
    return;
  }
  bitmap.previous = ::SelectObject(bitmap.mem, bitmap.dib);
  if (bitmap.previous == nullptr) {
    painting_ = false;
    return;
  }
  // Undrawn pixels stay alpha 0. Nothing fills a panel behind the text.
  ::ZeroMemory(bitmap.bits, bytes);

  const bool devices_ready = EnsureDevices();
  ID2D1DCRenderTarget* target = nullptr;
  if (devices_ready && devices_ != nullptr && devices_->d2d != nullptr) {
    D2D1_RENDER_TARGET_PROPERTIES properties = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_DEFAULT,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED),
        static_cast<float>(dpi), static_cast<float>(dpi),
        D2D1_RENDER_TARGET_USAGE_GDI_COMPATIBLE);
    if (SUCCEEDED(devices_->d2d->CreateDCRenderTarget(&properties, &target)) &&
        target != nullptr) {
      RECT bind{0, 0, width, height};
      if (SUCCEEDED(target->BindDC(bitmap.mem, &bind))) {
        target->BeginDraw();
        target->Clear(D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.0f));
        target->SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
        if (devices_->rendering != nullptr) {
          target->SetTextRenderingParams(devices_->rendering);
        }
        // After rendering params, so a ClearType default cannot replace this.
        target->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
        ID2D1SolidColorBrush* ink = nullptr;
        ID2D1SolidColorBrush* ink_dim = nullptr;
        ID2D1SolidColorBrush* ring = nullptr;
        ID2D1SolidColorBrush* halo = nullptr;
        if (FAILED(target->CreateSolidColorBrush(D2D1::ColorF(kInkR, kInkG, kInkB, 1.0f),
                                                 &ink))) {
          ink = nullptr;
        }
        if (FAILED(target->CreateSolidColorBrush(
                D2D1::ColorF(kInkR, kInkG, kInkB, 0.82f), &ink_dim))) {
          ink_dim = nullptr;
        }
        if (FAILED(target->CreateSolidColorBrush(D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.95f),
                                                 &ring))) {
          ring = nullptr;
        }
        if (FAILED(target->CreateSolidColorBrush(D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.40f),
                                                 &halo))) {
          halo = nullptr;
        }
        const float text_width = static_cast<float>(kLogicalWidth) - kTextLeft -
                                 kTextGap - kCloseSize - kCloseMargin;
        const float block = kCurrentBox + kLineGap + kNextBox;
        const float current_top =
            (static_cast<float>(kLogicalHeight) - block) / 2.0f;
        const float next_top = current_top + kCurrentBox + kLineGap;
        auto draw_line = [&](const std::wstring& text, IDWriteTextFormat* format,
                             float top, float box, ID2D1Brush* fill) {
          if (text.empty() || format == nullptr || fill == nullptr || devices_->dwrite == nullptr) {
            return;
          }
          IDWriteTextLayout* layout = nullptr;
          const UINT32 length = static_cast<UINT32>(text.size());
          if (FAILED(devices_->dwrite->CreateTextLayout(text.c_str(), length, format,
                                                        text_width, box, &layout)) ||
              layout == nullptr) {
            return;
          }
          DrawOutlinedText(target, layout, kTextLeft, top, fill, ring, halo);
          layout->Release();
        };
        draw_line(current_, devices_->current_format, current_top, kCurrentBox, ink);
        draw_line(next_, devices_->next_format, next_top, kNextBox, ink_dim);
        if (ink != nullptr) {
          const DipBox close = CloseBox();
          const float cx = (close.left + close.right) / 2.0f;
          const float cy = (close.top + close.bottom) / 2.0f;
          const float arm = 5.5f;
          const D2D1_POINT_2F a0 = D2D1::Point2F(cx - arm, cy - arm);
          const D2D1_POINT_2F a1 = D2D1::Point2F(cx + arm, cy + arm);
          const D2D1_POINT_2F b0 = D2D1::Point2F(cx + arm, cy - arm);
          const D2D1_POINT_2F b1 = D2D1::Point2F(cx - arm, cy + arm);
          if (ring != nullptr) {
            target->DrawLine(a0, a1, ring, 3.2f, devices_->stroke);
            target->DrawLine(b0, b1, ring, 3.2f, devices_->stroke);
          }
          target->DrawLine(a0, a1, ink, 1.6f, devices_->stroke);
          target->DrawLine(b0, b1, ink, 1.6f, devices_->stroke);
        }
        const HRESULT drawn = target->EndDraw();
        ReleaseCom(halo);
        ReleaseCom(ring);
        ReleaseCom(ink_dim);
        ReleaseCom(ink);
        if (FAILED(drawn)) {
          ::ZeroMemory(bitmap.bits, bytes);
        }
      }
      target->Release();
      target = nullptr;
    }
  }

  POINT source{0, 0};
  SIZE size{width, height};
  BLENDFUNCTION blend{};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 255;
  blend.AlphaFormat = AC_SRC_ALPHA;
  // NULL destination keeps the position set by dragging or by CreateWindowEx.
  ::UpdateLayeredWindow(hwnd_, bitmap.screen, nullptr, &size, bitmap.mem, &source, 0,
                        &blend, ULW_ALPHA);
  painting_ = false;
}

void LyricsWindow::NotifyClosed() {
  if (notifying_) {
    return;
  }
  notifying_ = true;
  Hide();
  const std::function<void()> callback = closed_;
  if (callback) {
    callback();
  }
  notifying_ = false;
}

void LyricsWindow::HandleDpi(const RECT* suggested) {
  if (hwnd_ == nullptr) {
    return;
  }
  const UINT dpi = WindowDpi();
  const int width = ScalePx(kLogicalWidth, dpi);
  const int height = ScalePx(kLogicalHeight, dpi);
  int x = 0;
  int y = 0;
  if (suggested != nullptr) {
    x = suggested->left;
    y = suggested->top;
  } else {
    RECT rect{};
    ::GetWindowRect(hwnd_, &rect);
    x = rect.left;
    y = rect.top;
  }
  ::SetWindowPos(hwnd_, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
  Paint();
}

bool LyricsWindow::HitClose(POINT client) const {
  const UINT dpi = WindowDpi();
  const float scale = static_cast<float>(dpi) / 96.0f;
  if (scale <= 0.0f) {
    return false;
  }
  const float x = static_cast<float>(client.x) / scale;
  const float y = static_cast<float>(client.y) / scale;
  const float strip = kCloseSize + kCloseMargin;
  return x >= static_cast<float>(kLogicalWidth) - strip &&
         x < static_cast<float>(kLogicalWidth) && y >= 0.0f &&
         y < static_cast<float>(kLogicalHeight);
}

LRESULT CALLBACK LyricsWindow::WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                       LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* created = reinterpret_cast<CREATESTRUCTW*>(lparam);
    auto* self = created == nullptr
                     ? nullptr
                     : reinterpret_cast<LyricsWindow*>(created->lpCreateParams);
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    if (self != nullptr) {
      self->hwnd_ = hwnd;
    }
    return ::DefWindowProcW(hwnd, message, wparam, lparam);
  }
  auto* self = reinterpret_cast<LyricsWindow*>(::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self == nullptr) {
    return ::DefWindowProcW(hwnd, message, wparam, lparam);
  }
  return self->Handle(hwnd, message, wparam, lparam);
}

LRESULT LyricsWindow::Handle(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      ::BeginPaint(hwnd, &paint);
      ::EndPaint(hwnd, &paint);
      return 0;
    }
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_SETCURSOR:
      if (LOWORD(lparam) == HTCLIENT) {
        POINT cursor{};
        ::GetCursorPos(&cursor);
        ::ScreenToClient(hwnd, &cursor);
        const wchar_t* cursor_id = HitClose(cursor) ? IDC_HAND : IDC_ARROW;
        ::SetCursor(::LoadCursorW(nullptr, cursor_id));
        return TRUE;
      }
      break;
    case WM_LBUTTONDOWN: {
      POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      if (HitClose(pt)) {
        close_pressed_ = true;
        ::SetCapture(hwnd);
        return 0;
      }
      ::ReleaseCapture();
      ::SendMessageW(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      return 0;
    }
    case WM_LBUTTONUP:
      if (close_pressed_) {
        close_pressed_ = false;
        ::ReleaseCapture();
        POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        if (HitClose(pt)) {
          NotifyClosed();
        }
      }
      return 0;
    case WM_CAPTURECHANGED:
      close_pressed_ = false;
      return 0;
    case WM_DPICHANGED:
      HandleDpi(reinterpret_cast<const RECT*>(lparam));
      return 0;
    case WM_SYSCOMMAND: {
      const UINT command = static_cast<UINT>(wparam & 0xFFF0);
      if (command == SC_CLOSE) {
        NotifyClosed();
        return 0;
      }
      if (command == SC_MAXIMIZE) {
        return 0;
      }
      break;
    }
    case WM_CLOSE:
      NotifyClosed();
      return 0;
    case WM_DESTROY:
      hwnd_ = nullptr;
      ::SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
      return 0;
    default:
      break;
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}
