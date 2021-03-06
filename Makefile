#
# Options
#

# Or you may want to select an explicit Python version, e.g. python2.7
PYTHON = python

# Directory that will be nuked and created for stuff
TMPDIR = tmp

#
# Bit of an implementation detail: all scripts generated by buildout
#
scripts = bin/test bin/detox bin/python bin/zodbbrowser

# my cargo-culted release rules
FILE_WITH_VERSION = src/zodbbrowser/__init__.py
FILE_WITH_CHANGELOG = CHANGES.rst
VCS_STATUS = git status --porcelain
VCS_EXPORT = git archive --format=tar --prefix=tmp/tree/ HEAD | tar -xf -
VCS_TAG = git tag
VCS_COMMIT_AND_PUSH = git commit -av -m \"Post-release version bump\" && git push && git push --tags


#
# Interesting targets
#

.PHONY: all
all: $(scripts)

.PHONY: test
test: bin/test
	bin/test -s zodbbrowser --auto-color -v1

.PHONY: check
check: bin/detox test
	bin/detox

# test with pager
.PHONY: testp
testp:
	bin/test -s zodbbrowser -vc 2>&1 |less -RFX

.PHONY: coverage
coverage:
	bin/tox -e coverage

.PHONY: tags
tags:
	bin/ctags

.PHONY: preview-pypi-description
preview-pypi-description:
	# pip install restview, if missing
	restview -e "$(PYTHON) setup.py --long-description"

.PHONY: dist
dist:
	$(PYTHON) setup.py sdist

.PHONY: checkzope2
checkzope2: dist python/bin/python
	version=`$(PYTHON) setup.py --version` && \
	rm -rf $(TMPDIR) && \
	mkdir $(TMPDIR) && \
	cd $(TMPDIR) && \
	tar xvzf ../dist/zodbbrowser-$$version.tar.gz && \
	cd zodbbrowser-$$version && \
	../../python/bin/python bootstrap.py && \
	bin/buildout -c zope2.cfg && \
	bin/test -s zodbbrowser

.PHONY: distcheck
distcheck: check checkzope2 dist
	version=`$(PYTHON) setup.py --version` && \
	rm -rf $(TMPDIR) && \
	mkdir $(TMPDIR) && \
	cd $(TMPDIR) && \
	tar xvzf ../dist/zodbbrowser-$$version.tar.gz && \
	cd zodbbrowser-$$version && \
	make dist && \
	cd .. && \
	mkdir one two && \
	cd one && \
	tar xvzf ../../dist/zodbbrowser-$$version.tar.gz && \
	cd ../two/ && \
	tar xvzf ../zodbbrowser-$$version/dist/zodbbrowser-$$version.tar.gz && \
	cd .. && \
	diff -ur one two -x SOURCES.txt && \
	cd .. && \
	rm -rf $(TMPDIR) && \
	echo "sdist seems to be ok"
# I'm ignoring SOURCES.txt since it appears that the second sdist gets a new
# source file, namely, setup.cfg.  Setuptools/distutils black magic, may it rot
# in hell forever.

release:
	@$(PYTHON) setup.py --version | grep -qv dev || { \
	    echo "Please remove the 'dev' suffix from the version number in $(FILE_WITH_VERSION)"; exit 1; }
	@$(PYTHON) setup.py --long-description | rst2html --exit-status=2 > /dev/null || { \
	    echo "There's a ReStructuredText error in the package description"; exit 1; }
	@ver_and_date="`$(PYTHON) setup.py --version` (`date +%Y-%m-%d`)" && \
	    grep -q "^$$ver_and_date$$" $(FILE_WITH_CHANGELOG) || { \
	        echo "$(FILE_WITH_CHANGELOG) has no entry for $$ver_and_date"; exit 1; }
	@test -z "`$(VCS_STATUS) 2>&1`" || { echo "Your working tree is not clean:" 1>&2; $(VCS_STATUS) 1>&2; exit 1; }
	make distcheck
	# I'm chicken so I won't actually do these things yet
	@echo Please run rm -rf dist && $(PYTHON) setup.py sdist && twine upload dist/*
	@echo Please run $(VCS_TAG) `$(PYTHON) setup.py --version`
	@echo Please increment the version number in $(FILE_WITH_VERSION)
	@echo Please add a new empty entry in $(FILE_WITH_CHANGELOG)
	@echo "Then please $(VCS_COMMIT_AND_PUSH)"

#
# Implementation
#

bin/buildout: python/bin/python bootstrap.py
	python/bin/pip install -U setuptools
	python/bin/python bootstrap.py

python/bin/python:
	virtualenv -p $(PYTHON) python

$(scripts): bin/buildout
	bin/buildout
	touch -c $(scripts)
