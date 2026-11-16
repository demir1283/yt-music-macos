#!/bin/bash
# YT Music'in işlemci ve bellek kullanımını ölçer, 10 saniyelik bir örnek alır (profile.txt).
#   ./profile.sh            boştayken: çalıştır, 20 saniye fareye ve klavyeye dokunma
#   ./profile.sh --kullanim kullanırken: çalıştır, 20 saniye uygulamayı normal kullan
#                           (sayfa aç, kaydır, şarkı değiştir)
cd "$(dirname "$0")"
PID="$(pgrep -x Encore | head -1)"
if [ -z "$PID" ]; then echo "YT Music çalışmıyor." >&2; exit 1; fi
if [ "${1:-}" = "--kullanim" ]; then
  echo "▸ 20 saniye boyunca YT Music'i normal kullan (kaydır, sayfa aç)…"
  MODE="kullanırken"
else
  echo "▸ 20 saniye boyunca bilgisayara dokunma…"
  MODE="boştayken"
fi
{
  echo "=== ölçüm: $MODE (örnekleyici yokken, 1 sn aralıkla) ==="
  top -l 9 -s 1 -pid "$PID" -stats pid,cpu,mem,threads,idlew,power | awk '/^[0-9]/{print}' | tail -8
  echo "=== ön plandaki uygulama ==="
  lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null | head -1
  echo
} > profile.txt
sample "$PID" 10 5 -file profile.sample.txt >/dev/null 2>&1
{
  echo "=== bellek dağılımı ==="
  footprint "$PID" 2>/dev/null | head -40
  echo "=== en çok yer kaplayan nesneler ==="
  heap -sortBySize "$PID" 2>/dev/null | sed -n '/COUNT/,$p' | head -45
  echo
} >> profile.txt
cat profile.sample.txt >> profile.txt && rm -f profile.sample.txt
echo "✓ Hazır: $(pwd)/profile.txt"
