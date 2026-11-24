#!/usr/bin/env python3
# Makes modules/welcome/script.js, the welcome title's pen path:
#   python3 tools/handwriting.py js modules/welcome/script.js
# With no arguments it writes hello.svg (the path, its points in red) for tuning.
import math, sys, json
# "bead." in one connected pen line; x-height 1, ascenders 2, baseline 0, y up
# Drawn upright: every downstroke is vertical (b's stem, the bowls' right
# sides, a's and d's stems) and SLANT then leans the whole word by one angle,
# so all the strokes run the same way; loops lean only by their upstrokes.
P = [
 # b: lead-in from the baseline up into a tall loop, straight down the stem
 (-0.20,0.05),(0.10,0.30),(0.38,0.90),(0.50,1.50),(0.48,1.90),(0.36,2.06),(0.24,1.95),(0.20,1.50),(0.20,0.80),(0.20,0.15),
 # …its bowl round to a little tie at the top right
 (0.30,0.03),(0.60,0.00),(0.88,0.18),(0.97,0.52),(0.87,0.86),(0.62,0.92),(0.50,0.78),(0.70,0.66),(1.05,0.62),
 # e: up into its loop, round, and out along the bottom
 (1.4,0.62),(1.7,0.78),(1.82,0.96),(1.68,1.06),(1.45,0.96),(1.3,0.62),(1.32,0.25),(1.55,0.02),(1.85,0.02),(2.1,0.2),
 # a and d: the connector rises up the bowl's left side and over its top, the
 # pen turns back along exactly that line and goes round; then the stem
 (2.18,0.45),(2.26,0.80),(2.46,0.99),(2.73,0.98),(2.88,0.90),(2.73,0.98),(2.46,0.99),(2.26,0.80),(2.18,0.45),(2.24,0.12),(2.46,0.00),(2.73,0.10),(2.86,0.45),(2.90,0.98),(2.90,0.55),(2.91,0.15),(3.08,0.00),(3.30,0.12),(3.33,0.45),(3.41,0.80),(3.61,0.99),(3.88,0.98),(4.03,0.90),(3.88,0.98),(3.61,0.99),(3.41,0.80),(3.33,0.45),(3.39,0.12),(3.61,0.00),(3.88,0.10),(4.01,0.45),(4.07,1.40),(4.12,1.95),(4.06,2.08),(4.01,1.90),(4.01,1.30),(4.01,0.55),(4.03,0.12),(4.21,0.00),(4.46,0.15),
]
DOT = (4.98, 0.09)
SLANT = 0.14
def cr(pts, n=24, alpha=0.5):
    out=[]; P=[(2*pts[0][0]-pts[1][0],2*pts[0][1]-pts[1][1])]+pts+[(2*pts[-1][0]-pts[-2][0],2*pts[-1][1]-pts[-2][1])]
    for i in range(1,len(P)-2):
        p0,p1,p2,p3=P[i-1],P[i],P[i+1],P[i+2]
        t0=0; t1=t0+math.dist(p0,p1)**alpha; t2=t1+math.dist(p1,p2)**alpha; t3=t2+math.dist(p2,p3)**alpha
        for k in range(n):
            t=t1+(t2-t1)*k/n
            def L(a,b,ta,tb): return tuple(((tb-t)*a[j]+(t-ta)*b[j])/(tb-ta) for j in range(2))
            A1=L(p0,p1,t0,t1);A2=L(p1,p2,t1,t2);A3=L(p2,p3,t2,t3)
            B1=L(A1,A2,t0,t2);B2=L(A2,A3,t1,t3)
            out.append(L(B1,B2,t1,t2))
    out.append(pts[-1]); return out
def resample(pts,step):
    o=[pts[0]]; acc=0
    for i in range(1,len(pts)):
        a,b=pts[i-1],pts[i]; L=math.dist(a,b)
        while acc+L>=step and L>0:
            t=(step-acc)/L; a=(a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t); o.append(a); L=math.dist(a,b); acc=0
        acc+=L
    o.append(pts[-1]); return o
def smooth(pts, win=7, passes=2):
    for _ in range(passes):
        q=list(pts); h=win//2
        for i in range(h,len(pts)-h):
            q[i]=(sum(p[0] for p in pts[i-h:i+h+1])/win, sum(p[1] for p in pts[i-h:i+h+1])/win)
        pts=q
    return pts
line=[(x+y*SLANT,y) for x,y in smooth(resample(cr(P),0.01))]
dot=(DOT[0]+DOT[1]*SLANT,DOT[1])
xs=[p[0] for p in line]+[dot[0]+0.1]; ys=[p[1] for p in line]
x0,y1=min(xs),max(ys); H=y1-min(ys+[0])
norm=lambda p: ((p[0]-x0)/H,(y1-p[1])/H)
line=resample([norm(p) for p in line],0.008); dot=norm(dot); W=(max(xs)-x0)/H
if len(sys.argv)>1 and sys.argv[1]=='js':
    f=lambda v: ('%.4f'%v).rstrip('0').rstrip('.')
    L=sum(math.dist(line[i-1],line[i]) for i in range(1,len(line)))
    open(sys.argv[2],'w').write('''.pragma library
// "bead." as handwriting, in one connected pen line: points spaced evenly
// along it (so the pen moves at an even pace), x then y, in units of the
// word's height (y down). Made by tools/handwriting.py (a centripetal
// Catmull-Rom spline through hand-placed points). The full stop is a bead instead: `dot`.
var aspect = %s;
var lengths = [%s];
var dot = [%s, %s];
var strokes = [
    [%s]
];
'''%(f(W),f(L),f(dot[0]),f(dot[1]),', '.join(f(c) for p in line for c in p)))
    print('js',len(line),W,L); sys.exit()
S=300; pad=40; w=0.062
svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{W*S+2*pad:.0f}" height="{S+2*pad}"><rect width="100%" height="100%" fill="#26242e"/>'
svg+='<polyline fill="none" stroke="#ece8ff" stroke-width="%.1f" stroke-linecap="round" stroke-linejoin="round" points="%s"/>'%(w*S,' '.join(f'{p[0]*S+pad:.1f},{p[1]*S+pad:.1f}' for p in line))
svg+=f'<circle cx="{dot[0]*S+pad}" cy="{dot[1]*S+pad-0.03*S}" r="{0.075*S}" fill="#ece8ff"/>'
# control points, for tuning
for x,y in P: q=norm((x+y*SLANT,y)); svg+=f'<circle cx="{q[0]*S+pad}" cy="{q[1]*S+pad}" r="3" fill="#f55"/>'
open('hello.svg','w').write(svg+'</svg>'); print(W)
