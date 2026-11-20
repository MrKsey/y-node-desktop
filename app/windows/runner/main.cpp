#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// The window title carries the live tunnel state, so the second launch cannot
// look the window up by its title any more. The process image name stays the
// same, and checking it keeps the search from picking up another Flutter
// window of an unrelated application.
bool IsYNodeProcess(DWORD pid) {
  HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) {
    return false;
  }
  wchar_t path[MAX_PATH];
  DWORD size = MAX_PATH;
  bool match = false;
  if (::QueryFullProcessImageNameW(process, 0, path, &size)) {
    const wchar_t* name = ::wcsrchr(path, L'\\');
    name = name == nullptr ? path : name + 1;
    match = ::_wcsicmp(name, L"y_node_desktop.exe") == 0;
  }
  ::CloseHandle(process);
  return match;
}

BOOL CALLBACK FindAppWindow(HWND window, LPARAM param) {
  // The process owns helper windows of its own (the taskbar restart watcher,
  // IME windows). Only the Flutter runner window can be brought back.
  wchar_t class_name[64];
  if (::GetClassNameW(window, class_name, 64) == 0 ||
      ::_wcsicmp(class_name, L"FLUTTER_RUNNER_WIN32_WINDOW") != 0) {
    return TRUE;
  }
  DWORD pid = 0;
  ::GetWindowThreadProcessId(window, &pid);
  if (!IsYNodeProcess(pid)) {
    return TRUE;
  }
  *reinterpret_cast<HWND*>(param) = window;
  return FALSE;
}

HWND FindExistingWindow() {
  HWND window = nullptr;
  ::EnumWindows(FindAppWindow, reinterpret_cast<LPARAM>(&window));
  return window;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // A second copy would start a second core and fight over the proxy ports and
  // the configuration file. The named mutex keeps one instance per session; a
  // second launch brings the existing window to the front instead.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, FALSE, L"Y-Node-Desktop-SingleInstance");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = FindExistingWindow();
    if (existing != nullptr) {
      if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      } else if (!::IsWindowVisible(existing)) {
        // A logon launch waits in the tray; a later click on the shortcut has
        // to bring that hidden window back.
        ::ShowWindow(existing, SW_SHOWNORMAL);
      }
      ::SetForegroundWindow(existing);
    }
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1050, 858);
  if (!window.Create(L"Y-Node", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
