#!/bin/bash
gawk "{print \$1;}" all-raw.txt >all.txt
for (( d = 0 ; d < 2 ; d ++ )) ; do
	gawk "{if (\$4 == $d) print;}" all-raw.txt >t-$d.txt
	for (( k = 2 + $d ; k <= 7 ; k ++ )) ; do
		gawk "{if (\$3 == $k) print;}" t-$d.txt >t-$d-$k.txt
	done
done
for f in t*.txt ; do
	sort -k 2 -n -r $f >s${f#t*}
done
gawk "{print tolower (\$0);}" all.txt | sort | uniq >long-words.txt
