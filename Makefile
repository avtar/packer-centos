# if Makefile.local exists, include it
ifneq ("$(wildcard Makefile.local)", "")
	include Makefile.local
endif

PACKER := /opt/packer/packer

# Possible values for CM: (nocm | chef | chefdk | salt | puppet | ansible)
CM ?= ansible
# Possible values for CM_VERSION: (latest | x.y.z | x.y)
CM_VERSION ?= latest
ifndef CM_VERSION
	ifneq ($(CM),nocm)
		CM_VERSION = latest
	endif
endif
SSH_USERNAME ?= vagrant
SSH_PASSWORD ?= vagrant
INSTALL_VAGRANT_KEY ?= true
ISO_PATH ?= iso
BOX_VERSION ?= $(shell cat VERSION)
BOX_SUFFIX := -$(BOX_VERSION).box
# Packer does not allow empty variables, so only pass variables that are defined
PACKER_VARS_LIST = 'cm=$(CM)' 'headless=$(HEADLESS)' 'update=$(UPDATE)' 'version=$(BOX_VERSION)' 'ssh_username=$(SSH_USERNAME)' 'ssh_password=$(SSH_PASSWORD)' 'install_vagrant_key=$(INSTALL_VAGRANT_KEY)' 'iso_path=$(ISO_PATH)'
ifdef CM_VERSION
	PACKER_VARS_LIST += 'cm_version=$(CM_VERSION)'
endif
PACKER_VARS := $(addprefix -var , $(PACKER_VARS_LIST))
ifdef PACKER_DEBUG
	PACKER_CMD := PACKER_LOG=1 $(PACKER) --debug
else
	PACKER_CMD := $(PACKER)
