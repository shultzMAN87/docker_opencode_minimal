# OpenCode в Docker с MCP-серверами из config/mcp.json
#
# Базовый образ — Node, чтобы локальные MCP-серверы на npx работали «из коробки».
# Дополнительно ставится uv (uvx) для MCP-серверов на Python.

FROM node:22-bookworm-slim

ARG OPENCODE_VERSION=1.19.3

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq ripgrep python3 \
 && rm -rf /var/lib/apt/lists/*

# uv / uvx — для MCP-серверов, которые запускаются через uvx
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" \
 && npm cache clean --force \
 && opencode --version

# Работаем от непривилегированного пользователя node (uid 1000)
USER node
ENV HOME=/home/node
WORKDIR /workspace

# Файлы в /workspace монтируются с хоста и часто принадлежат другому uid
# (особенно на Windows/macOS). Без этого git откажется работать с репозиторием
# ("dubious ownership"), и OpenCode не распознает папку как проект.
RUN git config --global --add safe.directory '*'

# Сборка итогового конфига: базовые настройки + MCP-серверы.
# jq проверяет JSON: при ошибке в mcp.json сборка остановится и покажет, где она.
COPY --chown=node:node config/ /tmp/opencode-config/
RUN mkdir -p ~/.config/opencode ~/.local/share/opencode \
 && jq -s '.[0] * .[1]' /tmp/opencode-config/opencode.json /tmp/opencode-config/mcp.json \
      > ~/.config/opencode/opencode.json \
 && rm -rf /tmp/opencode-config \
 && echo "MCP-серверы в образе:" \
 && jq -r '.mcp // {} | to_entries[] | "  - \(.key) [\(.value.type)] \(if .value.enabled == false then "выключен" else "включён" end)"' \
      ~/.config/opencode/opencode.json

EXPOSE 4096

# По умолчанию — веб-интерфейс. TUI запускается отдельной командой (см. README).
CMD ["opencode", "web", "--hostname", "0.0.0.0", "--port", "4096"]
