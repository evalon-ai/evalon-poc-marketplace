#!/usr/bin/env bash
# evalon-poc: echo hook name + short argument summary back to the user via systemMessage.
# Never blocks, never auto-approves: always exits 0. Works on macOS, Linux, Windows (Git Bash).

INPUT="$(cat)"
MAX=200

case "$(uname -s 2>/dev/null)" in
  Darwin*)               OS="macOS" ;;
  Linux*)                OS="Linux" ;;
  MINGW*|MSYS*|CYGWIN*)  OS="Windows" ;;
  *)                     OS="${OS:-unknown}" ;;
esac

# Extract a field: use jq when available, otherwise a crude sed fallback.
str_field() {  # top-level string value
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r --arg k "$1" '.[$k] // empty | if type=="string" then . else tojson end'
  else
    printf '%s' "$INPUT" | tr -d '\n\r' | sed -nE "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\".*/\1/p"
  fi
}
raw_field() {  # any value (object/string), rough text after the key
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -c --arg k "$1" '.[$k] // empty'
  else
    printf '%s' "$INPUT" | tr -d '\n\r' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*//p"
  fi
}
trim() { printf '%s' "$1" | tr -d '\n\r\t' | cut -c1-"$MAX"; }

EVENT="$(str_field hook_event_name)"
case "$EVENT" in
  PreToolUse)       DETAIL="🛫 PreToolUse · $(str_field tool_name) · $(trim "$(raw_field tool_input)")" ;;
  PostToolUse)      DETAIL="🛬 PostToolUse · $(str_field tool_name) · $(trim "$(raw_field tool_response)")" ;;
  SessionStart)     DETAIL="🚀 SessionStart · source=$(str_field source) · session=$(str_field session_id)" ;;
  UserPromptSubmit) DETAIL="💬 UserPromptSubmit · $(trim "$(str_field prompt)")" ;;
  *)                DETAIL="❓ ${EVENT:-unknown-event} · $(trim "$INPUT")" ;;
esac

MSG="🪝 [evalon-poc] [$OS] $DETAIL"
# JSON-escape: backslashes, quotes, strip control chars
ESC="$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\037')"
printf '{"systemMessage":"%s"}\n' "$ESC"
exit 0
