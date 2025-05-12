# load_edk2_symbols.py
#
# GDB Python script to parse EDK2 image load information from a log file
# and automatically load corresponding .debug symbols.
# - Dynamically scans specified EDK2 package directories for .inf files.
# - Dynamically searches for .debug files within the specified build output.
#
# To use:
# 1. Save this script (e.g., as load_edk2_symbols.py).
# 2. Set environment variables:
#    export EDK2_SOURCE_ROOT_ENV="/path/to/your/edk2"
#    export EDK2_PLATFORM_PACKAGE_NAME_ENV="YourPlatformPkgNameInBuildOutput"
#    export EDK2_BUILD_TARGET_DIR_NAME_ENV="DEBUG_YOURTARGET"
# 3. Configure EDK2_TARGET_ARCH and EDK2_PACKAGE_NAMES_TO_SCAN_DEFAULTS in the "User Configuration" section.
# 4. In GDB: source /path/to/load_edk2_symbols.py
# 5. To load symbols from a log: load-edk2-symbols <path_to_your_tty_log_file>
# 6. To rebuild map and then load symbols from log: rebuild-edk2-guidmap <path_to_your_tty_log_file>
#
#
import gdb
import re
import os
import json
import subprocess # For calling objdump

##### User Configuration
EDK2_SOURCE_ROOT_ENV_VAR = "EDK2_SOURCE_ROOT_ENV"
EDK2_PLATFORM_PACKAGE_NAME_ENV_VAR = "EDK2_PLATFORM_PACKAGE_NAME_ENV"
EDK2_BUILD_TARGET_DIR_NAME_ENV_VAR = "EDK2_BUILD_TARGET_DIR_NAME_ENV"

EDK2_SOURCE_ROOT = None
EDK2_PLATFORM_PACKAGE_NAME = None
EDK2_BUILD_TARGET_DIR_NAME = None

# Target architecture (e.g., X64, IA32, AARCH64) - Hardcoded for now, can be made ENV VAR if needed.
EDK2_TARGET_ARCH = "X64"

# List of EDK2 package names (relative to EDK2_SOURCE_ROOT) to scan for .inf files.
EDK2_PACKAGE_NAMES_TO_SCAN_DEFAULTS = [
    "MdeModulePkg",
    "MdePkg",
    # EDK2_PLATFORM_PACKAGE_NAME will be added dynamically
    "ShellPkg", # If you use the shell
]

# Cache file for the GUID map to speed up subsequent loads
GUID_MAP_CACHE_FILE = os.path.expanduser("~/.cache/gdb_edk2_guid_map_v2.json")
######

EDK2_DEBUG_FILES_SEARCH_BASE = None
EDK2_PACKAGE_SOURCE_DIRS_TO_SCAN = []


# Ensure cache directory exists
if GUID_MAP_CACHE_FILE and not os.path.exists(os.path.dirname(GUID_MAP_CACHE_FILE)):
    try:
        os.makedirs(os.path.dirname(GUID_MAP_CACHE_FILE))
        print(f"Created cache directory: {os.path.dirname(GUID_MAP_CACHE_FILE)}")
    except OSError as e:
        print(f"Warning: Could not create cache directory {os.path.dirname(GUID_MAP_CACHE_FILE)}: {e}")
        GUID_MAP_CACHE_FILE = None # Disable caching if dir creation fails

