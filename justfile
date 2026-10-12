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
