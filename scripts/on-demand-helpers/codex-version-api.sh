#!/bin/bash
# OpenAI Codex 的版本 tag 带有 "rust-" 前缀，需要去除
curl -s "https://api.github.com/repos/openai/codex/releases/latest" | jq -c "{\"version\": (.tag_name | sub(\"^rust-\"; \"\") | sub(\"^v\"; \"\"))}" 2>/dev/null
