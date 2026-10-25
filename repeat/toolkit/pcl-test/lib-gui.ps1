# GUI helpers for the PCL PoC demo VM.
# ASCII only. Windows PowerShell 5.1 compatible.

if (-not ('PclGui' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class PclGui
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("user32.dll")]
    public static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CONSOLE_FONT_INFO_EX
    {
        public uint cbSize;
        public uint nFont;
        public short dwFontSizeX;
        public short dwFontSizeY;
        public uint FontFamily;
        public uint FontWeight;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string FaceName;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetCurrentConsoleFontEx(IntPtr hConsoleOutput, bool bMaximumWindow, ref CONSOLE_FONT_INFO_EX lpConsoleCurrentFontEx);

    public static string SetBestResolution()
    {
        int[][] prefs = new int[][]
        {
            new int[] { 1920, 1080 },
            new int[] { 1600, 900 },
            new int[] { 1366, 768 },
            new int[] { 1280, 720 },
            new int[] { 1024, 768 }
        };

        foreach (int[] pref in prefs)
        {
            DEVMODE found = new DEVMODE();
            found.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            bool ok = false;
            for (int i = 0; EnumDisplaySettings(null, i, ref found); i++)
            {
                if (found.dmPelsWidth == pref[0] && found.dmPelsHeight == pref[1] && found.dmBitsPerPel == 32)
                {
                    ok = true;
                    break;
                }
            }
            if (!ok) continue;

            DEVMODE set = found;
            set.dmFields = 0x80000 | 0x100000 | 0x40000; // width, height, bits per pixel
            int r = ChangeDisplaySettings(ref set, 0x00000001); // CDS_UPDATEREGISTRY
            if (r == 0)
            {
                return pref[0].ToString() + "x" + pref[1].ToString();
            }
        }
        return "unchanged";
    }

    public static bool SetConsoleFont(int size)
    {
        IntPtr h = GetStdHandle(-11);
        if (h == IntPtr.Zero) return false;
        CONSOLE_FONT_INFO_EX f = new CONSOLE_FONT_INFO_EX();
        f.cbSize = (uint)Marshal.SizeOf(typeof(CONSOLE_FONT_INFO_EX));
        f.nFont = 0;
        f.dwFontSizeX = 0;
        f.dwFontSizeY = (short)size;
        f.FontFamily = 54;
        f.FontWeight = 400;
        f.FaceName = "Consolas";
        return SetCurrentConsoleFontEx(h, false, ref f);
    }

    public static void Move(IntPtr h, int x, int y, int w, int hgt)
    {
        if (h == IntPtr.Zero) return;
        ShowWindow(h, 9); // SW_RESTORE
        SetWindowPos(h, IntPtr.Zero, x, y, w, hgt, 0x0040); // SWP_SHOWWINDOW
    }
}
'@
}

function Set-ConsoleSize {
    param([int]$Columns, [int]$Rows)
    try {
        $buffer = New-Object System.Management.Automation.Host.Size([Math]::Max($Columns, 120), 600)
        $Host.UI.RawUI.BufferSize = $buffer
    } catch { }
    try {
        $window = New-Object System.Management.Automation.Host.Size($Columns, $Rows)
        $Host.UI.RawUI.WindowSize = $window
    } catch { }
}
