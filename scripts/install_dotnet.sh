#!/bin/bash

curl -L https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh

chmod +x ./dotnet-install.sh

./dotnet-install.sh --channel LTS --install-dir ~/.dotnet-lts

./dotnet-install.sh --channel STS --install-dir ~/.dotnet-latest

echo 'export DOTNET_ROOT=$HOME/.dotnet-latest' >> ~/.bashrc

echo 'export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools' >> ~/.bashrc

# alias dotnet-lts='DOTNET_ROOT=$HOME/.dotnet-lts $HOME/.dotnet-lts/dotnet'
# alias dotnet-latest='DOTNET_ROOT=$HOME/.dotnet-latest $HOME/.dotnet-latest/dotnet'

rm -f dotnet-install.sh
