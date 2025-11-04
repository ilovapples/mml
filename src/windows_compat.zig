const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const kernel32 = windows.kernel32;

const mibu = @import("mibu");
const RawTerm = mibu.term.RawTerm;

// code copied from `xyaman/mibu` library
pub const ENABLE_PROCESSED_OUTPUT: windows.DWORD = 0x0001;
pub const ENABLE_PROCESSED_INPUT: windows.DWORD = 0x0001;
pub const ENABLE_VIRTUAL_TERMINAL_PROCESSING: windows.DWORD = 0x0004;
pub const ENABLE_WINDOW_INPUT: windows.DWORD = 0x0008;
pub const ENABLE_MOUSE_INPUT: windows.DWORD = 0x0010;
pub const ENABLE_VIRTUAL_TERMINAL_INPUT: windows.DWORD = 0x0200;

pub const DISABLE_NEWLINE_AUTO_RETURN: windows.DWORD = 0x0008;

pub fn enableRawModeWindows(handle: windows.HANDLE) !RawTerm {
    const old_mode = try getConsoleMode(handle);

    const mode: windows.DWORD = ENABLE_MOUSE_INPUT | ENABLE_WINDOW_INPUT | ENABLE_PROCESSED_OUTPUT | ENABLE_PROCESSED_INPUT;
    try setConsoleMode(handle, mode);

    return .{
        .context = old_mode,
        .handle = handle,
    };
}

// https://learn.microsoft.com/en-us/windows/console/getconsolemode
fn getConsoleMode(handle: windows.HANDLE) !windows.DWORD {
    var mode: windows.DWORD = 0;

    // nonzero value means success
    if (kernel32.GetConsoleMode(handle, &mode) == 0) {
        const err = kernel32.GetLastError();
        return windows.unexpectedError(err);
    }

    return mode;
}

fn setConsoleMode(handle: windows.HANDLE, mode: windows.DWORD) !void {
    // nonzero value means success
    if (kernel32.SetConsoleMode(handle, mode) == 0) {
        const err = kernel32.GetLastError();
        return windows.unexpectedError(err);
    }
}
