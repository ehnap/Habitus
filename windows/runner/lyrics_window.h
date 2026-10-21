#ifndef RUNNER_LYRICS_WINDOW_H_
#define RUNNER_LYRICS_WINDOW_H_

#include <windows.h>

#include <functional>
#include <string>

// Layered popup that draws the current lyric line and the next one.
// Show and hide reuse one HWND. Hiding does not post a quit message.
class LyricsWindow {
 public:
  explicit LyricsWindow(HWND owner);
  ~LyricsWindow();

  LyricsWindow(const LyricsWindow&) = delete;
  LyricsWindow& operator=(const LyricsWindow&) = delete;

  // Creates the popup on the first call. Later calls show the same HWND.
  bool Show();
  void Hide();
  void SetLines(const std::wstring& current, const std::wstring& next);
  void SetClosedHandler(std::function<void()> handler);

 private:
  struct Devices;

  bool EnsureCreated();
  bool EnsureDevices();
  void ReleaseDevices();
  void Paint();
  void NotifyClosed();
  void HandleDpi(const RECT* suggested);
  bool HitClose(POINT client) const;
  UINT WindowDpi() const;
  void InitialOrigin(UINT dpi, int width, int height, int* x, int* y) const;
  LRESULT Handle(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);

  HWND owner_ = nullptr;
  HWND hwnd_ = nullptr;
  std::wstring current_;
  std::wstring next_;
  std::function<void()> closed_;
  bool close_pressed_ = false;
  bool notifying_ = false;
  bool painting_ = false;
  Devices* devices_ = nullptr;
};

#endif  // RUNNER_LYRICS_WINDOW_H_
