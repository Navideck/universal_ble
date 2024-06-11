#pragma once

#include <windows.h>
#include <tchar.h>

namespace universal_ble
{

    typedef struct SizeAndPos_s
    {
        int x, y, width, height;
    } SizeAndPos_t;

    // const SizeAndPos_t txtDeviceId = {60, 10, 300, 20};
    // const WORD ID_deviceId = 2;
    // HWND textTitleHandle = NULL;

    const WORD ID_btnOk = 1;
    const WORD ID_txtEdit = 4;
    HWND txtEditHandle = NULL;
    TCHAR textBoxText[256];

    // Location and Dimensions of ui elements: X, Y, Width, Height
    const SizeAndPos_t mainWindow = {150, 150, 450, 200};
    const SizeAndPos_t txtEdit = {60, 40, 300, 25};
    const SizeAndPos_t btnOk = {60, 80, 300, 25};

    LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
    {
        switch (msg)
        {
        case WM_CREATE:
            // textTitleHandle = CreateWindow(
            //     TEXT("STATIC"), TEXT("Bluetooth Device"),
            //     WS_CHILD | WS_VISIBLE | SS_CENTER,
            //     txtDeviceId.x, txtDeviceId.y, txtDeviceId.width, txtDeviceId.height,
            //     hwnd, (HMENU)ID_deviceId, NULL, NULL);
            txtEditHandle = CreateWindow(
                TEXT("Edit"), TEXT(""),
                WS_CHILD | WS_VISIBLE | WS_BORDER,
                txtEdit.x, txtEdit.y, txtEdit.width, txtEdit.height,
                hwnd, (HMENU)ID_txtEdit, NULL, NULL);
            CreateWindow(
                TEXT("Button"), TEXT("Ok"),
                WS_CHILD | WS_VISIBLE | BS_FLAT,
                btnOk.x, btnOk.y, btnOk.width, btnOk.height,
                hwnd, (HMENU)ID_btnOk, NULL, NULL);
            break;
        case WM_COMMAND:
            if (LOWORD(wParam) == ID_btnOk)
            {
                GetWindowText(txtEditHandle, textBoxText, sizeof(textBoxText) / sizeof(TCHAR));
                DestroyWindow(hwnd);
            }
            break;
        case WM_CLOSE:
            DestroyWindow(hwnd);
            break;
        case WM_DESTROY:
            PostQuitMessage(0);
            break;
        default:
            return DefWindowProc(hwnd, msg, wParam, lParam);
        }

        return 0;
    }

    hstring askForPairingPin()
    {
        textBoxText[0] = '\0';
        HINSTANCE hInstance = GetModuleHandle(NULL);
        MSG msg;
        WNDCLASS mainWindowClass = {0};
        mainWindowClass.lpszClassName = TEXT("JRH.MainWindow");
        mainWindowClass.hInstance = hInstance;
        mainWindowClass.hbrBackground = GetSysColorBrush(COLOR_BTNHIGHLIGHT);
        mainWindowClass.lpfnWndProc = WndProc;
        mainWindowClass.hCursor = LoadCursor(0, IDC_ARROW);
        RegisterClass(&mainWindowClass);

        HWND hwnd = CreateWindow(
            mainWindowClass.lpszClassName,
            TEXT("PIN"), WS_OVERLAPPEDWINDOW & ~WS_MINIMIZEBOX & ~WS_MAXIMIZEBOX | WS_VISIBLE,
            mainWindow.x, mainWindow.y, mainWindow.width, mainWindow.height,
            NULL, 0, hInstance, NULL);

        ShowWindow(hwnd, SW_SHOW);

        // TCHAR newText[] = TEXT("Bluetooth 73:32:8b:d5:a3");
        // SendMessage(textTitleHandle, WM_SETTEXT, 0, (LPARAM)newText);

        while (GetMessage(&msg, NULL, 0, 0))
        {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        return winrt::to_hstring(textBoxText);
    }
}