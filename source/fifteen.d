module fifteen;

import std.algorithm;
import std.conv;
import std.exception;
import std.stdio;

import board;
import general;
import problem;
import scoring;
import trie;

struct LongWord
{
	immutable static int LENGTH = 15;

	immutable (byte) [] contents;
	int value = NA;
	int least = NA;
	Pair [] subwords;

	int [] possible (ref Problem problem, int wildcards)
	{
		byte [] temp;
		foreach (c; problem.contents)
		{
			if (c == '?')
			{
				temp ~= LET;
			}
			else
			{
				enforce ('A' <= c && c <= 'Z');
				temp ~= to !(byte) (c - 'A');
			}
		}

		int [] res;
main_loop:
		foreach (c; contents)
		{
			foreach (i, ref d; temp)
			{
				if (d == c)
				{
					d = LET + 1;
					res ~= i;
					continue main_loop;
				}
			}
			if (wildcards)
			{
				foreach (i, ref d; temp)
				{
					if (d == LET)
					{
						d = LET + 1;
						res ~= i;
						wildcards--;
						continue main_loop;
					}
				}
			}
			return new int [0];
		}
		sort (res);
		foreach (i, ref d; temp)
		{
			if (d == LET && wildcards)
			{
				res[$ - 1] = min (res[$ - 1], i);
				sort (res);
				wildcards--;
			}
		}
		return res;
	}

	void calculate_value (Scoring scoring)
	{
		value = 0;
		foreach (c; contents)
		{
			value += scoring.tile_value[c];
		}
	}

	void find_subwords (Trie trie)
	{
		subwords = new Pair [0];
		foreach (i; 0..LENGTH)
		{
			if (i == 0 || i == 6 || i == 7 || i == 13 || i == 14)
			{
				continue;
			}
			int j = i;
			int v = Trie.ROOT;
			while (j != 7 && j != 14)
			{
				v = trie.contents[v].next (contents[j]);
				if (v == NA)
				{
					break;
				}
				if (trie.contents[v].word)
				{
					subwords ~= Pair (i, j);
				}
				j++;
			}
		}
		int u = 0;
		int v = 0;
		foreach (p; subwords)
		{
			if (p.x < 7)
			{
				u = max (u, p.y - p.x + 1);
			}
			else if (p.x < 14)
			{
				v = max (v, p.y - p.x + 1);
			}
			else
			{
				assert (false);
			}
		}
		least = LENGTH - u - v;
	}

	this (string line, Scoring scoring, Trie trie)
	{
		enforce (line.length == LENGTH);
		byte [] temp;
		foreach (c; line)
		{
			enforce ('a' <= c && c <= 'z');
			temp ~= to !(byte) (c - 'a');
		}
		contents = temp.idup;

		calculate_value (scoring);

		find_subwords (trie);
	}

	string toString () const
	{
		string res;
		foreach (c; contents)
		{
			res ~= c + 'a';
		}
		res ~= ' ' ~ to !(string) (value);
		res ~= ' ' ~ to !(string) (least);
		res ~= ' ' ~ to !(string) (subwords);
		return res;
	}
}

class LongWordSet
{
	LongWord [] contents;

	this (const char [] [] line_list, Scoring scoring, Trie trie)
	{
		foreach (line; line_list)
		{
			if (line.length == LongWord.LENGTH)
			{
				contents ~= LongWord (to !(string) (line),
				    scoring, trie);
			}
		}
		debug {writeln ("LongWordSet: loaded ", contents.length,
		    " long words");}
	}
}
