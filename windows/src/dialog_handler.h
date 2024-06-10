#pragma once

#include <windows.h>
#include <tchar.h>

namespace universal_ble
{

    typedef struct SizeAndPos_s
    {
        int x, y, width, height;
    } SizeAndPos_t;

    const WORD ID_btnOk = 1;
    const WORD ID_btnCancel = 2;
    const WORD ID_txtEdit = 4;
    HWND txtEditHandle = NULL;
    TCHAR textBoxText[256];

    // Location and Dimensions of ui elements: X, Y, Width, Height
    const SizeAndPos_t mainWindow = {150, 150, 300, 200};
    const SizeAndPos_t txtEdit = {50, 50, 170, 20};
    const SizeAndPos_t btnCancel = {50, 90, 80, 25};
    const SizeAndPos_t btnOk = {150, 90, 80, 25};

    LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
    {
        switch (msg)
        {
        case WM_CREATE:
            txtEditHandle = CreateWindow(TEXT("Edit"), TEXT(""), WS_CHILD | WS_VISIBLE | WS_BORDER, txtEdit.x, txtEdit.y, txtEdit.width, txtEdit.height, hwnd, (HMENU)ID_txtEdit, NULL, NULL);
            CreateWindow(TEXT("Button"), TEXT("Ok"), WS_VISIBLE | WS_CHILD, btnOk.x, btnOk.y, btnOk.width, btnOk.height, hwnd, (HMENU)ID_btnOk, NULL, NULL);
            CreateWindow(TEXT("Button"), TEXT("Cancel"), WS_VISIBLE | WS_CHILD, btnCancel.x, btnCancel.y, btnCancel.width, btnCancel.height, hwnd, (HMENU)ID_btnCancel, NULL, NULL);
            break;
        case WM_COMMAND:
            if (LOWORD(wParam) == ID_btnCancel)
            {
                DestroyWindow(hwnd);
            }
            else if (LOWORD(wParam) == ID_btnOk)
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
        mainWindowClass.hbrBackground = GetSysColorBrush(COLOR_3DFACE);
        mainWindowClass.lpfnWndProc = WndProc;
        mainWindowClass.hCursor = LoadCursor(0, IDC_ARROW);
        RegisterClass(&mainWindowClass);
        CreateWindow(mainWindowClass.lpszClassName, TEXT("Enter Pairing Pin"), WS_OVERLAPPEDWINDOW | WS_VISIBLE, mainWindow.x, mainWindow.y, mainWindow.width, mainWindow.height, NULL, 0, hInstance, NULL);
        while (GetMessage(&msg, NULL, 0, 0))
        {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        return winrt::to_hstring(textBoxText);
    }
}