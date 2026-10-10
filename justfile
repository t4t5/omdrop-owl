# Development tasks. `just` lists them.

[private]
default:
    @just --list

# Build OWL and assemble build/lib, laid out like /usr/lib/omdrop
build:
    tools/build-owl.sh
    tools/stage.sh

# Build and install the pacman package
install:
    makepkg -si

# Test this computer's card against build/lib and write a report (README, "Adding your card")
test *ARGS: build
    sudo tools/test-card.sh --lib build/lib {{ARGS}}
