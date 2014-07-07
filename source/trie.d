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
	immutable static int IS_WORD = LET;
	immutable static int IS_GROW = LET + 1;

	int mask;
	int start;

	static assert (mask.sizeof * 8 >= LET + 2);

	bool word () @property const
	{
		return (mask & (1 << IS_WORD)) != 0;
	}

	bool word (const bool new_word) @property
	{
		mask = (mask & ~(1 << IS_WORD)) | (new_word << IS_WORD);
		return new_word;
	}

	bool grow () @property const
	{
		return (mask & (1 << IS_GROW)) != 0;
	}

	bool grow (const bool new_grow) @property
	{
		mask = (mask & ~(1 << IS_GROW)) | (new_grow << IS_GROW);
		return new_grow;
	}

	int next () (const int ch) const
	{
		int ch_bit = 1 << ch;
		if (!(mask & ch_bit))
		{
			return NA;
		}
		return start + popcnt (mask & (ch_bit - 1));
	}
}

final class Trie
{
	immutable static int ROOT = 0;
	immutable static char BASE = 'a';

	TrieNode [] contents;

	deprecated final int next (const int pos, const int ch) const
	{
		return contents[pos].next (ch);
	}

	void traverse (int v, void delegate (int) fun)
	{
		fun (v);
		int num = popcnt (contents[v].mask & ((1 << LET) - 1));
		foreach (i; 0..num)
		{
			traverse (contents[v].start + i, fun);
		}
	}

	this (const char [] [] word_list, // bool calc_grow,
	    const int size_hint = 1)
	{
		stdout.flush ();
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

			int new_size = to !(int) (contents.length);
			foreach (j; old_size..new_size)
			{
				contents[j].start =
				    to !(int) (contents.length);
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

struct TrieNodeCompact
{
	ushort mask_id;
	ushort start;
}

final class TrieCompact
{
	immutable static int IS_WORD = LET;
	immutable static ushort NONE = 0xFFFFu;
	immutable static int ROOT = 0;
	immutable static char BASE = 'a';

	TrieNodeCompact [] contents;
	int [] mask_pool;

	final ushort next (const ushort pos, const int ch) const
	{
		int mask = mask_pool[contents[pos].mask_id];
		int ch_bit = 1 << ch;
		if (!(mask & ch_bit))
		{
			return NONE;
		}
		return cast (ushort) (contents[pos].start +
		    cast (ushort) (popcnt (mask & (ch_bit - 1))));
	}
	
	final bool is_word (const ushort pos) const
	{
		int mask = mask_pool[contents[pos].mask_id];
		return (mask & IS_WORD) != 0;
	}

	this (const Trie prev_trie)
	{
		bool [int] masks;
		foreach (v; prev_trie.contents)
		{
			masks[v.mask] = true;
		}
		debug {writeln ("TrieCompact: found ", masks.length,
		    " different masks");}

		immutable uint PRIME = 262_139;
		int [ulong] hashes;
		auto hash = new ulong[prev_trie.contents.length];
		foreach_reverse (i, w; prev_trie.contents)
		{
			ulong h = w.mask;
			int num = popcnt (w.mask & ((1 << LET) - 1));
			foreach (pos; 0..num)
			{
				h = h * PRIME + hash[w.start + pos];
			}
			hash[i] = h;
			hashes[h] = to !(int) (i);
		}
		debug {writeln ("TrieCompact: found ", hashes.length,
		    " different hashes");}

		contents = [];
		contents.reserve (hashes.length);
		foreach (i, w; prev_trie.contents)
		{
			if (hashes[hash[i]] == i)
			{
			}
		}
	}
}
