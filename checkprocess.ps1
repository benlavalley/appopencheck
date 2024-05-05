# Check if a process is running and not minimized for the current user, v1.0
# Coming soon as a native script check to an RMM vendor near you? ;) 
# Ben Lavalley - 5/5/24

param(
    [Parameter(Mandatory = $true, HelpMessage = "Please provide the process name")]
    [string]$ProcessName,

    [Parameter(Mandatory = $false, HelpMessage = "Optional delay in seconds before the check.")]
    [int]$DelaySeconds = 0
)

Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;

    public static class User32 {
        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsIconic(IntPtr hWnd);

        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    }
"@

$script:foundVisibleWindow = $false

$scriptBlock = {
    param ([IntPtr]$hWnd, [IntPtr]$lParam)
    $processId = 0
    [User32]::GetWindowThreadProcessId($hWnd, [ref]$processId)
    $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue

    if ($proc -and $proc.ProcessName -eq $ProcessName) {
        $windowVisible = [User32]::IsWindowVisible($hWnd)
        $windowMinimized = [User32]::IsIconic($hWnd)

        if ($windowVisible -and -not $windowMinimized) {
            $sb = New-Object System.Text.StringBuilder 256
            [User32]::GetWindowText($hWnd, $sb, $sb.Capacity)
            [string]$windowTitle = $sb.ToString()

            $windowTitleText = if (![string]::IsNullOrWhiteSpace($windowTitle)) { "'$windowTitle'" } else { "(no title)" }
            Write-Host "$ProcessName window is visible with title: $windowTitleText"

            $script:foundVisibleWindow = $true
            [System.Runtime.InteropServices.Marshal]::WriteInt32($lParam, 1) # Store state
            return $false # Stop enumeration on first visible non-minimized window
        }

        return $true # Continue enumeration
    }
    return $true # Continue enumeration for other windows
}

if ($DelaySeconds -gt 0) {
    Write-Host "Waiting for $DelaySeconds seconds before checking..."
    Start-Sleep -Seconds $DelaySeconds
}

$foundStatePtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal([System.IntPtr]::Size)
try {
    $callback = [User32+EnumWindowsProc]$scriptBlock
    [User32]::EnumWindows($callback, $foundStatePtr) | Out-Null
    $foundState = [System.Runtime.InteropServices.Marshal]::ReadInt32($foundStatePtr)

    if ($foundState -eq 1) {
        Write-Host "Summary: A visible window for '$ProcessName' was found and reported."
    } else {
        Write-Host "Summary: No visible non-minimized windows found for '$ProcessName'."
    }
} finally {
    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($foundStatePtr)
}
