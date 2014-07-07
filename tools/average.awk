#!/usr/bin/gawk
// {s += $3;}
END {print s, s / FNR;}
