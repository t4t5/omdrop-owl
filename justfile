# Development tasks. `just` lists them.

[private]
default:
    @just --list

# Build OWL and assemble build/lib, laid out like /usr/lib/omdrop
build:
    tools/build-owl.sh
    tools/stage.sh

# Build and install the pacman package from this checkout
install:
    makepkg -si

# Build the AUR's PKGBUILD against this checkout, as CI does for pull requests
test-aur:
    tools/test-aur-pkgbuild.sh

# Test this computer's card against build/lib and write a report (README, "Adding your card")
test *ARGS: build
    sudo tools/test-card.sh --lib build/lib {{ARGS}}

# Preview README as GitHub renders it (dark by default; `just readme-preview light`)
readme-preview theme="dark":
    #!/usr/bin/env bash
    set -euo pipefail
    out=.readme-preview.html
    # Export next to the README so relative image paths keep working.
    uvx grip --export --quiet --user "$(gh api user --jq .login)" --pass "$(gh auth token)" README.md "$out"
    sed -i 's|<html lang="en">|<html lang="en" data-color-mode="{{theme}}" data-{{theme}}-theme="{{theme}}">|' "$out"
    xdg-open "$out"
