SHELL_SCRIPTS := script/app_bundle.sh script/build_and_run.sh script/package.sh script/install_latest.sh script/install_agent_tools.sh script/sparkle.sh script/test.sh script/test_app_bundle.sh script/test_install_latest.sh script/test_install_agent_tools.sh script/version.sh

.PHONY: build check run package install-latest install-agent-tools release status

VERSION ?=

build:
	swift build

check:
	./script/test.sh
	./script/test_install_latest.sh
	./script/test_app_bundle.sh
	./script/test_install_agent_tools.sh
	@for script in $(SHELL_SCRIPTS); do \
		bash -n "$$script" || exit 1; \
	done

run:
	./script/build_and_run.sh

package:
	CONTEXT_VERSION="$(VERSION)" ./script/package.sh

install-latest:
	./script/install_latest.sh

install-agent-tools:
	./script/install_agent_tools.sh

release:
	@if [ -z "$(VERSION)" ]; then \
		echo "usage: make release VERSION=v0.1.0" >&2; \
		exit 2; \
	fi
	@CONTEXT_VERSION="$(VERSION)" bash script/version.sh >/dev/null
	git tag "$(VERSION)"
	git push origin main
	git push origin "$(VERSION)"

status:
	git status -sb
