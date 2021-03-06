##
## This file is part of the coreboot project.
##
## Copyright (C) 2008 Advanced Micro Devices, Inc.
## Copyright (C) 2008 Uwe Hermann <uwe@hermann-uwe.de>
## Copyright (C) 2009-2010 coresystems GmbH
## Copyright (C) 2011 secunet Security Networks AG
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions
## are met:
## 1. Redistributions of source code must retain the above copyright
##    notice, this list of conditions and the following disclaimer.
## 2. Redistributions in binary form must reproduce the above copyright
##    notice, this list of conditions and the following disclaimer in the
##    documentation and/or other materials provided with the distribution.
## 3. The name of the author may not be used to endorse or promote products
##    derived from this software without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
## ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
## IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
## ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
## FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
## DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
## OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
## HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
## LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
## OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
## SUCH DAMAGE.
##

# in addition to the dependency below, create the file if it doesn't exist
# to silence stupid warnings about a file that would be generated anyway.
$(if $(wildcard .xcompile),,$(eval $(shell util/xcompile/xcompile $(XGCCPATH) > .xcompile || rm -f .xcompile)))

.xcompile: util/xcompile/xcompile
	rm -f $@
	$< $(XGCCPATH) > $@.tmp
	\mv -f $@.tmp $@ 2> /dev/null
	rm -f $@.tmp

export top := $(CURDIR)
export src := src
export srck := $(top)/util/kconfig
obj ?= build
override obj := $(subst $(top)/,,$(abspath $(obj)))
export obj
export objutil ?= $(obj)/util
export objk := $(objutil)/kconfig
absobj := $(abspath $(obj))


export KCONFIG_AUTOHEADER := $(obj)/config.h
export KCONFIG_AUTOCONFIG := $(obj)/auto.conf
export KCONFIG_DEPENDENCIES := $(obj)/auto.conf.cmd
export KCONFIG_SPLITCONFIG := $(obj)/config
export KCONFIG_TRISTATE := $(obj)/tristate.conf
export KCONFIG_NEGATIVES := 1
export KCONFIG_STRICT := 1

# directory containing the toplevel Makefile.inc
TOPLEVEL := .

CONFIG_SHELL := sh
KBUILD_DEFCONFIG := configs/defconfig
UNAME_RELEASE := $(shell uname -r)
DOTCONFIG ?= .config
KCONFIG_CONFIG = $(DOTCONFIG)
export KCONFIG_CONFIG
HAVE_DOTCONFIG := $(wildcard $(DOTCONFIG))
MAKEFLAGS += -rR --no-print-directory

# Make is silent per default, but 'make V=1' will show all compiler calls.
Q:=@
ifneq ($(V),1)
ifneq ($(Q),)
.SILENT:
endif
endif

# Disable implicit/built-in rules to make Makefile errors fail fast.
.SUFFIXES:

HOSTCC := $(if $(shell type gcc 2>/dev/null),gcc,cc)
HOSTCXX = g++
HOSTCFLAGS := -g
HOSTCXXFLAGS := -g

PREPROCESS_ONLY := -E -P -x assembler-with-cpp -undef -I .

DOXYGEN := doxygen
DOXYGEN_OUTPUT_DIR := doxygen

all: real-all

help_coreboot help::
	@echo  '*** coreboot platform targets ***'
	@echo  '  Use "make [target] V=1" for extra build debug information'
	@echo  '  all                   - Build coreboot'
	@echo  '  clean                 - Remove coreboot build artifacts'
	@echo  '  distclean             - Remove build artifacts and config files'
	@echo  '  doxygen               - Build doxygen documentation for coreboot'
	@echo  '  what-jenkins-does     - Run platform build tests (Use CPUS=# for more cores)'
	@echo  '  printall              - print makefile info for debugging'
	@echo  '  lint / lint-stable    - run coreboot lint tools (all / minimal)'
	@echo  '  gitconfig             - set up git to submit patches to coreboot'
	@echo  '  ctags / ctags-project - make ctags file for all of coreboot or current board'
	@echo  '  cscope / cscope-project - make cscope.out file for coreboot or current board'
	@echo

# This include must come _before_ the pattern rules below!
# Order _does_ matter for pattern rules.
include $(srck)/Makefile

