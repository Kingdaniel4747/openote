#include "screen_capture.h"

#include <dwmapi.h>
#include <wincodec.h>
#include <windowsx.h>
#include <wrl/client.h>

#include <algorithm>
#include <vector>

namespace {

constexpr wchar_t kCaptureClass[] = L"OpenoteScreenCaptureOverlay";

RECT SelectionRect(POINT a, POINT b) {
  return {std::min(a.x, b.x), std::min(a.y, b.y), std::max(a.x, b.x),
          std::max(a.y, b.y)};
}

bool RegisterCaptureClass() {
  static const bool registered = [] {
    WNDCLASSW wc{};
    wc.lpfnWndProc = ScreenCapture::WindowProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_CROSS);
    wc.lpszClassName = kCaptureClass;
    return RegisterClassW(&wc) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
  }();
  return registered;
}

}  // namespace

ScreenCapture::ScreenCapture(HWND host, flutter::BinaryMessenger* messenger)
    : host_(host),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "openote/screen_capture",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<Result> result) {
        if (call.method_name() == "selectRegion") {
          Start(std::move(result));
        } else {
          result->NotImplemented();
        }
      });
}

ScreenCapture::~ScreenCapture() {
  channel_->SetMethodCallHandler(nullptr);
  if (overlay_ != nullptr) DestroyWindow(overlay_);
  if (pending_) pending_->Error("cancelled", "Screen selection was cancelled.");
}

bool ScreenCapture::Start(std::unique_ptr<Result> result) {
  if (pending_) {
    result->Error("busy", "A screen selection is already open.");
    return false;
  }
  if (!RegisterCaptureClass()) {
    result->Error("overlay", "Could not create the screen selection overlay.");
    return false;
  }

  pending_ = std::move(result);
  // The virtual screen deliberately covers every monitor, including monitors
  // arranged left or above the primary display (negative desktop coordinates).
  const int x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  screen_origin_ = {x, y};
  ShowWindow(host_, SW_HIDE);
  overlay_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
                              kCaptureClass, L"", WS_POPUP, x, y, width,
                              height, nullptr, nullptr, GetModuleHandle(nullptr), this);
  if (overlay_ == nullptr) {
    ShowWindow(host_, SW_SHOW);
    pending_->Error("overlay", "Could not show the screen selection overlay.");
    pending_.reset();
    return false;
  }
  SetLayeredWindowAttributes(overlay_, 0, 92, LWA_ALPHA);
  ShowWindow(overlay_, SW_SHOW);
  SetForegroundWindow(overlay_);
  return true;
}

void ScreenCapture::Finish(bool accepted) {
  if (!pending_) return;
  const RECT selection = SelectionRect(start_, current_);
  if (overlay_ != nullptr) {
    DestroyWindow(overlay_);
    overlay_ = nullptr;
    // The desktop compositor may still hold the dim selection overlay for a
    // frame after the HWND is destroyed. Flush before BitBlt so the PNG never
    // contains its own crosshair or dark veil.
    DwmFlush();
  }

  std::vector<uint8_t> png;
  if (accepted && selection.right - selection.left > 2 &&
      selection.bottom - selection.top > 2 && EncodeSelection(&png)) {
    pending_->Success(flutter::EncodableValue(png));
  } else if (accepted) {
    pending_->Error("capture", "Could not capture that screen area.");
  } else {
    pending_->Success(); // Escape/right-click is an ordinary cancellation.
  }
  pending_.reset();
  ShowWindow(host_, SW_SHOW);
  SetForegroundWindow(host_);
}

