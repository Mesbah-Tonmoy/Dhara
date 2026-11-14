#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kWindowChannel[] = "dhara/window";

// The smallest size the window can be dragged to, in logical pixels: below
// it the title bar and the navigation rail no longer fit.
constexpr int kMinWidth = 940;
constexpr int kMinHeight = 560;

// The player's fullscreen (media_kit_video) takes the frame styles off the
// window; that is how fullscreen is told apart.
bool IsFullscreen(HWND hwnd) {
  return (::GetWindowLongPtr(hwnd, GWL_STYLE) & WS_THICKFRAME) == 0;
}

// Hands the mouse button that is down to the system as a press on a part of
// the window frame, which starts its own move or resize loop (with snapping).
void StartFrameDrag(HWND hwnd, WPARAM hit) {
  POINT cursor;
  ::GetCursorPos(&cursor);
  ::ReleaseCapture();
  ::PostMessage(hwnd, WM_NCLBUTTONDOWN, hit, MAKELPARAM(cursor.x, cursor.y));
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

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowChannel,
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleWindowCall(call, std::move(result));
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
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

flutter::EncodableValue FlutterWindow::WindowState(HWND hwnd) const {
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("maximized"),
       flutter::EncodableValue(::IsZoomed(hwnd) != FALSE)},
      {flutter::EncodableValue("fullscreen"),
       flutter::EncodableValue(IsFullscreen(hwnd))},
  });
}

void FlutterWindow::NotifyWindowState(HWND hwnd) {
  if (!window_channel_) {
    return;
  }
  const bool maximized = ::IsZoomed(hwnd) != FALSE;
  const bool fullscreen = IsFullscreen(hwnd);
  if (maximized == told_maximized_ && fullscreen == told_fullscreen_) {
    return;
  }
  told_maximized_ = maximized;
  told_fullscreen_ = fullscreen;
  window_channel_->InvokeMethod(
      "stateChanged",
      std::make_unique<flutter::EncodableValue>(WindowState(hwnd)));
}

void FlutterWindow::HandleWindowCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    result->Error("no-window", "The window is gone.");
    return;
  }
  const std::string& method = call.method_name();

  if (method == "setCustomFrame") {
    const auto* enabled = std::get_if<bool>(call.arguments());
    custom_frame_ = enabled != nullptr && *enabled;
    // Makes the system work the frame out again (WM_NCCALCSIZE below).
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                       SWP_FRAMECHANGED);
    told_maximized_ = ::IsZoomed(hwnd) != FALSE;
    told_fullscreen_ = IsFullscreen(hwnd);
    result->Success(WindowState(hwnd));
  } else if (method == "startDrag") {
    StartFrameDrag(hwnd, HTCAPTION);
    result->Success();
  } else if (method == "startResize") {
    const auto* edge = std::get_if<std::string>(call.arguments());
    if (edge == nullptr) {
      result->Error("bad-edge", "startResize needs the name of an edge.");
    } else if (*edge == "top") {
      StartFrameDrag(hwnd, HTTOP);
      result->Success();
    } else if (*edge == "topLeft") {
      StartFrameDrag(hwnd, HTTOPLEFT);
      result->Success();
    } else if (*edge == "topRight") {
      StartFrameDrag(hwnd, HTTOPRIGHT);
      result->Success();
    } else {
      result->Error("bad-edge", "Unknown edge.");
    }
  } else if (method == "minimize") {
    ::ShowWindow(hwnd, SW_MINIMIZE);
    result->Success();
  } else if (method == "toggleMaximize") {
    ::ShowWindow(hwnd, ::IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
    result->Success();
  } else if (method == "close") {
    ::PostMessage(hwnd, WM_CLOSE, 0, 0);
    result->Success();
  } else {
    result->NotImplemented();
  }
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

    case WM_NCCALCSIZE:
      // With the app's own title bar the caption is taken out of the frame:
      // the client area starts at the very top of the window. The left, right
      // and bottom borders stay the system's, so resizing there, snapping,
      // the shadow and the rounded corners work as for any window. Fullscreen
      // has no frame at all and is left alone.
      if (custom_frame_ && wparam == TRUE && !IsFullscreen(hwnd)) {
        auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        const LONG top = params->rgrc[0].top;
        const LRESULT result = ::DefWindowProc(hwnd, message, wparam, lparam);
        if (result != 0) {
          return result;
        }
        params->rgrc[0].top = top;
        if (::IsZoomed(hwnd)) {
          // A maximized window hangs over the edges of its monitor by the
          // thickness of the frame; keep that much off the top as well, or
          // the first rows of the title bar would be off screen.
          const UINT dpi = ::GetDpiForWindow(hwnd);
          params->rgrc[0].top +=
              ::GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) +
              ::GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
        }
        return 0;
      }
      break;

    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = ::GetDpiForWindow(hwnd);
      info->ptMinTrackSize.x = ::MulDiv(kMinWidth, dpi, USER_DEFAULT_SCREEN_DPI);
      info->ptMinTrackSize.y =
          ::MulDiv(kMinHeight, dpi, USER_DEFAULT_SCREEN_DPI);
      return 0;
    }

    case WM_SIZE:
    case WM_STYLECHANGED: {
      const LRESULT result =
          Win32Window::MessageHandler(hwnd, message, wparam, lparam);
      NotifyWindowState(hwnd);
      return result;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
