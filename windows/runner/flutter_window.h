#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that hosts a Flutter view and, when the app asks for it, gives up
// the system title bar so that the app can draw its own.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Answers the app's calls on the "dhara/window" channel: its own title bar
  // moves, resizes, minimizes, maximizes and closes the window through it.
  void HandleWindowCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Whether the window is maximized and whether it is fullscreen, as the app
  // is told.
  flutter::EncodableValue WindowState(HWND hwnd) const;

  // Tells the app if that state has changed since it was last told.
  void NotifyWindowState(HWND hwnd);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // True once the app draws the title bar itself: the caption is then taken
  // out of the window frame.
  bool custom_frame_ = false;
  bool told_maximized_ = false;
  bool told_fullscreen_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