# Shared instance for map generation and symbol loading logic
class Edk2SymbolHelper:
    def __init__(self):
        self.guid_to_module_details = {} # Stores {"guid": {"base_name": "...", "full_debug_path": "..."}}
        self.debug_file_cache = {}       # Cache for found .debug file paths: {base_name: full_path}
        self.loaded_modules_info = {}    # Key: ImageBase, Value: base_name (to track loaded symbols per invocation)

    def check_env_vars_and_paths(self):
        """
        Checks if required environment variables are set, constructs global paths,
        and verifies the existence of EDK2_DEBUG_FILES_SEARCH_BASE.
        Returns True if all essential paths are valid, False otherwise.
        Updates global path variables.
        """
        global EDK2_SOURCE_ROOT, EDK2_PLATFORM_PACKAGE_NAME, EDK2_BUILD_TARGET_DIR_NAME
        global EDK2_DEBUG_FILES_SEARCH_BASE, EDK2_PACKAGE_SOURCE_DIRS_TO_SCAN

        EDK2_SOURCE_ROOT = os.getenv(EDK2_SOURCE_ROOT_ENV_VAR)
        EDK2_PLATFORM_PACKAGE_NAME = os.getenv(EDK2_PLATFORM_PACKAGE_NAME_ENV_VAR)
        EDK2_BUILD_TARGET_DIR_NAME = os.getenv(EDK2_BUILD_TARGET_DIR_NAME_ENV_VAR)

        missing_vars = []
        if not EDK2_SOURCE_ROOT: missing_vars.append(EDK2_SOURCE_ROOT_ENV_VAR)
        if not EDK2_PLATFORM_PACKAGE_NAME: missing_vars.append(EDK2_PLATFORM_PACKAGE_NAME_ENV_VAR)
        if not EDK2_BUILD_TARGET_DIR_NAME: missing_vars.append(EDK2_BUILD_TARGET_DIR_NAME_ENV_VAR)

        if missing_vars:
            print("Error: The following environment variable(s) are not set:")
            for var in missing_vars:
                print(f"  - {var}")
            print("Please set them before running the script.")
            return False
        
        EDK2_SOURCE_ROOT = os.path.abspath(os.path.expanduser(EDK2_SOURCE_ROOT))
        
        EDK2_DEBUG_FILES_SEARCH_BASE = os.path.join(
            EDK2_SOURCE_ROOT, "Build", EDK2_PLATFORM_PACKAGE_NAME,
            EDK2_BUILD_TARGET_DIR_NAME, EDK2_TARGET_ARCH
        )

        current_package_names = list(EDK2_PACKAGE_NAMES_TO_SCAN_DEFAULTS) 
        if EDK2_PLATFORM_PACKAGE_NAME not in current_package_names:
            current_package_names.append(EDK2_PLATFORM_PACKAGE_NAME)
        
        EDK2_PACKAGE_SOURCE_DIRS_TO_SCAN = sorted(list(set(
            [os.path.join(EDK2_SOURCE_ROOT, name) for name in current_package_names if name] 
        )))
        
        print(f"Using EDK2 Source Root: {EDK2_SOURCE_ROOT}")
        print(f"Using EDK2 Platform Package (from ENV): {EDK2_PLATFORM_PACKAGE_NAME}")
        print(f"Using EDK2 Build Target Dir (from ENV): {EDK2_BUILD_TARGET_DIR_NAME}")
        print(f"Constructed EDK2 Build Output Base for .debug files: {EDK2_DEBUG_FILES_SEARCH_BASE}")

        if not os.path.isdir(EDK2_DEBUG_FILES_SEARCH_BASE):
            print(f"Error: EDK2_DEBUG_FILES_SEARCH_BASE directory not found: {EDK2_DEBUG_FILES_SEARCH_BASE}")
            print("Please ensure environment variables are set correctly and accurately reflect your build output path structure.")
            return False
        
        return True

    def find_debug_file_recursive(self, base_name):
        if base_name in self.debug_file_cache:
            return self.debug_file_cache[base_name]

        target_filename = f"{base_name}.debug"
        search_base_abs = os.path.abspath(EDK2_DEBUG_FILES_SEARCH_BASE) 
        if not os.path.isdir(search_base_abs):
            return None

        for root, _, files in os.walk(search_base_abs):
            if target_filename in files:
                found_path = os.path.join(root, target_filename)
                self.debug_file_cache[base_name] = found_path
                return found_path
        self.debug_file_cache[base_name] = None
        return None

    def generate_guid_map(self, force_rebuild=False):
        if not self.check_env_vars_and_paths():
             self.guid_to_module_details = {}
             return False 

        if not force_rebuild and GUID_MAP_CACHE_FILE and os.path.exists(GUID_MAP_CACHE_FILE):
            try:
                with open(GUID_MAP_CACHE_FILE, 'r') as f:
                    cached_data = json.load(f)
                    if cached_data.get("_source_root") == EDK2_SOURCE_ROOT and \
                       cached_data.get("_platform_package") == EDK2_PLATFORM_PACKAGE_NAME and \
                       cached_data.get("_build_target") == EDK2_BUILD_TARGET_DIR_NAME and \
                       cached_data.get("_target_arch") == EDK2_TARGET_ARCH:
                        self.guid_to_module_details = cached_data.get("map", {})
                        self.debug_file_cache = cached_data.get("debug_file_cache", {})
                        print(f"Loaded GUID map and debug file cache from: {GUID_MAP_CACHE_FILE}")
                        if self.guid_to_module_details:
                            return True
                        else:
                            print("Cache was empty or invalid, rebuilding map.")
                    else:
                        print("Configuration changed, rebuilding map.")
            except Exception as e:
                print(f"Error loading GUID map from cache ({e}), rebuilding.")

        print(f"Generating EDK2 GUID to debug file map (searching for .debug files in {EDK2_DEBUG_FILES_SEARCH_BASE})...")
        self.guid_to_module_details = {}
        self.debug_file_cache = {}
        guid_pattern = re.compile(r"FILE_GUID\s*=\s*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})", re.IGNORECASE)
        base_name_pattern = re.compile(r"BASE_NAME\s*=\s*(\w+)", re.IGNORECASE)
        module_type_pattern = re.compile(r"MODULE_TYPE\s*=\s*(\w+)", re.IGNORECASE)

        scanned_inf_count = 0
        relevant_module_count = 0
        
        for package_root_abs in EDK2_PACKAGE_SOURCE_DIRS_TO_SCAN: 
            if not os.path.isdir(package_root_abs):
                # print(f"Warning: EDK2 package source directory not found during scan: {package_root_abs}") # Removed warning
                continue
            
            for root, dirs, files in os.walk(package_root_abs):
                dirs[:] = [d for d in dirs if d.lower() not in ["build", ".git", "bin", "obj", "output", "tools", "scripts"]]
                
                for file_name in files:
                    if file_name.lower().endswith(".inf"):
                        scanned_inf_count += 1
                        inf_path_abs = os.path.join(root, file_name)
                        file_guid = None
                        base_name = None
                        module_type = None
                        try:
                            with open(inf_path_abs, "r", encoding="utf-8", errors="ignore") as f_inf:
                                for line in f_inf:
                                    line = line.strip()
                                    if not file_guid:
                                        match_guid = guid_pattern.search(line)
                                        if match_guid: file_guid = match_guid.group(1).upper()
                                    if not base_name:
                                        match_base = base_name_pattern.search(line)
                                        if match_base: base_name = match_base.group(1)
                                    if not module_type:
                                        mt_match = module_type_pattern.search(line)
                                        if mt_match: module_type = mt_match.group(1)
                                    if file_guid and base_name and module_type: break
                            
                            if file_guid and base_name and module_type and \
                               module_type.upper() in ["DXE_DRIVER", "DXE_RUNTIME_DRIVER", 
                                                        "DXE_SAL_DRIVER", "DXE_SMM_DRIVER", 
                                                        "UEFI_DRIVER", "UEFI_APPLICATION", "DXE_CORE"]:
                                relevant_module_count +=1
                                full_debug_path = self.find_debug_file_recursive(base_name)
                                if full_debug_path:
                                    self.guid_to_module_details[file_guid] = {
                                        "base_name": base_name,
                                        "full_debug_path": full_debug_path
                                    }
                                # else: # Silenced warning for not finding debug file during map generation
                                #     print(f"  - Could not find .debug file for {base_name} (GUID: {file_guid}) during map generation.")
                        except Exception as e:
                            print(f"Error processing {inf_path_abs}: {e}")
        
        print(f"Finished scanning {scanned_inf_count} .inf files. Found {relevant_module_count} relevant DXE modules, mapped {len(self.guid_to_module_details)} to .debug files.")
        if GUID_MAP_CACHE_FILE and self.guid_to_module_details:
            try:
                data_to_cache = {
                    "_source_root": EDK2_SOURCE_ROOT,
                    "_platform_package": EDK2_PLATFORM_PACKAGE_NAME,
                    "_build_target": EDK2_BUILD_TARGET_DIR_NAME,
                    "_target_arch": EDK2_TARGET_ARCH,
                    "map": self.guid_to_module_details,
                    "debug_file_cache": self.debug_file_cache
                }
                with open(GUID_MAP_CACHE_FILE, 'w') as f_cache:
                    json.dump(data_to_cache, f_cache, indent=4)
                print(f"Saved GUID map to cache: {GUID_MAP_CACHE_FILE}")
            except Exception as e:
                print(f"Error saving GUID map to cache: {e}")
        return True

    def find_text_offset(self, full_debug_path_to_check):
        """Uses objdump to find the VMA of the .text section."""
        try:
            if not os.path.exists(full_debug_path_to_check): return 0
            abs_search_base = os.path.abspath(EDK2_DEBUG_FILES_SEARCH_BASE) 
            if ".." in full_debug_path_to_check or not os.path.abspath(full_debug_path_to_check).startswith(abs_search_base):
                # print(f"Warning: Potentially unsafe or unexpected debug file path for objdump skipped: {full_debug_path_to_check}") # Silenced
                return 0

            objdump_cmd = ["objdump", "-h", full_debug_path_to_check]
            process = subprocess.Popen(objdump_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            objdump_output, objdump_err = process.communicate()

            if process.returncode != 0:
                print(f"Error running objdump for {full_debug_path_to_check}:\n{objdump_err}") # Kept error for objdump failure
                return 0
            
            text_section_match = re.search(r"^\s*\d+\s+\.text\s+[0-9a-fA-F]+\s+([0-9a-fA-F]+)", objdump_output, re.MULTILINE)
            if text_section_match:
                return int(text_section_match.group(1), 16)
        except Exception as e:
            print(f"Could not get .text offset for {full_debug_path_to_check}: {e}") # Kept error for unexpected issues
        return 0

    def load_symbols_from_log_file(self, log_file_path):
        """Parses the log file and loads symbols for found modules."""
        if not self.guid_to_module_details:
            print("GUID map is empty. Cannot load symbols. Generate map first (e.g., with rebuild-edk2-guidmap or load-edk2-symbols --rebuild-map).")
            return

        self.loaded_modules_info = {} # Reset for this specific load operation

        log_pattern = re.compile(
            r"EDK2_IMAGE_INFO: FileGuid=(?P<file_guid>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}), "
            r"ImageBase=0x(?P<image_base>[0-9a-fA-F]+), "
            r"ImageSize=0x(?P<image_size>[0-9a-fA-F]+)"
        )
        
        # processed_guids_for_warning = set() # No longer needed for this specific warning
        try:
            with open(log_file_path, "r", encoding="utf-8", errors="ignore") as f_log:
                for line_num, line in enumerate(f_log, 1):
                    match = log_pattern.search(line)
                    if match:
                        file_guid_str = match.group("file_guid").upper()
                        image_base_addr = int(match.group("image_base"), 16)

                        if image_base_addr == 0: continue
                        if image_base_addr in self.loaded_modules_info: continue 
                        
                        module_details = self.guid_to_module_details.get(file_guid_str)

                        if module_details:
                            base_name = module_details["base_name"]
                            full_debug_path = module_details["full_debug_path"] 

                            if not full_debug_path or not os.path.exists(full_debug_path):
                                # print(f"Warning: Pre-mapped debug file not found for GUID {file_guid_str} (Name: {base_name}) at path: {full_debug_path}") # Silenced
                                self.loaded_modules_info[image_base_addr] = f"{base_name} (debug file not found)"
                                continue
                            
                            text_offset = self.find_text_offset(full_debug_path)
                            load_addr = image_base_addr + text_offset
                            
                            print(f"Found: GUID={file_guid_str}, Name='{base_name}', ImageBase=0x{image_base_addr:X}, .text offset=0x{text_offset:X}, Load Addr=0x{load_addr:X}")
                            try:
                                gdb.execute(f"add-symbol-file \"{full_debug_path}\" 0x{load_addr:X}")
                                self.loaded_modules_info[image_base_addr] = base_name
                                print(f"  Symbols for '{base_name}' loaded.")
                            except gdb.error as e:
                                print(f"  Error loading symbols for '{base_name}': {e}") # Kept GDB load errors
                                self.loaded_modules_info[image_base_addr] = f"{base_name} (load error)"
                        else:
                            # if file_guid_str not in processed_guids_for_warning: # Silenced warning
                                # print(f"Warning: No GUID-to-module mapping found for GUID: {file_guid_str} (ImageBase: 0x{image_base_addr:X})")
                                # processed_guids_for_warning.add(file_guid_str)
                            self.loaded_modules_info[image_base_addr] = f"GUID {file_guid_str} (mapping not found)"
            
            if not self.loaded_modules_info: print("No EDK2_IMAGE_INFO lines found or processed from the log file.")
            else: print(f"Attempted to load symbols for {len(self.loaded_modules_info)} unique ImageBase instances.")

        except FileNotFoundError: print(f"Error: Log file '{log_file_path}' not found.") # Kept critical errors
        except Exception as e: print(f"An error occurred during symbol loading from log: {e}") # Kept critical errors
        print("Symbol loading process finished.")


# Create a single instance of the helper to share the map and caches
edk2_helper = Edk2SymbolHelper()

class LoadEdk2SymbolsCommand(gdb.Command):
    """Load EDK2 symbols based on image load info from a log file."""
    def __init__(self):
        super(LoadEdk2SymbolsCommand, self).__init__("load-edk2-symbols", gdb.COMMAND_USER)

    def invoke(self, argument, from_tty):
        global edk2_helper 

        if not edk2_helper.check_env_vars_and_paths():
            return

        args = gdb.string_to_argv(argument)
        force_rebuild_map = False
        log_file_path = None

        if not args:
            print("Usage: load-edk2-symbols [--rebuild-map] <log_file_path>")
            return

        if args[0] == "--rebuild-map":
            force_rebuild_map = True
            if len(args) > 1: log_file_path = os.path.expanduser(args[1])
            else:
                print("Usage: load-edk2-symbols --rebuild-map <log_file_path>"); return
        else:
            log_file_path = os.path.expanduser(args[0])
        
        if not log_file_path: print("Error: Log file path not provided."); return
        if not os.path.exists(log_file_path): print(f"Error: Log file '{log_file_path}' not found."); return
        
        if not edk2_helper.generate_guid_map(force_rebuild=force_rebuild_map):
            print("Failed to generate or load GUID map. Aborting symbol load.")
            return
        
        edk2_helper.load_symbols_from_log_file(log_file_path)


class RebuildEdk2GuidMapCommand(gdb.Command):
    """Rebuilds and caches the EDK2 GUID to .debug file mapping, then loads symbols from the provided log file.
    Usage: rebuild-edk2-guidmap <log_file_path>"""
    def __init__(self):
        super(RebuildEdk2GuidMapCommand, self).__init__("rebuild-edk2-guidmap", gdb.COMMAND_USER)

    def invoke(self, argument, from_tty):
        global edk2_helper 
        
        if not edk2_helper.check_env_vars_and_paths():
            return

        args = gdb.string_to_argv(argument)
        if not args:
            print("Usage: rebuild-edk2-guidmap <log_file_path>")
            return
        
        log_file_path = os.path.expanduser(args[0])
        if not os.path.exists(log_file_path):
            print(f"Error: Log file '{log_file_path}' not found.")
            return

        print("Forcing rebuild of EDK2 GUID map...")
        if edk2_helper.generate_guid_map(force_rebuild=True):
            print("GUID map rebuild complete and cached.")
            print(f"Now loading symbols from log: {log_file_path}")
            edk2_helper.load_symbols_from_log_file(log_file_path)
        else:
            print("GUID map rebuild failed. Check errors and environment variable settings.")

# Register the commands with GDB
if __name__ == "__main__":
    LoadEdk2SymbolsCommand()
    RebuildEdk2GuidMapCommand()

