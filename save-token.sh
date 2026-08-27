#!/bin/bash
# Получает OAuth-токен Яндекса и кладёт его в ~/.config/yandex-direct/token.
# Ввод скрытый: ни URL, ни токен не попадают в историю shell.
#
#   ./save-token.sh <CLIENT_ID>     — Client ID приложения из oauth.yandex.ru
#   ./save-token.sh                 — возьмёт client_id из config.json или $YANDEX_DIRECT_CLIENT_ID
set -euo pipefail

CONFIG_DIR="${YANDEX_DIRECT_CONFIG_DIR:-$HOME/.config/yandex-direct}"
CONFIG="$CONFIG_DIR/config.json"
DEST="$CONFIG_DIR/token"
HERE="$(cd "$(dirname "$0")" && pwd)"

CLIENT_ID="${1:-${YANDEX_DIRECT_CLIENT_ID:-}}"
if [ -z "$CLIENT_ID" ] && [ -f "$CONFIG" ]; then
  CLIENT_ID="$(node -e 'try{const c=require(process.argv[1]);process.stdout.write(c.client_id||"")}catch(e){}' "$CONFIG" 2>/dev/null || true)"
fi

if [ -z "$CLIENT_ID" ]; then
  cat >&2 <<'MSG'
Не задан Client ID приложения.

  ./save-token.sh <CLIENT_ID>

Где взять: https://oauth.yandex.ru → своё приложение → поле ClientID.
Важно: это должно быть то приложение, на которое ОДОБРЕНА заявка на доступ к API,
иначе Директ ответит ошибкой 58 «Незавершенная регистрация».
MSG
  exit 1
fi

echo "1) Открой в браузере и нажми «Разрешить»:"
echo "   https://oauth.yandex.ru/authorize?response_type=token&client_id=$CLIENT_ID"
echo "2) Скопируй адресную строку страницы, куда тебя перекинет (или сам токен)."
echo

read -rsp "Вставь URL или токен: " input
echo

token="$(printf '%s' "$input" | sed -n 's/.*access_token=\([^&]*\).*/\1/p')"
[ -z "$token" ] && token="$(printf '%s' "$input" | tr -d '[:space:]')"

if [ "${#token}" -lt 20 ]; then
  echo "Не похоже на токен (длина ${#token}). Ничего не записал." >&2
  exit 1
fi

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
printf '%s' "$token" > "$DEST"
chmod 600 "$DEST"
echo "Токен сохранён: $DEST (${#token} симв., ...${token: -4})"

# запомнить client_id, чтобы в следующий раз запускать без аргумента
node -e '
const fs=require("fs"),p=process.argv[1],id=process.argv[2];
let c={};try{c=JSON.parse(fs.readFileSync(p,"utf8"))}catch(e){}
c.client_id=id;
fs.writeFileSync(p,JSON.stringify(c,null,2)+"\n",{mode:0o600});
' "$CONFIG" "$CLIENT_ID" 2>/dev/null || true

echo
echo "Проверяю доступ к API…"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"direct_status","arguments":{}}}' \
  | node "$HERE/server.js" \
  | node -e 'let b="";process.stdin.on("data",d=>b+=d).on("end",()=>{for(const l of b.trim().split("\n")){const m=JSON.parse(l);if(m.result&&m.result.content)console.log(m.result.content[0].text)}})'
