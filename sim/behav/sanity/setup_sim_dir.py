import sys
import argparse
from pathlib import Path

MAKEFILE_DIR = Path("../../../src/Makefiles")
SCRIPTS_DIR = Path("../../../scripts")
# ---------------------
def setup_simulation(module_name: str, template_name: str):
    """
    Creates a simulation directory structure and sets up a custom Makefile.
    """
    # Define paths
    cwd = Path.cwd()
    module_dir = cwd / module_name
    
    # Locate the template using the statically defined MAKEFILE_DIR
    makefile_dir_path = Path(MAKEFILE_DIR).resolve()
    makefile_path = makefile_dir_path / template_name
    include_path = makefile_dir_path / "tb_template_sanity.include"
    target_makefile = module_dir / "Makefile"
    target_include = module_dir / f"tb_{module_name}.include"

    # Link script path
    link_script_src = (cwd / SCRIPTS_DIR / "link_files.py").resolve()
    link_script_dest = module_dir / "link_files.py"

    # gitignore path
    gitignore_path = module_dir / ".gitignore"

    # --- THE FIX: Create the module directory first ---
    try:
        # Create the module directory (and any necessary parent directories)
        module_dir.mkdir(parents=True, exist_ok=True)
        # If you still need the 'results' folder from the earlier version, uncomment the line below:
        # (module_dir / "results").mkdir(parents=True, exist_ok=True)
        print(f"Created directory structure for '{module_name}'.")
    except Exception as e:
        print(f"Error creating directories: {e}")
        sys.exit(1)
    # --------------------------------------------------

    # 1. Verify the template Makefile exists
    if not makefile_path.exists():
        print(f"Error: Could not find template Makefile at '{makefile_path}'.")
        print(f"Please ensure '{template_name}' exists in '{MAKEFILE_DIR}'.")
        sys.exit(1)

    # 2. Read, modify, and write the Makefile and the include file
    try:
        # Read the contents of the base Makefile
        with open(makefile_path, 'r') as file:
            makefile_content = file.read()

        # Replace the placeholder with the actual module name
        updated_content = makefile_content.replace('MODULE_NAME_PLACEHOLDER', module_name)

        # Write the modified content to the new Makefile in the module directory
        with open(target_makefile, 'w') as file:
            file.write(updated_content)
            
        print(f"Copied and updated Makefile for module '{module_name}'.")
        
    except Exception as e:
        print(f"Error processing the Makefile: {e}")
        sys.exit(1)

    if include_path.exists():
        try:
            with open(include_path, 'r') as file:
                tb_content = file.read()

            updated_tb_content = tb_content.replace('MODULE_NAME_PLACEHOLDER', module_name)

            with open(target_include, 'w') as file:
                file.write(updated_tb_content)
                
            print(f"Copied and updated {target_include.name} for module '{module_name}'.")
            
        except Exception as e:
            print(f"Error processing tb_template.include: {e}")
            sys.exit(1)
    else:
        print(f"Warning: Could not find '{include_path}'. Skipping this file.")

    # 3. Create a symbolic link for the link_files_uvm.py script
    if link_script_src.exists():
        try:
            if not link_script_dest.exists():
                link_script_dest.symlink_to(link_script_src)
                print(f"Created symbolic link for link_files.py -> {link_script_src}")
            else:
                print("link_files_uvm.py already exists in target directory. Skipping symlink.")
        except Exception as e:
            print(f"Error creating symlink for link_files.py: {e}")
            sys.exit(1)
    else:
        print(f"Warning: Could not find '{link_script_src}'. Skipping this file.")

    # 4. Create a .gitignore file with WORKSPACE entry
    try:
        with open(gitignore_path, 'w') as f:
            f.write("./WORKSPACE\n")
        print(f"Created .gitignore file with WORKSPACE entry.")
    except Exception as e:
        print(f"Error creating .gitignore: {e}")
        sys.exit(1)

if __name__ == "__main__":
    # Set up command-line arguments
    parser = argparse.ArgumentParser(description="Set up a simulation directory for a specific module.")
    parser.add_argument("module_name", help="The name of the simulation module.")
    parser.add_argument("-t", "--template", default="Makefile.sim_presyn", 
                        help="The filename of the template Makefile (defaults to 'Makefile.sim_presyn').")
    
    args = parser.parse_args()
    
    setup_simulation(args.module_name, args.template)