import sys
import argparse
from pathlib import Path

def setup_tb_dir(module_name: str):
    """
    Creates a UVM source directory structure and empty starter files.
    """
    # Base directory is the current working directory / module_name
    base_dir = Path.cwd() / module_name

    # List of UVM files to create, relative to the base directory
    uvm_files = [
        # ========= Packages =========
        "sequences/MODULE_NAME_PLACEHOLDER_seq_pkg.sv",
        "agent/MODULE_NAME_PLACEHOLDER_agent_pkg.sv",
        "env/MODULE_NAME_PLACEHOLDER_env_pkg.sv",
        "tests/MODULE_NAME_PLACEHOLDER_test_pkg.sv",

        # ========= Components =========
        "sequences/MODULE_NAME_PLACEHOLDER_seq_item.sv",
        "sequences/MODULE_NAME_PLACEHOLDER_sequence.svh",
        "sequences/MODULE_NAME_PLACEHOLDER_seq_lib.sv",
        "agent/MODULE_NAME_PLACEHOLDER_sequencer.sv",
        "agent/MODULE_NAME_PLACEHOLDER_driver.sv",
        "agent/MODULE_NAME_PLACEHOLDER_monitor.sv",
        "agent/MODULE_NAME_PLACEHOLDER_agent.sv",
        "env/MODULE_NAME_PLACEHOLDER_sb.sv",
        "env/MODULE_NAME_PLACEHOLDER_env.sv",
        "tests/MODULE_NAME_PLACEHOLDER_base_test.svh",
        "tests/MODULE_NAME_PLACEHOLDER_test_lib.sv",

        # ========= TB Top =========
        "tb/MODULE_NAME_PLACEHOLDER_tb_top.sv"
    ]

    try:
        # 1. Create the base module directory
        base_dir.mkdir(parents=True, exist_ok=True)
        print(f"Created base UVM directory: {base_dir}")
        
        # 2. Iterate through the list, create folders, and touch files
        for file_template in uvm_files:
            # Replace the placeholder with the actual module name
            rel_path = file_template.replace("MODULE_NAME_PLACEHOLDER", module_name)
            
            # Construct the full absolute path
            full_path = base_dir / rel_path
            
            # Create the parent directories (e.g., 'sequences', 'agent')
            full_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Create the empty file (touch)
            full_path.touch(exist_ok=True)
            print(f"  -> Created: {rel_path}")
            
        print(f"\nSuccessfully set up UVM src directory for '{module_name}'.")
        
    except Exception as e:
        print(f"Error setting up UVM structure: {e}")
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Set up UVM src directory structure for a specific module.")
    parser.add_argument("module_name", help="The name of the UVM module.")
    
    args = parser.parse_args()
    
    setup_tb_dir(args.module_name)