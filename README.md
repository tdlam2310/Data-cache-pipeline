# Tapeout_3
# Links
* Project/job tree (draw.io): [here](https://drive.google.com/file/d/1VgHh2zGTGUpXsvJK_pRbK1lyQa2hnCFQ/view?usp=sharing)
* Project assignments & progress (excel): [here](https://gtvault.sharepoint.com/:x:/s/SiliconJackets/ER9rUdvcgPFLnKWKsFkWZlMBQQ7IjQ-E5OFrvEP0PrjQ2g?e=12n3xU) 
* RISCV Architecture (draw.io): [here](https://drive.google.com/file/d/1VgHh2zGTGUpXsvJK_pRbK1lyQa2hnCFQ/view?usp=drive_link)
* Discord: [here](https://discord.gg/V34g4S4Dzx)
* Powerpoints: [here](https://gtvault.sharepoint.com/:f:/s/SiliconJackets/EmwGEznq0SVDvFG69MgEItQBh_McZCTRHkf6lnCOAY7RiA)
* Resources: [here](https://gtvault.sharepoint.com/:f:/s/SiliconJackets/EtAjUBo8IBJNjFa6UVnacHoBZXlPSJcx-Ai2KHaIHru66A?e=DSx60l)
* Helpful for learning HDL: [here](https://hdlbits.01xz.net/wiki/Main_Page)

# How to simulate your module (FOR DESIGNERS: SANITY/NON-UVM)
1. Put your testbench in `src/tb/verilog/sanity`
2. In `sim/behav/sanity/` directory, run the command `python3.12 setup_sim_dir.py "your-module-name"`.
3. In the generated subfolder, fill out the `tb_"your-module-name".include` file with the necessary files.
4. In the generated subfolder, run `make link` to create soft links to each file from "`my-test-name.include`".
5. In the generated subfolder, run `make xrun` to run the simulation and fix any errors it reports.
6. When your simulation is successful, run `make simvision` to view the waveforms.
7. In waveform debugging, use what you learned in the onboarding project to view the relevant signals. We recommend in your testbench using `$display()` or file I/O in systemverilog to print results so you don't need to always rely on viewing waveforms to check certain behavior.
8. `make clean` deletes files produced during simulation. Usually not necessary to use this.
9. Note: If you change your code while simvision is open, you DON'T need to close simvision! Just run `make xrun` to rerun the simulation, and in simvision click File -> Reload Databases to update your waveform.

# How to simulate your module (FOR VERIF: UVM)
1. In the `src/tb/verilog/uvm` directory, run the command `python3.12 setup_tb_dir.py "your-module-name"`, for a quick uvm directory setup. Template files are also provided in the `src/tb/verilog/uvm/uvm_template` directory.
2. In `sim/behav/uvm/` directory, run the command `python3.12 setup_sim_dir.py "your-module-name"`.
3. In the generated subfolder, fill out the `tb_"your-module-name".include` file with the necessary files.
4. In the generated subfolder, run `make link` to create soft links to each file from `tb_"your-module-name".include`.
5. In the generated subfolder, run `make xrun` to run the simulation and fix any errors it reports.
6. When your simulation is successful, run `make simvision` to view the waveforms.
7. In waveform debugging, use what you learned in the onboarding project to view the relevant signals. We recommend in your testbench using `$display()` or file I/O in systemverilog to print results so you don't need to always rely on viewing waveforms to check certain behavior.
8. `make clean` deletes files produced during simulation. Usually not necessary to use this.
9. Note: If you change your code while simvision is open, you DON'T need to close simvision! Just run `make xrun` to rerun the simulation, and in simvision click File -> Reload Databases to update your waveform.
