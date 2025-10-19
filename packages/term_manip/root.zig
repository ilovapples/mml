const std = @import("std");
const posix = std.posix;

// set/restore terminal for raw mode

var saved_termios: ?posix.termios = null;

pub fn saveSetTerminalRawMode(file: *const std.fs.File) !void {
    saved_termios = try posix.tcgetattr(file.handle);

    var new_termios = saved_termios.?;
    new_termios.lflag.ECHO = false;
    new_termios.lflag.ICANON = false;

    try posix.tcsetattr(file.handle, posix.TCSA.FLUSH, new_termios);
}
pub fn restoreTerminal(file: *const std.fs.File) bool {
    if (saved_termios == null) return false;

    posix.tcsetattr(file.handle, posix.TCSA.FLUSH, saved_termios.?) catch return false;

    saved_termios = null;

    return true;
}