endif
BUILDER_TYPES := vmware virtualbox
TEMPLATE_FILENAMES := $(wildcard *.json)
BOX_FILENAMES := idi-$(TEMPLATE_FILENAMES:.json=$(BOX_SUFFIX))
TEST_BOX_FILES := $(foreach builder, $(BUILDER_TYPES), $(foreach box_filename, $(BOX_FILENAMES), test-box/$(builder)/$(box_filename)))
VMWARE_BOX_DIR := box/vmware
VIRTUALBOX_BOX_DIR := box/virtualbox
VMWARE_BOX_FILES := $(foreach box_filename, $(BOX_FILENAMES), $(VMWARE_BOX_DIR)/$(box_filename))
VIRTUALBOX_BOX_FILES := $(foreach box_filename, $(BOX_FILENAMES), $(VIRTUALBOX_BOX_DIR)/$(box_filename))
BOX_FILES := $(VMWARE_BOX_FILES) $(VIRTUALBOX_BOX_FILES)
VMWARE_OUTPUT := output-vmware-iso
VIRTUALBOX_OUTPUT := output-virtualbox-iso
VMWARE_BUILDER := vmware-iso
VIRTUALBOX_BUILDER := virtualbox-iso
CURRENT_DIR = $(shell pwd)
SOURCES := $(wildcard script/*.sh)

.PHONY: list

all: $(BOX_FILES)

test: $(TEST_BOX_FILES)

###############################################################################
# Target shortcuts
define SHORTCUT

vmware/$(1): $(VMWARE_BOX_DIR)/$(1)$(BOX_SUFFIX)

test-vmware/$(1): test-$(VMWARE_BOX_DIR)/$(1)$(BOX_SUFFIX)

ssh-vmware/$(1): ssh-$(VMWARE_BOX_DIR)/$(1)$(BOX_SUFFIX)

virtualbox/$(1): $(VIRTUALBOX_BOX_DIR)/$(1)$(BOX_SUFFIX)

test-virtualbox/$(1): test-$(VIRTUALBOX_BOX_DIR)/$(1)$(BOX_SUFFIX)

ssh-virtualbox/$(1): ssh-$(VIRTUALBOX_BOX_DIR)/$(1)$(BOX_SUFFIX)

$(1): vmware/$(1) virtualbox/$(1)

test-$(1): test-vmware/$(1) test-virtualbox/$(1)

s3cp-$(1): s3cp-$(VMWARE_BOX_DIR)/$(1)$(BOX_SUFFIX) s3cp-$(VIRTUALBOX_BOX_DIR)/$(1)$(BOX_SUFFIX)

s3cp-vmware/$(1): s3cp-$(VMWARE_BOX_DIR)/$(1)$(BOX_SUFFIX)

s3cp-virtualbox/$(1): s3cp-$(VIRTUALBOX_BOX_DIR)/$(1)$(BOX_SUFFIX)

test-atlas-$(1): test-atlas-$(VMWARE_BOX_DIR)/$(1)$(BOX_SUFFIX) test-atlas-$(VIRTUALBOX_BOX_DIR)/$(1)$(BOX_SUFFIX)

test-atlas-vmware/$(1): test-atlas-$(VMWARE_BOX_DIR)/$(1)$(BOX_SUFFIX)

test-atlas-virtualbox/$(1): test-atlas-$(VIRTUALBOX_BOX_DIR)/$(1)$(BOX_SUFFIX)

s3cp-$(1): s3cp-$(VMWARE_BOX_DIR)/$(1)$(BOX_SUFFIX) s3cp-$(VIRTUALBOX_BOX_DIR)/$(1)$(BOX_SUFFIX)

register-atlas-$(1): register-atlas/$(1)$(BOX_SUFFIX)

endef

SHORTCUT_TARGETS := $(basename $(TEMPLATE_FILENAMES))
$(foreach i,$(SHORTCUT_TARGETS),$(eval $(call SHORTCUT,$(i))))
###############################################################################

$(VMWARE_BOX_DIR)/%$(BOX_SUFFIX): %.json $(SOURCES)
	rm -rf $(VMWARE_OUTPUT)
	mkdir -p $(VMWARE_BOX_DIR)
	$(PACKER_CMD) build -only=$(VMWARE_BUILDER) $(PACKER_VARS) $<

$(VIRTUALBOX_BOX_DIR)/%$(BOX_SUFFIX): %.json $(SOURCES)
	rm -rf $(VIRTUALBOX_OUTPUT)
	mkdir -p $(VIRTUALBOX_BOX_DIR)
	$(PACKER_CMD) build -only=$(VIRTUALBOX_BUILDER) $(PACKER_VARS) $<

list:
	@echo "Prepend 'vmware/' or 'virtualbox/' to build only one target platform:"
	@echo "  make vmware/centos7"
	@echo ""
	@echo "Targets:"
	@for shortcut_target in $(SHORTCUT_TARGETS) ; do \
		echo $$shortcut_target ; \
	done

validate:
	@for template_filename in $(TEMPLATE_FILENAMES) ; do \
		echo Checking $$template_filename ; \
		$(PACKER) validate $$template_filename ; \
	done

clean: clean-builders clean-output clean-packer-cache

clean-builders:
	@for builder in $(BUILDER_TYPES) ; do \
		if test -d box/$$builder ; then \
			echo Deleting box/$$builder/*.box ; \
			find box/$$builder -maxdepth 1 -type f -name "*.box" ! -name .gitignore -exec rm '{}' \; ; \
		fi ; \
	done

clean-output:
	@for builder in $(BUILDER_TYPES) ; do \
		echo Deleting output-$$builder-iso ; \
		echo rm -rf output-$$builder-iso ; \
	done

clean-packer-cache:
	echo Deleting packer_cache
	rm -rf packer_cache

test-vmware: $(addprefix test-,$(VMWARE_BOX_FILES))
test-virtualbox: $(addprefix test-,$(VIRTUALBOX_BOX_FILES))

test-$(VMWARE_BOX_DIR)/%$(BOX_SUFFIX): $(VMWARE_BOX_DIR)/%$(BOX_SUFFIX)
	bin/test-box.sh $< vmware_desktop vmware_fusion $(CURRENT_DIR)/test/*_spec.rb || exit

test-$(VIRTUALBOX_BOX_DIR)/%$(BOX_SUFFIX): $(VIRTUALBOX_BOX_DIR)/%$(BOX_SUFFIX)
	bin/test-box.sh $< virtualbox virtualbox $(CURRENT_DIR)/test/*_spec.rb || exit

ssh-$(VMWARE_BOX_DIR)/%$(BOX_SUFFIX): $(VMWARE_BOX_DIR)/%$(BOX_SUFFIX)
	bin/ssh-box.sh $< vmware_desktop vmware_fusion $(CURRENT_DIR)/test/*_spec.rb

ssh-$(VIRTUALBOX_BOX_DIR)/%$(BOX_SUFFIX): $(VIRTUALBOX_BOX_DIR)/%$(BOX_SUFFIX)
	bin/ssh-box.sh $< virtualbox virtualbox $(CURRENT_DIR)/test/*_spec.rb

S3_STORAGE_CLASS ?= REDUCED_REDUNDANCY
S3_ALLUSERS_ID ?= uri=http://acs.amazonaws.com/groups/global/AllUsers

s3cp-$(VMWARE_BOX_DIR)/%$(BOX_SUFFIX): $(VMWARE_BOX_DIR)/%$(BOX_SUFFIX)
	@for i in {1..20}; do \
		aws --profile $(AWS_PROFILE) s3 cp $< $(VMWARE_S3_BUCKET) --storage-class $(S3_STORAGE_CLASS) --grants full=$(S3_GRANT_ID) read=$(S3_ALLUSERS_ID) && break || sleep 62; \
	done

s3cp-$(VIRTUALBOX_BOX_DIR)/%$(BOX_SUFFIX): $(VIRTUALBOX_BOX_DIR)/%$(BOX_SUFFIX)
	@for i in {1..20}; do \
		aws --profile $(AWS_PROFILE) s3 cp $< $(VIRTUALBOX_S3_BUCKET) --storage-class $(S3_STORAGE_CLASS) --grants full=$(S3_GRANT_ID) read=$(S3_ALLUSERS_ID) && break || sleep 62; \
	done

s3cp-vmware: $(addprefix s3cp-,$(VMWARE_BOX_FILES))
s3cp-virtualbox: $(addprefix s3cp-,$(VIRTUALBOX_BOX_FILES))

ATLAS_NAME ?= inclusivedesign

test-atlas: test-atlas-vmware test-atlas-virtualbox
test-atlas-vmware: $(addprefix test-atlas-,$(VMWARE_BOX_FILES))
test-atlas-virtualbox: $(addprefix test-atlas-,$(VIRTUALBOX_BOX_FILES))

test-atlas-$(VMWARE_BOX_DIR)%$(BOX_SUFFIX):
	bin/test-vagrantcloud-box.sh inclusivedesign$* vmware_fusion vmware_desktop $(CURRENT_DIR)/test/*_spec.rb
	bin/test-vagrantcloud-box.sh inclusivedesign$* vmware_fusion vmware_desktop $(CURRENT_DIR)/test/*_spec.rb

test-atlas-$(VIRTUALBOX_BOX_DIR)%$(BOX_SUFFIX):
	bin/test-vagrantcloud-box.sh inclusivedesign$* virtualbox virtualbox $(CURRENT_DIR)/test/*_spec.rb

register-atlas: $(addprefix register-atlas-,$(basename $(TEMPLATE_FILENAMES)))

register-atlas/%$(BOX_SUFFIX):
	bin/register_atlas.sh $* $(BOX_SUFFIX) $(BOX_VERSION)
	bin/register_atlas_box_cutter.sh $* $(BOX_SUFFIX) $(BOX_VERSION)
