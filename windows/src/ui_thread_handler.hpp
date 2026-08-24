#pragma once

#include <windows.h>

#include <flutter/plugin_registrar_windows.h>

#include <algorithm>
#include <functional>
#include <list>
#include <mutex>
#include <optional>

class UniversalBleUiThreadHandler
{
public:
    explicit UniversalBleUiThreadHandler(flutter::PluginRegistrarWindows *registrar)
        : registrar_(registrar)
    {
        windowProcId_ = registrar_->RegisterTopLevelWindowProcDelegate(
            [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
            {
                return HandleWindowMessage(hwnd, message, wparam, lparam);
            });
    }

    ~UniversalBleUiThreadHandler() { Shutdown(); }

    UniversalBleUiThreadHandler(const UniversalBleUiThreadHandler &) = delete;
    UniversalBleUiThreadHandler &operator=(const UniversalBleUiThreadHandler &) = delete;

    void Post(std::function<void()> &&func)
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (!accepting_) {
                return;
            }
            queuedFuncs_.emplace_back(std::move(func));
        }
        Notify();
    }

    void Shutdown()
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (!accepting_) {
                return;
            }
            accepting_ = false;
            queuedFuncs_.clear();
        }
        registrar_->UnregisterTopLevelWindowProcDelegate(windowProcId_);
    }

private:
    static const UINT kWmCallQueuedFunctions = WM_APP + 0x1d7;

    void Notify()
    {
        if (hwnd_ != 0)
        {
            PostMessage(hwnd_, kWmCallQueuedFunctions, 0, reinterpret_cast<LPARAM>(this));
        }
    }

    std::optional<LRESULT> HandleWindowMessage(
        HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
    {
        if (hwnd_ == 0)
        {
            hwnd_ = hwnd;
            Notify(); // Make sure queued functions are processed
        }
        if (message == kWmCallQueuedFunctions && lparam == reinterpret_cast<LPARAM>(this))
        {
            std::list<std::function<void()>> queuedFuncs;
            {
                std::lock_guard<std::mutex> lock(mutex_);
                if (!accepting_) {
                    return std::nullopt;
                }
                std::swap(queuedFuncs_, queuedFuncs);
            }
            for (auto &func : queuedFuncs)
            {
                func();
            }
        }
        return std::nullopt;
    }

    flutter::PluginRegistrarWindows *registrar_;
    int windowProcId_ = 0;
    HWND hwnd_ = 0;
    std::list<std::function<void()>> queuedFuncs_;
    std::mutex mutex_;
    bool accepting_ = true;
};
