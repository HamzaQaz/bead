#!/usr/bin/env bash
# Claude Code ↔ Glint bridge (bead). Handles these hook events:
#   PermissionRequest             Allow / Deny; the answer goes straight back to Claude
#   PreToolUse (AskUserQuestion)  the terminal shows the question at once; a toast
#                                 offers the same options and types the pick there
#   PostToolUse (AskUserQuestion) answered in the terminal: withdraw that toast
#                                 (declined with Esc: the worker sees the answer in
#                                 the transcript and withdraws it too)
#   Stop                          "Claude finished" + the start of its reply, every turn
#   Notification                  passive toast (sign-in, usage limit; "waiting" only
#                                 when no "finished" toast went out for that turn)
#
# Every toast names the session it comes from. Toasts from all Claude sessions share
# one queue, so only one shows at a time, ordered by priority, then age:
#   1 permission   2 question   3 notification
# If the terminal running that session is focused (when asked, or while it waits in
# the queue), nothing is shown and the normal prompt appears there. Dismissing a
# toast also hands the prompt back to the terminal.
in=$(cat)
command -v glint >/dev/null || exit 0
get() { jq -r "$1 // empty" <<<"$in" 2>/dev/null; }

marks=${XDG_RUNTIME_DIR:-/tmp}/claude-toast
queue=$marks/queue
mkdir -p "$queue"
mark=$marks/$(get .session_id).perm
log() { echo "$(date +%T) $(get .hook_event_name) $(get .tool_name)$(get .notification_type) [$session]: $*" >>"$marks/hook.log"; }

# Is the window running this Claude session the focused one?
focused() {
	[ -n "${CLAUDE_TOAST_FORCE:-}" ] && return 1 # testing: always show
	local a p
	a=$(hyprctl activewindow -j 2>/dev/null | jq -r '.pid // empty') || return 1
	[ -n "$a" ] || return 1
	p=${CLAUDE_TOAST_PID:-$PPID}
	while [ -n "$p" ] && [ "$p" -gt 1 ]; do
		[ "$p" = "$a" ] && return 0
		p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
	done
	return 1
}

