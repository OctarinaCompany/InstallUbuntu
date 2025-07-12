#!/bin/bash

sudo apt update

sudo apt -y install pipx

sudo apt -y install pip

pipx install uv

uv python install
