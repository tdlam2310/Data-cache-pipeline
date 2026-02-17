# Tapeout_3
# Links
* Project/job tree (draw.io): [here](https://drive.google.com/file/d/1VgHh2zGTGUpXsvJK_pRbK1lyQa2hnCFQ/view?usp=sharing)
* Project assignments & progress (excel): [here](https://gtvault.sharepoint.com/:x:/s/SiliconJackets/ER9rUdvcgPFLnKWKsFkWZlMBQQ7IjQ-E5OFrvEP0PrjQ2g?e=12n3xU) 
* RISCV Architecture (draw.io): [here](https://drive.google.com/file/d/1VgHh2zGTGUpXsvJK_pRbK1lyQa2hnCFQ/view?usp=drive_link)
* Discord: [here](https://discord.gg/V34g4S4Dzx)
* Powerpoints: [here](https://gtvault.sharepoint.com/:f:/s/SiliconJackets/EmwGEznq0SVDvFG69MgEItQBh_McZCTRHkf6lnCOAY7RiA)
* Resources: [here](https://gtvault.sharepoint.com/:f:/s/SiliconJackets/EtAjUBo8IBJNjFa6UVnacHoBZXlPSJcx-Ai2KHaIHru66A?e=DSx60l)
* Helpful for learning HDL: [here](https://hdlbits.01xz.net/wiki/Main_Page)

# How to simulate your module (SANITY/NON-UVM)
1. Put your testbench in `sim/behav/Tests/sanity`
2. In `sim/behav/Include/` directory, create a `my-test-name.include` file.
3. `my-test-name.include`, on each line put a relative path from `sim/behav` to each file you need for your simulation.
    (i.e. interfaces, packages, source files, and a testbench). Note: put packages first, then interfaces, then source files.
4. `cd` into `sim/behav`.
5. In `sim/behav/Makefile`, set `INCLUDE_FILE_NAME` equal to your include file name `my-test-name.include`
6. Run `make link` to create soft links in `sim/behav` to each file from "`my-test-name.include`".
7. Run `make xrun` to run the simulation and fix any errors it reports.
8. When your simulation is successful, run `make simvision` to view the waveforms.
9. In waveform debugging, use what you learned in the onboarding project to view the relevant signals. We recommend in your testbench using `$display()` or file I/O in systemverilog to print results so you don't need to always rely on viewing waveforms to check certain behavior.
10. `make clean` deletes files produced during simulation. Usually not necessary to use this.
11. Note: If you change your code while simvision is open, you DON'T need to close simvision! Just run `make xrun` to rerun the simulation, and in simvision click File -> Reload Databases to update your waveform.
