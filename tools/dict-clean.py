import sys
t = '??AAAAAAAAABBCCDDDDEEEEEEEEEEEEFFGGGHHIIIIIIIIIJKLLLLMMNNNNNNOOOOOOOOPPQRRRRRRSSSSTTTTTTUUUUVVWWXYYZ'
t = t.lower ()
d = {}
for c in t:
	if c not in d:
		d[c] = 1
	else:
		d[c] += 1
for s in sys.stdin.readlines ():
	p = s.strip ()
	e = d.copy ()
	ok = True
	for c in p:
		if e[c] > 0:
			e[c] -= 1
		elif e['?'] > 0:
			e['?'] -= 1
		else:
			ok = False
			break
	if ok:
		print (p)