# Three cases where we don't need fully populated $(obj) lists:
# 1. when no .config exists
# 2. when make config (in any flavour) is run
# 3. when make distclean is run
# Don't waste time on reading all Makefile.incs in these cases
ifeq ($(strip $(HAVE_DOTCONFIG)),)
NOCOMPILE:=1
endif
ifneq ($(MAKECMDGOALS),)
ifneq ($(filter %config %clean cross% clang iasl lint% help% what-jenkins-does,$(MAKECMDGOALS)),)
NOCOMPILE:=1
endif
ifeq ($(MAKECMDGOALS), %clean)
NOMKDIR:=1
endif
endif

ifeq ($(NOCOMPILE),1)
include $(TOPLEVEL)/Makefile.inc
include $(TOPLEVEL)/payloads/Makefile.inc
real-all: config

else

include $(HAVE_DOTCONFIG)

-include .xcompile

ifneq ($(XCOMPILE_COMPLETE),1)
$(shell rm -f .xcompile)
$(error .xcompile deleted because it's invalid. \
	Restarting the build should fix that, or explain the problem)
endif

ifneq ($(CONFIG_MMX),y)
CFLAGS_x86_32 += -mno-mmx
endif

include toolchain.inc

strip_quotes = $(strip $(subst ",,$(subst \",,$(1))))
# fix makefile syntax highlighting after strip macro \" "))

# The primary target needs to be here before we include the
# other files

real-all: real-target

# must come rather early
.SECONDEXPANSION:

$(KCONFIG_AUTOHEADER): $(KCONFIG_CONFIG)
	$(MAKE) oldconfig

# Add a new class of source/object files to the build system
add-class= \
	$(eval $(1)-srcs:=) \
	$(eval $(1)-objs:=) \
	$(eval classes+=$(1))

# Special classes are managed types with special behaviour
# On parse time, for each entry in variable $(1)-y
# a handler $(1)-handler is executed with the arguments:
# * $(1): directory the parser is in
# * $(2): current entry
add-special-class= \
	$(eval $(1):=) \
	$(eval special-classes+=$(1))

# Converts one or more source file paths to their corresponding build/ paths.
# Only .c and .S get converted to .o, other files (like .ld) keep their name.
# $1 stage name
# $2 file path (list)
src-to-obj=\
	$(patsubst $(obj)/%,$(obj)/$(1)/%,\
	$(patsubst $(obj)/$(1)/%,$(obj)/%,\
	$(patsubst src/%,$(obj)/%,\
	$(patsubst %.c,%.o,\
	$(patsubst %.S,%.o,\
	$(subst .$(1),,$(2)))))))

# Clean -y variables, include Makefile.inc
# Add paths to files in X-y to X-srcs
# Add subdirs-y to subdirs
includemakefiles= \
	$(foreach class,classes subdirs $(classes) $(special-classes), $(eval $(class)-y:=)) \
	$(eval -include $(1)) \
	$(foreach class,$(classes-y), $(call add-class,$(class))) \
	$(foreach class,$(classes), \
		$(eval $(class)-srcs+= \
			$$(subst $(absobj)/,$(obj)/, \
			$$(subst $(top)/,, \
			$$(abspath $$(subst $(dir $(1))/,/,$$(addprefix $(dir $(1)),$$($(class)-y)))))))) \
	$(foreach special,$(special-classes), \
		$(foreach item,$($(special)-y), $(call $(special)-handler,$(dir $(1)),$(item)))) \
	$(eval subdirs+=$$(subst $(CURDIR)/,,$$(abspath $$(addprefix $(dir $(1)),$$(subdirs-y)))))

# For each path in $(subdirs) call includemakefiles
# Repeat until subdirs is empty
evaluate_subdirs= \
	$(eval cursubdirs:=$(subdirs)) \
	$(eval subdirs:=) \
	$(foreach dir,$(cursubdirs), \
		$(eval $(call includemakefiles,$(dir)/Makefile.inc))) \
	$(if $(subdirs),$(eval $(call evaluate_subdirs)))

# collect all object files eligible for building
subdirs:=$(TOPLEVEL)
$(eval $(call evaluate_subdirs))
ifeq ($(FAILBUILD),1)
$(error cannot continue build)
endif

# Eliminate duplicate mentions of source files in a class
$(foreach class,$(classes),$(eval $(class)-srcs:=$(sort $($(class)-srcs))))

$(foreach class,$(classes),$(eval $(class)-objs:=$(call src-to-obj,$(class),$($(class)-srcs))))

# Save all objs before processing them (for dependency inclusion)
originalobjs:=$(foreach var, $(addsuffix -objs,$(classes)), $($(var)))

# Call post-processors if they're defined
$(foreach class,$(classes),\
	$(if $(value $(class)-postprocess),$(eval $(call $(class)-postprocess,$($(class)-objs)))))

allsrcs:=$(foreach var, $(addsuffix -srcs,$(classes)), $($(var)))
allobjs:=$(foreach var, $(addsuffix -objs,$(classes)), $($(var)))
alldirs:=$(sort $(abspath $(dir $(allobjs))))

# macro to define template macros that are used by use_template macro
define create_cc_template
# $1 obj class
# $2 source suffix (c, S, ld, ...)
# $3 additional compiler flags
# $4 additional dependencies
ifn$(EMPTY)def $(1)-objs_$(2)_template
de$(EMPTY)fine $(1)-objs_$(2)_template
$$(call src-to-obj,$1,$$(1).$2): $$(1).$2 $(KCONFIG_AUTOHEADER) $(4)
	@printf "    CC         $$$$(subst $$$$(obj)/,,$$$$(@))\n"
	$(CC_$(1)) -MMD $$$$(CPPFLAGS_$(1)) $$$$(CFLAGS_$(1)) -MT $$$$(@) $(3) -c -o $$$$@ $$$$<
en$(EMPTY)def
end$(EMPTY)if
endef

filetypes-of-class=$(subst .,,$(sort $(suffix $($(1)-srcs))))
$(foreach class,$(classes), \
	$(foreach type,$(call filetypes-of-class,$(class)), \
		$(eval $(class)-$(type)-ccopts += $(generic-$(type)-ccopts) $($(class)-generic-ccopts)) \
		$(if $(generic-objs_$(type)_template_gen),$(eval $(call generic-objs_$(type)_template_gen,$(class))),\
		$(eval $(call create_cc_template,$(class),$(type),$($(class)-$(type)-ccopts),$($(class)-$(type)-deps))))))

foreach-src=$(foreach file,$($(1)-srcs),$(eval $(call $(1)-objs_$(subst .,,$(suffix $(file)))_template,$(basename $(file)))))
$(eval $(foreach class,$(classes),$(call foreach-src,$(class))))

DEPENDENCIES += $(addsuffix .d,$(basename $(allobjs)))
-include $(DEPENDENCIES)

printall:
	@$(foreach class,$(classes), echo $(class)-objs: $($(class)-objs) | tr ' ' '\n'; echo; )
	@echo alldirs: $(alldirs) | tr ' ' '\n'; echo
	@echo allsrcs: $(allsrcs) | tr ' ' '\n'; echo
	@echo DEPENDENCIES: $(DEPENDENCIES) | tr ' ' '\n'; echo
	@$(foreach class,$(special-classes),echo $(class):'$($(class))' | tr ' ' '\n'; echo; )
endif

ifndef NOMKDIR
$(shell mkdir -p $(KCONFIG_SPLITCONFIG) $(objk)/lxdialog $(additional-dirs) $(alldirs))
endif

$(obj)/project_filelist.txt: all
	find $(obj) -name "*.d" -exec cat {} \; | \
	  sed 's/[:\\]/ /g' | sed 's/ /\n/g' | sort | uniq | \
	  grep -v '\.o$$' > $(obj)/project_filelist.txt

#works with either exuberant ctags or ctags.emacs
ctags-project: clean-ctags $(obj)/project_filelist.txt
	cat $(obj)/project_filelist.txt | \
	  xargs ctags -o tags

cscope-project: clean-cscope $(obj)/project_filelist.txt
	cat $(obj)/project_filelist.txt | xargs cscope -b

cscope:
	cscope -bR

doxy: doxygen
doxygen:
	$(DOXYGEN) Documentation/Doxyfile.coreboot

doxygen_simple:
	$(DOXYGEN) Documentation/Doxyfile.coreboot_simple

doxyclean: doxygen-clean
doxygen-clean:
	rm -rf $(DOXYGEN_OUTPUT_DIR)

clean-for-update: doxygen-clean clean-for-update-target
	rm -rf $(obj) .xcompile

clean: clean-for-update clean-target
	rm -f .ccwrap

clean-cscope:
	rm -f cscope.out

clean-ctags:
	rm -f tags

distclean: clean clean-ctags clean-cscope distclean-payloads
	rm -f .config .config.old ..config.tmp .kconfig.d .tmpconfig* .ccwrap .xcompile

.PHONY: $(PHONY) clean clean-for-update clean-cscope cscope distclean doxygen doxy doxygen_simple
.PHONY: ctags-project cscope-project clean-ctags
