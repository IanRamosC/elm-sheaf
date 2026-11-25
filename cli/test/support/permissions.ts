/**
 * Whether taking away a file's read or write permission stops this process
 * from using it. Windows ignores those bits of `chmod`, and root ignores the
 * permissions altogether.
 */
export const permissionsApply =
  process.platform !== "win32" && process.getuid?.() !== 0;
