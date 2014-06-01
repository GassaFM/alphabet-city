#!/bin/bash
pushd ..
rm -f to-submit.txt
for f in data/best/[a-z].txt ; do
	if [ -f to-submit.txt ] ; then
		echo ";" >> to-submit.txt
	fi
	head -n 1 $f | gawk '{print $1}' >> to-submit.txt
	tail -n +2 $f >> to-submit.txt
done
popd
