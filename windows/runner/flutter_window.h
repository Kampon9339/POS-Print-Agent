#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <shellapi.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that hosts a Flutter view and manages Windows System Tray
// integration so POS Print Agent stays running in the background.
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
  void SetupTrayChannel();
  void InitTray(const std::wstring& status_text);
  void UpdateTrayStatus(const std::wstring& status_text);
  void RemoveTray();
  void ShowTrayContextMenu(HWND hwnd);
  void ShowMainWindow();
  static std::wstring Utf8ToWide(const std::string& utf8);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // MethodChannel for com.pos.printagent/tray
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      tray_channel_;

  NOTIFYICONDATAW tray_icon_data_{};
  bool tray_initialized_ = false;
  bool allow_force_close_ = false;
  bool start_hidden_ = false;
  std::wstring tray_status_text_ = L"POS Print Agent (127.0.0.1:8765)";
  std::wstring tray_open_label_ = L"Open POS Print Agent";
  std::wstring tray_quit_label_ = L"Quit POS Print Agent";
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
