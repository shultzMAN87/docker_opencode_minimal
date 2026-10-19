# OpenCode в Docker с MCP-серверами

Мини-проект для запуска [OpenCode](https://opencode.ai) в контейнере.
MCP-серверы описываются в одном файле `config/mcp.json`. При сборке образа он
встраивается в глобальный конфиг OpenCode, и серверы сразу доступны агенту.

## Состав

```
.
├── config/
│   ├── mcp.json        # ← MCP-серверы (редактируете вы)
│   └── opencode.json   # базовые настройки OpenCode
├── workspace/          # проект, с которым работает агент (монтируется в /workspace)
├── Dockerfile
├── compose.yml
├── .env.example
├── .dockerignore
└── .gitignore
```

Образ собирается на `node:22-bookworm-slim`. В нём уже есть:

- `opencode` (версия задаётся в `OPENCODE_VERSION`);
- `npx` для MCP-серверов на Node.js;
- `uv` / `uvx` и `python3` для MCP-серверов на Python;
- `git`, `ripgrep`, `jq`, `curl`.

## Быстрый старт

```bash
cp .env.example .env              # раскомментируйте ключ провайдера LLM
docker compose up -d --build
```

Во время сборки выводится список MCP-серверов, попавших в образ:

```
MCP-серверы в образе:
  - everything [local] выключен
  - fetch [local] включён
  - example-remote [remote] выключен
```

Веб-интерфейс открывается на **http://localhost:4096**.

### Терминальный интерфейс (TUI)

```bash
docker compose exec -it opencode opencode
```

Запускает TUI внутри контейнера в папке `/workspace`. Можно и подключиться к
уже работающему веб-серверу, тогда сессии будут общие с веб-интерфейсом:

```bash
docker compose exec -it opencode opencode attach http://localhost:4096
```

## Как добавить MCP-сервер

1. Отредактируйте `config/mcp.json`.
2. Пересоберите образ: `docker compose up -d --build`.
3. Проверьте подключение: `docker compose exec opencode opencode mcp list`.

Формат файла — объект `mcp`, где ключ задаёт имя сервера. Файл должен быть
обычным JSON без комментариев. Если в нём ошибка, сборка остановится на шаге с
`jq` и покажет строку.

### Локальный сервер (запускается внутри контейнера)

```json
"fetch": {
  "type": "local",
  "command": ["uvx", "mcp-server-fetch"],
  "environment": { "SOME_VAR": "value" },
  "enabled": true
}
```

`command` — массив: программа и её аргументы. Внутри контейнера доступны
`npx` и `uvx`, для них ничего доустанавливать не нужно.

### Удалённый сервер (HTTP)

```json
"my-server": {
  "type": "remote",
  "url": "http://host.docker.internal:8000/mcp",
  "oauth": false,
  "headers": { "Authorization": "Bearer {env:MY_TOKEN}" },
  "enabled": true
}
```

- **Сервер на хосте.** Обращайтесь к нему через `host.docker.internal`, а не через
  `localhost`: `localhost` внутри контейнера — это сам контейнер. Этот адрес
  настроен в `compose.yml` и работает на Linux, Windows и macOS.
- **Сервер в другом compose-проекте.** Подключите оба проекта к общей
  docker-сети и обращайтесь по имени сервиса.
- **Без авторизации.** `"oauth": false` отключает автоматическую попытку OAuth;
  уберите его, если сервер действительно работает через OAuth.

### Остальные поля

| Поле | Для | Назначение |
|---|---|---|
| `enabled` | оба типа | `false` — сервер описан, но не запускается |
| `timeout` | оба типа | сколько ждать список инструментов, мс (по умолчанию 5000) |
| `cwd` | local | рабочая папка процесса |

## Секреты

Ключи и токены в `mcp.json` не пишите: файл попадает в git и в образ.
Подставляйте их из переменных окружения через `{env:ИМЯ}`:

```json
"headers": { "Authorization": "Bearer {env:MY_TOKEN}" }
```

Сами значения храните в `.env`. Compose передаёт все переменные из него в
контейнер, а OpenCode подставляет их при запуске. Значит, после смены
токена достаточно перезапуска, пересборка не нужна:

```bash
docker compose up -d
```

## LLM-провайдер

Есть два способа подключить модель:

- раскомментировать ключ в `.env` (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
  `OPENROUTER_API_KEY` и т.д.);
- выполнить `/connect` в интерфейсе OpenCode. Ключ сохранится в томе
  `opencode-data` и переживёт пересоздание контейнера.

Модель по умолчанию задаётся в `config/opencode.json`, после изменения нужна
пересборка:

```json
"model": "anthropic/claude-sonnet-4-5"
```

## Настройки `.env`

| Переменная | По умолчанию | Что задаёт |
|---|---|---|
| `OPENCODE_VERSION` | `1.19.3` | версия OpenCode в образе |
| `OPENCODE_PORT` | `4096` | порт веб-интерфейса на хосте |
| `WORKSPACE_DIR` | `./workspace` | папка проекта на хосте, монтируется в `/workspace` |
| `OPENCODE_SERVER_PASSWORD` | не задан | пароль веб-интерфейса, логин `opencode` |

Чтобы работать с существующим проектом, укажите путь к нему:

```env
WORKSPACE_DIR=D:/projects/my-repo
```

## OpenCode не видит проект

OpenCode считает проектом **корень git-репозитория**. Если в папке нет `.git`,
он работает в режиме `global` с корнем `/`, и файлов проекта не видно.

Проверить, что определил сервер:

```bash
docker compose exec opencode sh -c 'curl -s -u "opencode:$OPENCODE_SERVER_PASSWORD" http://localhost:4096/project/current'
```

Должно быть `"worktree":"/workspace"`. Если там `"id":"global","worktree":"/"`,
разберите случай ниже.

**В `/workspace` нет git.** Инициализируйте репозиторий и перезапустите:

```bash
docker compose exec opencode git init /workspace
docker compose restart opencode
```

Или укажите в `WORKSPACE_DIR` папку, которая уже является git-репозиторием.

**Репозиторий лежит во вложенной папке** (`workspace/my-project/.git`). Сама
`/workspace` проектом не будет. Либо укажите в `WORKSPACE_DIR` путь прямо к
`my-project`, либо запустите TUI с этой папкой:

```bash
docker compose exec -it opencode opencode /workspace/my-project
```

**Проверка, что файлы вообще смонтированы:**

```bash
docker compose exec opencode ls -la /workspace
```

Если папка пустая, значит путь в `WORKSPACE_DIR` неверный. На Windows
указывайте его с прямыми слешами (`D:/projects/my-repo`). После изменения
`.env` пересоздайте контейнер командой `docker compose up -d`.

Права на файлы с хоста в образе уже учтены (`git safe.directory`), так что
ошибка git «dubious ownership» проект не скрывает.

## Данные и сброс

Сессии, история и ключи из `/connect` лежат в томе `opencode-data`.

```bash
docker compose down        # остановить, данные сохраняются
docker compose down -v     # удалить вместе с сессиями и ключами
```

## Безопасность

- Без `OPENCODE_SERVER_PASSWORD` веб-интерфейс открыт любому, кто достучится
  до порта. Если машина доступна по сети, задайте пароль.
- Агент может выполнять команды в контейнере и менять файлы в `/workspace`.
  Монтируйте только тот проект, с которым он должен работать.
- Контейнер работает от пользователя `node` (uid 1000), а не от root.
