#!/usr/bin/env bash
# Push a notification to Tim's phone via ntfy.sh (ntfy iOS app, private topic in
# ~/.beerwithme-ntfy-topic on tim-server). Used by Claude sessions and CI helpers.
#
#   tools/notify.sh "message"                       # plain
#   tools/notify.sh -t "Title" -p high "message"    # title + priority (min/low/default/high/urgent)
#   tools/notify.sh -a "https://..." "message"      # tap-to-open URL
set -euo pipefail
TITLE="Beer With Friends"; PRIO="default"; CLICK=""
while getopts "t:p:a:" opt; do
  case $opt in
    t) TITLE="$OPTARG" ;;
    p) PRIO="$OPTARG" ;;
    a) CLICK="$OPTARG" ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
MSG="${*:-}"
[ -n "$MSG" ] || { echo "usage: tools/notify.sh [-t title] [-p prio] [-a url] message" >&2; exit 2; }
TOPIC_FILE="${NTFY_TOPIC_FILE:-$HOME/.beerwithme-ntfy-topic}"
TOPIC="$(cat "$TOPIC_FILE")"
args=(-s -o /dev/null -w '%{http_code}\n' -H "Title: $TITLE" -H "Priority: $PRIO" -H "Tags: beer")
[ -n "$CLICK" ] && args+=(-H "Click: $CLICK")
curl "${args[@]}" -d "$MSG" "https://ntfy.sh/$TOPIC"
