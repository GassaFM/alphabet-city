import core.bitop;
import core.memory;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.stdio;
import std.string;

struct Board
{
	immutable static int SIZE = 15;

	char [SIZE] [SIZE] contents;
	int score;
}

struct TrieNode
{
	immutable static int LET = 26;

	int start;
	int mask;

	bool word () @property
	{
		return (mask & (1 << LET)) != 0;
	}

	bool word (bool new_word) @property
	{
		mask = (mask & ~(1 << LET)) | new_word;
		return new_word;
	}
}

class Trie
{
	immutable static int NA = -1;
	immutable static int ROOT = 0;
	immutable static char BASE = 'a';

	TrieNode [] contents;

	int next (int pos, int ch)
	{
		int cur_mask = contents[pos].mask;
		if (!(cur_mask & (1 << ch)))
		{
			return NA;
		}
		return contents[pos].start +
		       popcnt (cur_mask & ((1 << ch) - 1));
	}

	this (const char [] [] word_list, int size_hint = 1)
	{
		int nw = to !(int) (word_list.length);
		enforce (isSorted (word_list));
		contents = [TrieNode ()];
		contents.reserve (size_hint);
		auto vp = new int [nw];
		vp[] = ROOT;

		foreach (pos; 0..Board.SIZE)
		{
			foreach (i, w; word_list)
			{
				if (pos < w.length)
				{
					contents[vp[i]].mask |=
					    1 << (w[pos] - BASE);
				}
			}

			foreach (i, w; word_list)
			{
				if (pos < w.length)
				{
					contents[vp[i]].start =
					    contents.length;
					contents.length +=
					    popcnt (contents[vp[i]].mask);
				}
			}

			foreach (i, w; word_list)
			{
				if (pos < w.length)
				{
					vp[i] = next (vp[i], w[pos] - BASE);
					assert (vp[i] != NA);
					if (pos + 1 == w.length)
					{
						contents[vp[i]].word = true;
					}
	                	}
			}
		}
	}
}

string [] read_words (string file_name)
{
	string [] res;
	auto fin = File (file_name, "rt");
	foreach (w; fin.byLine ())
	{
		res ~= to !(string) (w);
	}
	return res;
}

void main ()
{
	auto t = new Trie (read_words ("data/words.txt"), 13_734_265);
	GC.collect ();
}
