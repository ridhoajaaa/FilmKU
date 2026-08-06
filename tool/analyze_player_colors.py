#!/usr/bin/env python3
"""Color sampling of the player screenshot regions."""
import sys
from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else '/tmp/phone_player.png'
img = Image.open(path).convert('RGB')
W, H = img.size
print(f'{W}x{H}')

def sample(box, label):
    region = img.crop(box)
    px = list(region.getdata())
    n = len(px)
    avg = tuple(sum(p[i] for p in px) // n for i in range(3))
    # saturation = max-min of avg
    sat = max(avg) - min(avg)
    # variance
    var = sum((p[i] - avg[i]) ** 2 for p in px for i in range(3)) / (n * 3)
    print(f'{label:28s} box={box} avg_rgb={avg} sat={sat:3d} var={var:8.1f}')

# left strip (suspected video)
sample((0, int(H*0.12), int(W*0.25), int(H*0.62)), 'left-strip')
# its center
sample((int(W*0.06), int(H*0.25), int(W*0.18), int(H*0.50)), 'left-strip center')
# middle-right controls cluster
sample((int(W*0.65), int(H*0.42), W, int(H*0.62)), 'controls cluster')
# each round button in the cluster (approx positions)
# from earlier: circles at x~2078-2135, y~540-574
sample((2050, 510, 2180, 600), 'round button A')
sample((2170, 510, 2300, 600), 'round button B')
# top bar
sample((0, 0, W, int(H*0.12)), 'top bar')
# bottom band
sample((0, int(H*0.85), W, H), 'bottom band')
# what is at middle-left (between video and controls)?
sample((int(W*0.25), int(H*0.30), int(W*0.60), int(H*0.60)), 'middle area x25-60%')
