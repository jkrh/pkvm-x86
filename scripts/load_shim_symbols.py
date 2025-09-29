# GDB Python script to load shim symbols automatically.

import gdb
import re
import os

# The static offset of the .text section within the shim EFI debug file.
SHIM_TEXT_OFFSET = 0x25000

class LoadShimSymbols(gdb.Command):
    """
    Defines the 'load-shim-symbols' GDB command.

    This command parses a log file to find the dynamic base address
    where shim was loaded, then uses it to load the corresponding
    debug symbols at the correct memory location.
    """

    def __init__(self):
        super(LoadShimSymbols, self).__init__("load-shim-symbols",
                                              gdb.COMMAND_USER,
                                              gdb.COMPLETE_FILENAME)

    def invoke(self, arg, from_tty):
        self.dont_repeat()

        args = gdb.string_to_argv(arg)

        if len(args) != 2:
            print("Usage: load-shim-symbols <logfile> <debug_symbol_file>")
            return

        logfile_path = args[0]
        symbol_file_path = args[1]

        if not os.path.exists(logfile_path):
            print(f"Error: Log file not found at '{logfile_path}'")
            return
        if not os.path.exists(symbol_file_path):
            print(f"Error: Symbol file not found at '{symbol_file_path}'")
            return

        address_pattern = re.compile(r"Bootloader loaded at address: (0x[0-9a-fA-F]+)")

        base_address = None

        print(f"Searching for shim load address in '{logfile_path}'...")

        try:
            with open(logfile_path, 'r') as f:
                for line in f:
                    match = address_pattern.search(line)
                    if match:
                        base_address_str = match.group(1)
                        base_address = int(base_address_str, 16)
        except IOError as e:
            print(f"Error: Could not read log file: {e}")
            return

        if base_address is None:
            print("Error: Could not find the bootloader load address in the log file.")
            print("       (Looking for a line like '[Bds] Bootloader loaded at address: 0x...')")
            return

        print(f"✅ Found ImageBase address: {hex(base_address)}")

        symbol_load_address = base_address + SHIM_TEXT_OFFSET

        gdb_command = f"add-symbol-file {symbol_file_path} {hex(symbol_load_address)}"

        print(f"Executing: {gdb_command}")

        gdb.execute(gdb_command)

LoadShimSymbols()