# Session name: your /rename title, else Claude's generated title, else the folder.
session_name() {
	local t n=""
	t=$(get .transcript_path)
	if [ -f "$t" ]; then
		n=$(tac "$t" | grep -m1 -oE '"customTitle":"[^"]*"' | cut -d'"' -f4)
		[ -n "$n" ] || n=$(tac "$t" | grep -m1 -oE '"aiTitle":"[^"]*"' | cut -d'"' -f4)
	fi
	[ -n "$n" ] || n=$(basename "$(get .cwd)")
	[ ${#n} -gt 48 ] && n="${n:0:47}…"
	printf '%s' "$n"
}
session=$(session_name)

# toast descriptions are rich text: escape it
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
# body = session name (bright) on top, then the content
body() { printf "<b>%s</b><br>%s" "$(esc <<<"$session")" "$1"; }

# ── queue ──
now_ms() { date +%s%3N; }
# the screen stays busy until a toast has finished animating out
busy_for() { echo $(($(now_ms) + $1)) >"$marks/busy"; }
screen_free() { [ "$(now_ms)" -ge "$(cat "$marks/busy" 2>/dev/null || echo 0)" ]; }

ticket=
# wait_turn PRIORITY MAX_WAIT_S: queue up; returns 1 if we gave up or the terminal got focus
wait_turn() {
	ticket=$queue/$1-$(now_ms)-$BASHPID
	: >"$ticket"
	trap 'rm -f "$ticket"' EXIT
	local start=$SECONDS t pid first
	while :; do
		for t in "$queue"/*; do # drop tickets of hooks that died
			[ -e "$t" ] || continue
			pid=${t##*-}
			kill -0 "$pid" 2>/dev/null || rm -f "$t"
		done
		first=$(ls "$queue" | sort | head -1)
		[ "$queue/$first" = "$ticket" ] && screen_free && return 0
		focused && { log "terminal focused while queued"; return 1; }
		[ "$1" = 2 ] && settled && { log "question settled while queued"; return 1; }
		((SECONDS - start > $2)) && { log "gave up waiting in queue"; return 1; }
		sleep 0.25
	done
}
done_turn() { busy_for "${1:-0}"; rm -f "$ticket"; }

event=$(get .hook_event_name)

# ── questions: the toast that mirrors a terminal question ──
qmark=$marks/$(get .session_id).q # "<worker pid> <toast pid>" while a question toast is up
withdraw_question() {
	local w t
	[ -f "$qmark" ] && read -r w t <"$qmark" || return 0
	rm -f "$qmark"
	[ -n "$w" ] && kill "$w" 2>/dev/null
	[ -n "$t" ] && { qs -p "${XDG_DATA_HOME:-$HOME/.local/share}/bead" ipc call toast close "$t-" >/dev/null 2>&1; kill "$t" 2>/dev/null; }
	log "question answered in the terminal: toast withdrawn"
}
# this question has an answer in the transcript (picked, declined with Esc,
# interrupted: Esc sends no PostToolUse or Stop, so watch for the result)
tuid=$(get .tool_use_id)
settled() {
	[ -n "$tuid" ] && [ -f "$(get .transcript_path)" ] &&
		tail -c 400000 "$(get .transcript_path)" | grep -qF "\"tool_use_id\":\"$tuid\""
}
# the window running this session, by its process
claude_window_pid() {
	local pids p
	pids=" $(hyprctl clients -j 2>/dev/null | jq -r '[.[].pid] | join(" ")') "
	p=${CLAUDE_TOAST_PID:-$PPID}
	while [ -n "$p" ] && [ "$p" -gt 1 ]; do
		[[ $pids == *" $p "* ]] && { echo "$p"; return 0; }
		p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
	done
	return 1
}
# go to this session's terminal (a toast's body was clicked)
go_terminal() {
	local w
	w=$(claude_window_pid) || return 0
	hyprctl dispatch "hl.dsp.focus({ window = \"pid:$w\" })" >/dev/null && log "clicked: focused the terminal"
}

case $event in
PostToolUse | PostToolUseFailure) [ "$(get .tool_name)" = AskUserQuestion ] && withdraw_question; exit 0 ;;
Stop) withdraw_question ;; # the turn ended (a question declined with Esc, say)
esac

if [ "${1:-}" != --worker ]; then
	focused && { log "terminal focused, skipping"; exit 0; }
fi

case $event in
PermissionRequest)
	tool=$(get .tool_name)
	# Questions are answered by the PreToolUse branch (or in the terminal), never as Allow/Deny.
	[ "$tool" = AskUserQuestion ] && exit 0
	# A readable one-glance summary: the obvious field for common tools, else key: value lines.
	what=$(jq -r '.tool_input
		| if .command then .command
		  elif .file_path then .file_path
		  elif .url then .url
		  elif .pattern then .pattern
		  else to_entries | map("\(.key): \(.value | if type == "string" then . else tojson end | .[0:80])") | join("\n")
		  end' <<<"$in" | head -c 400 | esc | sed ':a;N;$!ba;s/\n/<br>/g')
	name=$tool
	[[ $name == mcp__* ]] && name=${name#mcp__} && name=${name//__/ }
	touch "$mark"
	wait_turn 1 200 || exit 0
	log "showing permission toast"
	left=$((280 - SECONDS))
	ans=$(glint choose "Allow $name?" -d "$(body "$what")" -c Allow -c Deny \
		--react success:Allowed --react error:Denied -i "✻" -p top-right -t "${left}s" 2>/dev/null)
	ok=$?
	[ $ok = 3 ] && { done_turn 300; go_terminal; exit 0; } # clicked: answer in the terminal
	done_turn 2000 # let the reaction play before the next toast
	[ $ok = 0 ] || exit 0
	if [ "$ans" = Allow ]; then
		jq -n '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"allow"}}}'
	else
		jq -n '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"deny",message:"Denied from the desktop toast."}}}'
	fi
	;;

PreToolUse) # AskUserQuestion: never block, so the terminal shows the question too
	[ "$(get .tool_name)" = AskUserQuestion ] || exit 0
	if [ "${1:-}" != --worker ]; then
		CLAUDE_TOAST_PID=$PPID setsid -f "$0" --worker <<<"$in" >/dev/null 2>&1
		exit 0
	fi
	echo "$$" >"$qmark"
	touch "$mark" # Claude Code's "needs permission" notification for this question is a duplicate
	n=$(jq '.tool_input.questions | length' <<<"$in")
	[ "$n" -ge 1 ] || exit 0
	wait_turn 2 200 || { rm -f "$qmark"; exit 0; }
	[ -f "$qmark" ] || { done_turn 0; exit 0; } # answered while queued
	# all the questions in one toast, one after another: full-width options
	# with their descriptions, ticks for the pick-several ones
	out=$(mktemp)
	log "showing question toast ($n)"
	glint ask "Question" --questions "$(jq -c '.tool_input.questions' <<<"$in")" \
		-d "$(printf '<b>%s</b>' "$(esc <<<"$session")")" -i "✻" -p top-right -t 280s >"$out" 2>/dev/null &
	tp=$!
	echo "$$ $tp" >"$qmark"
	while kill -0 "$tp" 2>/dev/null; do
		if settled; then
			rm -f "$qmark" "$out"
			qs -p "${XDG_DATA_HOME:-$HOME/.local/share}/bead" ipc call toast close "$tp-" >/dev/null 2>&1
			kill "$tp" 2>/dev/null
			log "question settled in the terminal: toast withdrawn"
			done_turn 900
			exit 0
		fi
		sleep 0.5
	done
	wait "$tp"; rc=$?
	settled && { rm -f "$qmark" "$out"; done_turn 900; exit 0; } # too late to type: it's answered
	if [ $rc != 0 ]; then # dismissed (or clicked: go there): the terminal still asks
		rm -f "$qmark" "$out"
		done_turn 900
		[ $rc = 3 ] && go_terminal
		exit 0
	fi
	picks=$(cat "$out"); rm -f "$out" "$qmark"
	jq -e --argjson n "$n" 'type == "array" and length == $n' <<<"$picks" >/dev/null 2>&1 || exit 0
	done_turn 1500
	# take the picks to the terminal: focus it, then each question in turn
	# (arrows: number keys don't select there). One pick: its option, and it
	# moves on. Several: Enter ticks each, then the row after "Type
	# something" (Next, or Submit when it's the only question). After the
	# last of several questions a review screen opens on Submit.
	w=$(claude_window_pid) || exit 0
	hyprctl dispatch "hl.dsp.focus({ window = \"pid:$w\" })" >/dev/null # Lua-config Hyprland
	sleep 0.25
	# only ever type into that terminal
	[ "$(hyprctl activewindow -j 2>/dev/null | jq -r '.pid // empty')" = "$w" ] || { log "terminal didn't take focus: not typing"; exit 0; }
	log "typing $picks into the terminal"
	down() { for ((k = 0; k < $1; k++)); do wtype -k Down; sleep 0.05; done; }
	for ((qi = 0; qi < n; qi++)); do
		opts=$(jq --argjson i "$qi" '.tool_input.questions[$i].options | length' <<<"$in")
		cur=0
		if [ "$(jq --argjson i "$qi" '.tool_input.questions[$i].multiSelect == true' <<<"$in")" = true ]; then
			for i in $(jq -r --argjson i "$qi" '.[$i] | sort | .[]' <<<"$picks"); do
				down $((i - cur)); cur=$i
				sleep 0.1; wtype -k Return; sleep 0.15
			done
			down $((opts + 1 - cur)) # past "Type something" to Next / Submit
		else
			down "$(jq -r --argjson i "$qi" '.[$i][0]' <<<"$picks")"
		fi
		sleep 0.1; wtype -k Return; sleep 0.35
	done
	if [ "$n" -gt 1 ]; then
		wtype -k Return # Submit answers
	elif [ "$(jq '.tool_input.questions[0].multiSelect == true' <<<"$in")" = true ]; then
		# one pick-several question: if a review screen opened, it's on Submit
		sleep 1.2
		settled || wtype -k Return
	fi
	;;

Stop)
	[ "$(get .stop_hook_active)" = true ] && exit 0 # a hook made Claude continue: not the end yet
	if [ "${1:-}" != --worker ]; then
		CLAUDE_TOAST_PID=$PPID setsid -f "$0" --worker <<<"$in" >/dev/null 2>&1
		exit 0
	fi
	focused && { log "terminal focused, skipping"; exit 0; }
	# the start of Claude's last reply
	msg=$(get .last_assistant_message)
	if [ -z "$msg" ] && [ -f "$(get .transcript_path)" ]; then
		sleep 0.3 # the transcript can trail the hook by a moment
		msg=$(tac "$(get .transcript_path)" | grep -m40 '"type":"assistant"' |
			jq -r '[.message.content[]? | select(.type == "text") | .text] | join(" ")' 2>/dev/null | grep -m1 .)
	fi
	msg=$(tr '\n' ' ' <<<"$msg" | sed -e 's/[*`#]//g' -e 's/  */ /g' | cut -c1-140)
	[ ${#msg} -ge 140 ] && msg="$msg…"
	touch "$marks/$(get .session_id).done"
	wait_turn 3 120 || exit 0
	log "showing finished"
	# clicking the toast takes you to this session's terminal
	{ glint success "Claude finished" -d "$(body "$(esc <<<"${msg:-Your turn.}")")" -i "✻" -p top-right -t 8s -w >/dev/null 2>&1 && go_terminal; } & # waits for a click without holding the queue
	sleep 0.2 # the toast is up before the next one queues
	done_turn 600
	;;

Notification)
	if [ "${1:-}" != --worker ]; then
		# queue in the background so Claude isn't held up; the worker re-checks focus
		CLAUDE_TOAST_PID=$PPID setsid -f "$0" --worker <<<"$in" >/dev/null 2>&1
		exit 0
	fi
	type=$(get .notification_type)
	case "$type" in
	permission_prompt)
		# already asked through the Allow/Deny toast in the last 2 minutes
		[ -n "$(find "$mark" -mmin -2 2>/dev/null)" ] && exit 0
		kind=warning title="Needs permission" ;;
	idle_prompt)
		# the "finished" toast already said so for this turn
		[ -n "$(find "$marks/$(get .session_id).done" -mmin -10 2>/dev/null)" ] && exit 0
		kind=info title="Claude is waiting" ;;
	elicitation_dialog | agent_needs_input) kind=info title="Claude has a question" ;;
	auth_success) kind=success title="Signed in" ;;
	quota_auto_resume_fired) kind=success title="Resumed" ;;
	quota_auto_resume_*) kind=warning title="Usage limit" ;;
	*) kind=info title=$(get .title); title=${title:-Claude Code} ;;
	esac
	focused && { log "terminal focused, skipping"; exit 0; }
	wait_turn 3 120 || exit 0
	log "showing notification"
	{ glint "$kind" "$title" -d "$(body "$(get .message | esc)")" -i "✻" -p top-right -t 8s -w >/dev/null 2>&1 && go_terminal; } & # waits for a click without holding the queue
	sleep 0.2 # the toast is up before the next one queues
	done_turn 600 # bead stacks notifications; just keep them in order
	;;
esac
exit 0
