#!/bin/bash

curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash

source ~/.nvm/nvm.sh

nvm install --lts

nvm use --lts

npm update -g npm


