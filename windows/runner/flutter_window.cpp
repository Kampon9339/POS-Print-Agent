#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;
constexpr UINT_PTR kTrayMenuStatusId = 1001;
constexpr UINT_PTR kTrayMenuShowId = 1002;
constexpr UINT_PTR kTrayMenuQuitId = 1003;
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
  SetupTrayChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTray();
  tray_channel_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetupTrayChannel() {
  tray_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.pos.printagent/tray",
          &flutter::StandardMethodCodec::GetInstance());

  tray_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());

        if (method == "initTray") {
          std::wstring status = tray_status_text_;
          if (args) {
            auto status_it = args->find(flutter::EncodableValue("status"));
            if (status_it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&status_it->second)) {
                status = Utf8ToWide(*s);
              }
            }
            auto open_it = args->find(flutter::EncodableValue("openLabel"));
            if (open_it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&open_it->second)) {
                tray_open_label_ = Utf8ToWide(*s);
              }
            }
            auto quit_it = args->find(flutter::EncodableValue("quitLabel"));
            if (quit_it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&quit_it->second)) {
                tray_quit_label_ = Utf8ToWide(*s);
              }
            }
          }
          InitTray(status);
          result->Success(flutter::EncodableValue(true));
        } else if (method == "updateTrayStatus") {
          if (args) {
            auto status_it = args->find(flutter::EncodableValue("status"));
            if (status_it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&status_it->second)) {
                UpdateTrayStatus(Utf8ToWide(*s));
              }
            }
          }
          result->Success(flutter::EncodableValue(true));
        } else if (method == "hideWindow") {
          start_hidden_ = true;
          if (!tray_initialized_) {
            InitTray(tray_status_text_);
          }
          HWND hwnd = GetHandle();
          if (hwnd) {
            ShowWindow(hwnd, SW_HIDE);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (method == "showWindow") {
          ShowMainWindow();
          result->Success(flutter::EncodableValue(true));
        } else if (method == "terminateApp") {
          allow_force_close_ = true;
          RemoveTray();
          HWND hwnd = GetHandle();
          result->Success(flutter::EncodableValue(true));
          if (hwnd) {
            DestroyWindow(hwnd);
          }
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::InitTray(const std::wstring& status_text) {
  tray_status_text_ = status_text;
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  if (tray_initialized_) {
    UpdateTrayStatus(status_text);
    return;
  }

  ZeroMemory(&tray_icon_data_, sizeof(tray_icon_data_));
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_data_.hWnd = hwnd;
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_data_.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));

  std::wstring tip = L"POS Print Agent - " + tray_status_text_;
  wcsncpy_s(tray_icon_data_.szTip, ARRAYSIZE(tray_icon_data_.szTip),
            tip.c_str(), _TRUNCATE);

  if (Shell_NotifyIconW(NIM_ADD, &tray_icon_data_)) {
    tray_initialized_ = true;
  }
}

void FlutterWindow::UpdateTrayStatus(const std::wstring& status_text) {
  tray_status_text_ = status_text;
  if (!tray_initialized_) {
    InitTray(status_text);
    return;
  }

  std::wstring tip = L"POS Print Agent - " + tray_status_text_;
  wcsncpy_s(tray_icon_data_.szTip, ARRAYSIZE(tray_icon_data_.szTip),
            tip.c_str(), _TRUNCATE);
  tray_icon_data_.uFlags = NIF_TIP;
  Shell_NotifyIconW(NIM_MODIFY, &tray_icon_data_);
}

void FlutterWindow::RemoveTray() {
  if (tray_initialized_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
    tray_initialized_ = false;
  }
}

void FlutterWindow::ShowTrayContextMenu(HWND hwnd) {
  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }

  AppendMenuW(menu, MF_STRING | MF_GRAYED, kTrayMenuStatusId,
              tray_status_text_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuShowId, tray_open_label_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuQuitId, tray_quit_label_.c_str());

  POINT pt;
  GetCursorPos(&pt);
  SetForegroundWindow(hwnd);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, pt.x, pt.y, 0, hwnd,
                 nullptr);
  PostMessage(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);
}

void FlutterWindow::ShowMainWindow() {
  start_hidden_ = false;
  HWND hwnd = GetHandle();
  if (hwnd) {
    ShowWindow(hwnd, SW_RESTORE);
    ShowWindow(hwnd, SW_SHOW);
    SetForegroundWindow(hwnd);
  }
}

std::wstring FlutterWindow::Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int size_needed = MultiByteToWideChar(
      CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), nullptr, 0);
  if (size_needed <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(size_needed), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      &wide[0], size_needed);
  return wide;
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

    case WM_CLOSE:
      if (!allow_force_close_) {
        if (!tray_initialized_) {
          InitTray(tray_status_text_);
        }
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;

    case WM_QUERYENDSESSION:
    case WM_ENDSESSION:
      allow_force_close_ = true;
      break;

    case kTrayCallbackMessage:
      if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
        ShowMainWindow();
        if (tray_channel_) {
          tray_channel_->InvokeMethod("onTrayShowWindow", nullptr);
        }
        return 0;
      } else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
        ShowTrayContextMenu(hwnd);
        return 0;
      }
      break;

    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kTrayMenuShowId:
          ShowMainWindow();
          if (tray_channel_) {
            tray_channel_->InvokeMethod("onTrayShowWindow", nullptr);
          }
          return 0;
        case kTrayMenuQuitId:
          if (tray_channel_) {
            tray_channel_->InvokeMethod("onTrayQuitApp", nullptr);
          } else {
            allow_force_close_ = true;
            RemoveTray();
            DestroyWindow(hwnd);
          }
          return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
