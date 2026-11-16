#pragma once

#include <windows.h>

#include <flutter/plugin_registrar_windows.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <functional>
#include <list>
#include <mutex>
#include <memory>
#include <unordered_map>
#include <optional>

class UniversalBleUiThreadHandler
    : public std::enable_shared_from_this<UniversalBleUiThreadHandler> {
public:
  explicit UniversalBleUiThreadHandler(
      flutter::PluginRegistrarWindows *registrar)
      : registrar_(registrar), ui_thread_id_(GetCurrentThreadId()) {
    windowProcId_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
          return HandleWindowMessage(hwnd, message, wparam, lparam);
        });
  }

  ~UniversalBleUiThreadHandler() { Shutdown(); }

  UniversalBleUiThreadHandler(const UniversalBleUiThreadHandler &) = delete;
  UniversalBleUiThreadHandler &operator=(const UniversalBleUiThreadHandler &) =
      delete;

  void Post(std::function<void()> &&func) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!accepting_) {
        return;
      }
      queuedFuncs_.emplace_back(std::move(func));
    }
    Notify();
  }

  // Only the UI thread owns the real Flutter reply. Native work captures
  // a weak endpoint and a key. Delivery consumes the reply exactly once.
  template <typename Value>
  std::function<void(Value)> BindReply(std::function<void(Value)> reply) {
    const auto id = next_reply_++;
    replies_.emplace(id, std::make_shared<std::function<void(Value)>>(
                             std::move(reply)));
    return [endpoint = weak_from_this(), id](Value value) {
      if (auto handler = endpoint.lock()) {
        auto deliver = [endpoint, id, value = std::move(value)]() mutable {
          auto ui = endpoint.lock();
          if (!ui) return;
          auto reply = ui->replies_.extract(id);
          if (!reply.empty()) {
            auto callback = std::static_pointer_cast<std::function<void(Value)>>(
                std::move(reply.mapped()));
            (*callback)(std::move(value));
          }
        };
        if (GetCurrentThreadId() == handler->ui_thread_id_) {
          deliver();
        } else {
          handler->Post(std::move(deliver));
        }
      }
    };
  }

  void Shutdown() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!accepting_) {
        return;
      }
      accepting_ = false;
      queuedFuncs_.clear();
    }
    replies_.clear();
    registrar_->UnregisterTopLevelWindowProcDelegate(windowProcId_);
    registrar_ = nullptr;
  }

private:
  static const UINT kWmCallQueuedFunctions = WM_APP + 0x1d7;

  void Notify() {
    const HWND window = hwnd_.load();
    if (window != nullptr) {
      PostMessage(window, kWmCallQueuedFunctions, 0,
                  reinterpret_cast<LPARAM>(this));
    }
  }

  std::optional<LRESULT> HandleWindowMessage(HWND hwnd, UINT message,
                                             WPARAM wparam, LPARAM lparam) {
    const auto keep_alive = weak_from_this().lock();
    if (hwnd_ == 0) {
      hwnd_ = hwnd;
      Notify();  // Make sure queued functions are processed
    }
    if (message == kWmCallQueuedFunctions &&
        lparam == reinterpret_cast<LPARAM>(this)) {
      std::list<std::function<void()>> queuedFuncs;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!accepting_) {
          return std::nullopt;
        }
        std::swap(queuedFuncs_, queuedFuncs);
      }
      for (auto &func : queuedFuncs) {
        if (!accepting_) break;
        func();
      }
    }
    return std::nullopt;
  }

  flutter::PluginRegistrarWindows *registrar_;
  std::unordered_map<uint64_t, std::shared_ptr<void>> replies_;
  uint64_t next_reply_ = 0;
  const DWORD ui_thread_id_;
  int windowProcId_ = 0;
  std::atomic<HWND> hwnd_{nullptr};
  std::list<std::function<void()>> queuedFuncs_;
  std::mutex mutex_;
  bool accepting_ = true;
};
