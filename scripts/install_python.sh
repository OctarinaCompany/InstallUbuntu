#!/bin/bash

sudo apt -y install pipx

sudo apt -y install pip

export PATH="$HOME/.local/bin:$PATH"

pipx ensurepath

pipx install uv

uv python install
