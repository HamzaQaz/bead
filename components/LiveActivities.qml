import QtQuick
import qs.services

// What's running right now, as chips: a recording (click stops), a Discord call
// (click mutes, right-click deafens) and a timer (click pauses, right-click
// stops). Hidden when nothing runs. On the dashboard and the lock screen.
Flow {
    id: root
    spacing: 6
    visible: Recorder.recording || Countdown.mode !== "" || Discord.inCall
    LiveChip {
        visible: Discord.inCall
        icon: Discord.deaf ? "headset_off" : Discord.mute ? "mic_off" : "headset_mic"
        tone: Discord.mute || Discord.deaf ? "error" : "action"
        pulse: Discord.speaking.length > 0
        text: (Discord.channel?.name ?? "") + " · " + Discord.members.length
        hint: "Click to mute, right-click to deafen"
        onClicked: Discord.toggleMute()
        onRightClicked: Discord.toggleDeaf()
    }
    LiveChip {
        visible: Recorder.recording
        icon: "radio_button_checked"
        tone: "error"
        pulse: true
        text: Recorder.label
        hint: "Click to stop"
        onClicked: Recorder.stop()
    }
    LiveChip {
        visible: Countdown.mode !== ""
        icon: Countdown.mode === "stopwatch" ? "timer" : "hourglass_top"
        tone: "action"
        dim: !Countdown.running
        progress: Countdown.mode === "timer" ? 1 - Countdown.progress : -1
        text: Countdown.label
        hint: "Click to pause, right-click to stop"
        onClicked: Countdown.toggle()
        onRightClicked: Countdown.stop()
    }
}
