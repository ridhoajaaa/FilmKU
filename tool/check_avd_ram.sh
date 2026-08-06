#!/usr/bin/env bash
echo '=== AVD config.ini ==='
cat ~/.android/avd/filmku.avd/config.ini 2>/dev/null | grep -iE 'ram|skin|density|hw.lcd|image|heap' || cat /root/.android/avd/filmku.avd/config.ini 2>/dev/null | grep -iE 'ram|skin|dpi|heap' || echo 'NO CONFIG FOUND'
echo
echo '=== free memory now ==='
free -m | head -2
echo
echo '=== big consumers ==='
ps aux --sort=-rss | head -8 | awk '{printf "%s %s %sMB %s\n", $1, $2, int($6/1024), $11}'
echo
echo '=== gradle / dart daemons running? ==='
pgrep -af 'GradleDaemon|dart.*flutter_tools' | head -5 || echo 'none'
