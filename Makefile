include Makefile.config
-include Makefile.custom.config

all: install lint check-outdated run-debug

install:
	test -d $(VENV) || virtualenv $(VENV) -p $(PYTHON_VERSION)
	$(PIP) install --upgrade --no-cache pip setuptools -e .[lint,themes] devcore
	$(NPM) install

clean:
	rm -fr $(NODE_MODULES)
	rm -fr $(VENV)
	rm -fr *.egg-info

lint:
	$(PYTEST) --flake8 -m flake8 $(PROJECT_NAME)
	$(PYTEST) --isort -m isort $(PROJECT_NAME)

check-outdated:
	$(PIP) list --outdated --format=columns

ARGS ?= --port=1212 --unsecure --debug
run-debug:
	$(PYTHON) ./butterfly.server.py $(ARGS)

build-coffee:
	$(NODE_MODULES)/.bin/grunt

release: build-coffee
	git pull
	$(eval VERSION := $(shell PROJECT_NAME=$(PROJECT_NAME) $(VENV)/bin/devcore bump $(LEVEL)))
	git commit -am "Bump $(VERSION)"
	git tag $(VERSION)
	$(PYTHON) setup.py sdist bdist_wheel upload
	git push
	git push --tags
