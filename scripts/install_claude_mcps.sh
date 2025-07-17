#!/bin/bash

claude mcp add playwright npx @playwright/mcp@latest

claude mcp add --transport http context7 https://mcp.context7.com/mcp

claude mcp add serena --uvx --from git+https://github.com/oraios/serena serena-mcp-server --context ide-assistant --project $(pwd)

#uvx --from git+https://github.com/oraios/serena serena-mcp-server