
#include <windows.h>
#include <tchar.h>
#include <string>
#include <iostream>

typedef struct SizeAndPos_s
{
    int x, y, width, height;
} SizeAndPos_t;

const WORD ID_btnOk = 1;
const WORD ID_DEVICEID = 1;
const WORD ID_txtEdit = 4;
HWND txtEditHandle = NULL;
TCHAR textBoxText[256];

// Location and Dimensions of ui elements: X, Y, Width, Height
const SizeAndPos_t mainWindow = {150, 150, 450, 200};
const SizeAndPos_t txtEdit = {60, 40, 300, 50};
const SizeAndPos_t btnOk = {60, 80, 300, 25};

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg)
    {
    case WM_CREATE:
    {
        txtEditHandle = CreateWindow(
            TEXT("Edit"), TEXT(""),
            WS_CHILD | WS_VISIBLE | WS_BORDER | ES_NUMBER,
            txtEdit.x, txtEdit.y, txtEdit.width, txtEdit.height,
            hwnd, (HMENU)ID_txtEdit, NULL, NULL);

        HFONT hFont = CreateFont(
            36,                       // Height of the font
            0,                        // Width of the font
            0,                        // Angle of escapement
            0,                        // Orientation angle
            FW_NORMAL,                // Font weight
            FALSE,                    // Italic attribute option
            FALSE,                    // Underline attribute option
            FALSE,                    // Strikeout attribute option
            DEFAULT_CHARSET,          // Character set identifier
            OUT_DEFAULT_PRECIS,       // Output precision
            CLIP_DEFAULT_PRECIS,      // Clipping precision
            DEFAULT_QUALITY,          // Output quality
            DEFAULT_PITCH | FF_SWISS, // Pitch and family
            TEXT("Arial"));           // Font name

        SendMessage(txtEditHandle, WM_SETFONT, (WPARAM)hFont, TRUE);

        CreateWindow(
            TEXT("Button"), TEXT("Ok"),
            WS_CHILD | WS_VISIBLE | BS_FLAT,
            btnOk.x, btnOk.y, btnOk.width, btnOk.height,
            hwnd, (HMENU)ID_btnOk, NULL, NULL);
    }
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

int main(int argc, char *argv[])
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

    while (GetMessage(&msg, NULL, 0, 0))
    {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
    std::wcout << textBoxText << std::endl;
    return 0;
}
