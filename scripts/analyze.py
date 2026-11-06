import json,glob,sys,collections
rows=[]
for f in sorted(glob.glob(sys.argv[1])):
    for l in open(f):
        try:j=json.loads(l)
        except: continue
        if 'fatal' in j: print('FATAL',f,j)
        if 'gapMs' in j: rows.append(j)
stall=lambda r:r['progressMs'] is None or r['progressMs']>800
arms=sorted({r['arm'] for r in rows})
for a in arms:
    A=[r for r in rows if r['arm']==a]; P=sorted(r['progressMs'] for r in A if r['progressMs'] is not None)
    print(f"{a}: n={len(A)} stalls={sum(map(stall,A))} never={sum(r['progressMs'] is None for r in A)} p50={P[len(P)//2]:.0f} max={P[-1]:.0f}" if P else f"{a}: n={len(A)} no progress at all")
    for s in ('pause','finish'):
        g=collections.defaultdict(lambda:[0,0])
        for r in A:
            if r['scenario']==s: g[r['gapMs']][0]+=stall(r); g[r['gapMs']][1]+=1
        print('  ',s,' '.join(f"{k}:{v[0]}/{v[1]}" for k,v in sorted(g.items())))
