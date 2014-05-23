module trie;

import core.bitop;
import std.algorithm;
import std.conv;
import std.exception;
import std.stdio;

import board;
import general;

struct TrieNode
{
	int mask;
	int start;

	static assert (mask.sizeof * 8 >= LET + 1);

	bool word () @property const
	{
		return (mask & (1 << LET)) != 0;
	}

	bool word (const bool new_word) @property
	{
		mask = (mask & ~(1 << LET)) | (new_word << LET);
		return new_word;
	}

	int next (const int ch) const
	{
		int ch_bit = 1 << ch;
		if (!(mask & ch_bit))
		{
			return NA;
		}
		return start + popcnt (mask & (ch_bit - 1));
	}
}

class Trie
{
	immutable static int NA = -1;
	immutable static int ROOT = 0;
	immutable static char BASE = 'a';

	TrieNode [] contents;
	
	deprecated int next (const int pos, const int ch) const
	{
		return contents[pos].next (ch);
	}

	this (const char [] [] word_list, const int size_hint = 1)
	{
		int nw = to !(int) (word_list.length);
		enforce (isSorted (word_list));
		contents = [TrieNode ()];
		contents.reserve (size_hint);
		auto vp = new int [nw];
		vp[] = ROOT;
		int old_size = 0;
		int total_length = 0;

		foreach (pos; 0..Board.SIZE)
		{
			foreach (i, w; word_list)
			{
				if (pos < w.length)
				{
					int ch = w[pos] - BASE;
					contents[vp[i]].mask |= 1 << ch;
				}
			}

			int new_size = contents.length;
			foreach (j; old_size..new_size)
			{
				contents[j].start = contents.length;
				contents.length += popcnt (contents[j].mask);
			}
			old_size = new_size;

			foreach (i, w; word_list)
			{
				if (pos < w.length)
				{
					int ch = w[pos] - BASE;
					vp[i] = contents[vp[i]].next (ch);
					assert (vp[i] != NA);
					if (pos + 1 == w.length)
					{
						contents[vp[i]].word = true;
						total_length += w.length;
					}
	                	}
			}
		}
		debug {writeln ("Trie: loaded ", nw, " words of total length ",
		    total_length, ", created ", contents.length, " nodes");}
	}
}
