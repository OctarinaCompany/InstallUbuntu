#!/bin/bash

npm i -D @playwright/test

npx playwright install

npx playwright install-deps

npm init playwright@latest

npx playwright install chrome
npx playwright install firefox
npx playwright install webkit

# npm init playwright@latest
# npm install playwright
# npm install playwright-firefox
# npm install playwright-webkit