bool ScreenCapture::EncodeSelection(std::vector<uint8_t>* png) const {
  RECT rect = SelectionRect(start_, current_);
  rect.left += screen_origin_.x;
  rect.right += screen_origin_.x;
  rect.top += screen_origin_.y;
  rect.bottom += screen_origin_.y;
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  if (width <= 2 || height <= 2) return false;

  HDC desktop = GetDC(nullptr);
  HDC memory = CreateCompatibleDC(desktop);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;  // top-down BGRA rows
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  HBITMAP bitmap = CreateDIBSection(desktop, &info, DIB_RGB_COLORS, &pixels,
                                    nullptr, 0);
  if (bitmap == nullptr || memory == nullptr || desktop == nullptr) {
    if (bitmap) DeleteObject(bitmap);
    if (memory) DeleteDC(memory);
    if (desktop) ReleaseDC(nullptr, desktop);
    return false;
  }
  HGDIOBJ old = SelectObject(memory, bitmap);
  const bool copied = BitBlt(memory, 0, 0, width, height, desktop, rect.left,
                             rect.top, SRCCOPY | CAPTUREBLT) != 0;
  SelectObject(memory, old);
  DeleteDC(memory);
  ReleaseDC(nullptr, desktop);
  if (!copied) {
    DeleteObject(bitmap);
    return false;
  }

  Microsoft::WRL::ComPtr<IWICImagingFactory> factory;
  Microsoft::WRL::ComPtr<IWICBitmap> source;
  Microsoft::WRL::ComPtr<IStream> stream;
  Microsoft::WRL::ComPtr<IWICBitmapEncoder> encoder;
  Microsoft::WRL::ComPtr<IWICBitmapFrameEncode> frame;
  bool encoded = false;
  if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                 CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory))) &&
      SUCCEEDED(factory->CreateBitmapFromMemory(
          width, height, GUID_WICPixelFormat32bppBGRA, width * 4,
          width * height * 4, static_cast<BYTE*>(pixels), &source)) &&
      SUCCEEDED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)) &&
      SUCCEEDED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                       &encoder)) &&
      SUCCEEDED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache)) &&
      SUCCEEDED(encoder->CreateNewFrame(&frame, nullptr)) &&
      SUCCEEDED(frame->Initialize(nullptr)) &&
      SUCCEEDED(frame->WriteSource(source.Get(), nullptr)) &&
      SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit())) {
    HGLOBAL global = nullptr;
    if (SUCCEEDED(GetHGlobalFromStream(stream.Get(), &global))) {
      const SIZE_T length = GlobalSize(global);
      const auto* bytes = static_cast<const uint8_t*>(GlobalLock(global));
      if (bytes != nullptr && length > 0) {
        png->assign(bytes, bytes + length);
        GlobalUnlock(global);
        encoded = true;
      }
    }
  }
  DeleteObject(bitmap);
  return encoded;
}

void ScreenCapture::Paint() {
  PAINTSTRUCT ps{};
  HDC dc = BeginPaint(overlay_, &ps);
  RECT client{};
  GetClientRect(overlay_, &client);
  FillRect(dc, &client, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
  if (selecting_) {
    RECT rect = SelectionRect(start_, current_);
    HBRUSH hollow = static_cast<HBRUSH>(GetStockObject(HOLLOW_BRUSH));
    HGDIOBJ old_brush = SelectObject(dc, hollow);
    HPEN pen = CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
    HGDIOBJ old_pen = SelectObject(dc, pen);
    Rectangle(dc, rect.left, rect.top, rect.right, rect.bottom);
    SelectObject(dc, old_pen);
    SelectObject(dc, old_brush);
    DeleteObject(pen);
  }
  const HPEN cross = CreatePen(PS_SOLID, 1, RGB(255, 255, 255));
  HGDIOBJ old = SelectObject(dc, cross);
  MoveToEx(dc, current_.x - 10, current_.y, nullptr);
  LineTo(dc, current_.x + 11, current_.y);
  MoveToEx(dc, current_.x, current_.y - 10, nullptr);
  LineTo(dc, current_.x, current_.y + 11);
  SelectObject(dc, old);
  DeleteObject(cross);
  EndPaint(overlay_, &ps);
}

LRESULT CALLBACK ScreenCapture::WindowProc(HWND hwnd, UINT message,
                                            WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<ScreenCapture*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<const CREATESTRUCT*>(lparam);
    self = static_cast<ScreenCapture*>(create->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (self == nullptr) return DefWindowProc(hwnd, message, wparam, lparam);
  switch (message) {
    case WM_MOUSEMOVE:
      self->current_ = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    case WM_LBUTTONDOWN:
      self->start_ = self->current_ = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      self->selecting_ = true;
      SetCapture(hwnd);
      InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    case WM_LBUTTONUP:
      self->current_ = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ReleaseCapture();
      self->Finish(true);
      return 0;
    case WM_RBUTTONDOWN:
    case WM_KEYDOWN:
      if (message == WM_RBUTTONDOWN || wparam == VK_ESCAPE) {
        self->Finish(false);
        return 0;
      }
      break;
    case WM_PAINT:
      self->Paint();
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}
