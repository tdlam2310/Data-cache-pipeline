import os
import re
import sys

if len(sys.argv) != 2:
    print("Usage: python3 link_files_uvm.py <include_file_location>")
    sys.exit(1)

input_file = os.path.join("./", sys.argv[1])

workspace_dir = "./WORKSPACE"
sym_links_dir = os.path.join(workspace_dir, "sym_links")
os.makedirs(sym_links_dir, exist_ok=True)

output_include = os.path.join(sym_links_dir, "sim_no_path.include")
filelist_path = os.path.join(workspace_dir, "compile.f")

# Track files by section
interface_files = []
source_files = []
package_files = []
tb_top_files = []

current_section = None

# All symlink basenames created
all_symlinks = []

def make_symlink(src_path, dst_dir):
    basename = os.path.basename(src_path)
    dst_path = os.path.join(dst_dir, basename)
    try:
        if os.path.islink(dst_path) or os.path.exists(dst_path):
            if os.path.islink(dst_path) and os.path.abspath(os.readlink(dst_path)) == os.path.abspath(src_path):
                return basename
            try:
                os.remove(dst_path)
            except Exception:
                pass
        os.symlink(os.path.abspath(src_path), dst_path)
    except Exception as e:
        print(f"Warning: could not create symlink {dst_path} -> {src_path}: {e}")
    return basename

# Read include file, create symlinks, categorize files
with open(input_file, 'r') as fp, open(output_include, 'w') as out_fp:
    for line in fp:
        line_stripped = line.strip()
        
        # Write comment lines as-is
        if not line_stripped or line_stripped.startswith('//'):
            out_fp.write(line_stripped + '\n')
            
            # Detect section headers
            if "INTERFACES" in line_stripped:
                current_section = "INTERFACES"
            elif "SOURCE FILES" in line_stripped:
                current_section = "SOURCE"
            elif "UVM PACKAGE FILES" in line_stripped:
                current_section = "PACKAGES"
            elif "UVM TB COMPONENTS" in line_stripped:
                current_section = "SKIP"
            elif "TB TOP" in line_stripped:
                current_section = "TB_TOP"
            continue

        # Parse file path
        match = re.match(r'^\s*(\S+)\s*$', line_stripped)
        if not match:
            print(f"Error: Invalid line in include file: '{line_stripped}'")
            sys.exit(1)

        file_path = match.group(1)
        if not os.path.exists(file_path):
            print(f"Error: File '{file_path}' does not exist.")
            sys.exit(1)

        basename = make_symlink(file_path, sym_links_dir)
        out_fp.write(f"sym_links/{basename}\n")
        all_symlinks.append(basename)

        # Categorize file based on current section
        if current_section == "INTERFACES":
            interface_files.append(basename)
        elif current_section == "SOURCE":
            source_files.append(basename)
        elif current_section == "PACKAGES":
            package_files.append(basename)
        elif current_section == "TB_TOP":
            tb_top_files.append(basename)
        # SKIP section files are not added to compilation list

ordered_files = interface_files + source_files + package_files + tb_top_files

# Write compile.f
with open(filelist_path, 'w') as ff:
    
    if interface_files:
        ff.write("// INTERFACES\n")
        for name in interface_files:
            ff.write(f"sym_links/{name}\n")
        ff.write("\n")
    
    if source_files:
        ff.write("// SOURCE FILES\n")
        for name in source_files:
            ff.write(f"sym_links/{name}\n")
        ff.write("\n")
    
    if package_files:
        ff.write("// UVM PACKAGES\n")
        for name in package_files:
            ff.write(f"sym_links/{name}\n")
        ff.write("\n")
    
    if tb_top_files:
        ff.write("// TB TOP\n")
        for name in tb_top_files:
            ff.write(f"sym_links/{name}\n")