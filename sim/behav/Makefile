#--------------------------------------------------------------------
# Cadence Makefile (Xcelium / SimVision / IMC)
#--------------------------------------------------------------------

#--------------------------------------------------------------------
# Setup Steps:
# 1) Add the following to the testbench
#
# initial begin
#     $shm_open("waves.shm");
#     $shm_probe("AC");
# end
#
# 2) Remove FSDB stuff.
#
# 3) In the .include files, remove/comment any directories. Cadence tools only support interface (.svh) files. 
#--------------------------------------------------------------------

# ===== User‑configurable variables =================================
INCLUDE_FILE_NAME ?= sanity_rob.include
ASM_NAME          ?= 
NUM_ELEMS         ?= 
DATA_REP          ?= 
INIT_DATA         ?= 
TESTNAME          ?=

# ===== Paths =======================================================
CURRENT_DIR := $(shell pwd)
WORKSPACE   := $(CURRENT_DIR)/WORKSPACE
SCRIPT_DIR  := ../scripts
ASM_TEST_DIR := $(CURRENT_DIR)/Tests/asm

ASM_FILE     := $(ASM_NAME).asm
ASM_FILE_PATH := $(ASM_TEST_DIR)/$(ASM_FILE)
DATA_FILE    := ../Tests/mem_files/$(ASM_NAME).data
INST_FILE    := ../Tests/mem_files/$(ASM_NAME).mem

# ===== Dynamic macro definitions ===================================
VERILOG_DEFINES := SIM=1 INST_FILE=\"$(INST_FILE)\"
ifeq ($(INIT_DATA),1)
  VERILOG_DEFINES += INIT_DATA=1
  VERILOG_DEFINES += DATA_FILE=\"$(DATA_FILE)\"
endif
DEFINE_FLAGS := $(foreach def,$(VERILOG_DEFINES),+define+$(def))

# ===== Help Message ================================================
.PHONY: help
help:
	@echo "----------------------------------------------------------------"
	@echo "Administrative targets:"
	@echo "  help               - this message"
	@echo "  clean              - remove WORKSPACE directory"
	@echo
	@echo "Compilation targets:"
	@echo "  link               - generate WORKSPACE/sym_links/"
	@echo "  xrun               - compile & simulate using Cadence Xcelium"
	@echo "  simvision          - view waveform database"
	@echo "  run_and_view       - xrun + simvision"
	@echo "  coverage           - open coverage in IMC"
	@echo
	@echo "ASM testing tools:"
	@echo "  fix_qs_asm         - rewrite .asm file with new NUM_ELEMS"
	@echo "  asm2memb           - convert .asm to .mem/.data"
	@echo "  gen_rand_qs_data   - generate random test vectors"
	@echo "  check_qs_results   - verify result correctness"
	@echo "----------------------------------------------------------------"

# ===== Administrative Targets ======================================
.PHONY: clean link
clean:
	@rm -rf $(WORKSPACE)

link:
	@mkdir -p $(WORKSPACE)/sym_links
	@rm -rf $(WORKSPACE)/sym_links/*
	@python3.12 link_files.py $(INCLUDE_FILE_NAME)

# ===== Simulation Targets ==========================================
.PHONY: xrun simvision run_and_view coverage
XRUN_FLAGS = -64bit -sv -linedebug -access +rwc \
             -timescale 1ns/10ps \
             $(DEFINE_FLAGS) \
             +testname=$(TESTNAME) \
             +incdir+sym_links \
             -coverage all \
             -licqueue \
             -covoverwrite

xrun: link
	cd $(WORKSPACE) && \
	xrun $(XRUN_FLAGS) -f sym_links/sim_no_path.include \
	     -logfile simulation.log

simvision:
	cd $(WORKSPACE) && simvision waves.shm &

run_and_view: xrun simvision

# Need to change IMC path...
coverage:
	cd $(WORKSPACE) && /tools/software/cadence/vmanager/latest/tools.lnx86/vmgr/bin/imc -load cov_work/scope/test &

# ===== ASM Pre/Post Processing =====================================
.PHONY: fix_qs_asm asm2memb gen_rand_qs_data check_qs_results
fix_qs_asm:
	cd $(SCRIPT_DIR) && \
	python3.12 fix_qs_asm.py $(ASM_FILE_PATH) $(NUM_ELEMS)
	make asm2memb

asm2memb:
	cd $(SCRIPT_DIR) && \
	./asm2mem.sh $(ASM_FILE_PATH)

gen_rand_qs_data:
	cd $(SCRIPT_DIR) && \
	python3.12 gendata.py $(ASM_NAME) $(NUM_ELEMS) $(DATA_REP)

check_qs_results:
	cd $(SCRIPT_DIR) && \
	python3.12 check_qs_results.py $(ASM_NAME) $(NUM_ELEMS) $(DATA_REP)

# ===== Default Target ==============================================
.DEFAULT_GOAL := run_and_view