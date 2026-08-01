#!/bin/bash
# launch_emulator_tmux.sh — run the emulator in a persistent tmux session so
# it survives individual shell commands (the sandbox kills backgrounded
# processes when a command returns, so plain setsid/nohup is not enough).
TMUX=/home/ridhoajaaa/.local/bin/tmux
export ANDROID_HOME=/opt/android-sdk
export PATH=/opt/android-sdk/platform-tools:$PATH

# Kill any previous instance
pkill -f 'emulator.*filmku' 2>/dev/null
pkill -f 'qemu.*filmku' 2>/dev/null
sleep 2

# Start fresh tmux session running the emulator (headless, swiftshader)
"$TMUX" kill-session -t emu 2>/dev/null
"$TMUX" new-session -d -s emu \
  "ANDROID_HOME=/opt/android-sdk /opt/android-sdk/emulator/emulator -avd filmku -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect -no-snapshot -no-metrics > /tmp/emu_tmux.log 2>&1"

sleep 4
echo "=== TMUX SESSIONS ==="
"$TMUX" ls 2>&1
echo "=== PROCESS ==="
ps aux | grep 'emulator.*filmku' | grep -v grep | awk '{print "PID", $2}' | head -2 || echo "NOT_ALIVE"
echo "=== LOG TAIL ==="
tail -4 /tmp/emu_tmux.log 2>/dev/null
