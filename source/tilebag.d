module tilebag;

import std.array;
import std.conv;
import std.exception;
import std.format;
import std.stdio;

import board;
import general;
import problem;

struct RackEntry
{
	immutable static ubyte NONE = 0xFF;

	ubyte contents = NONE;

	alias contents this;

	bool is_wildcard () @property const
	{
		return letter == LET;
	}

	ubyte letter () @property const
	{
		return contents & LET_MASK;
	}

	ubyte letter (const ubyte new_letter) @property
	{
		contents = (contents & ~LET_MASK) | new_letter;
		return new_letter;
	}

	ubyte num () @property const
	{
		return contents >> LET_BITS;
	}

	ubyte num (const ubyte new_num) @property
	{
		contents = to !(ubyte) ((contents & LET_MASK) |
		    (new_num << LET_BITS));
		return new_num;
	}

	bool empty () @property const
	{
		return contents == NONE;
	}

	void inc ()
	{
		contents += (1 << LET_BITS);
	}

	void dec ()
	{
		contents -= (1 << LET_BITS);
	}
}

struct Rack
{
	immutable static int MAX_SIZE = 7;

	RackEntry [MAX_SIZE] contents;
	byte total;
	alias usable_total = total;

	void add (const byte letter)
	{
		if (!(letter & TileBag.IS_RESTRICTED))
		{
			int i = 0;
			while (!contents[i].empty &&
			    (contents[i].letter < letter))
			{
				i++;
			}
			if (contents[i].letter == letter)
			{
				contents[i].inc ();
			}
			else
			{
				foreach_reverse (j; i..MAX_SIZE - 1)
				{
					contents[j + 1] = contents[j];
				}
				contents[i] = cast (ubyte) (letter +
				    (1 << LET_BITS));
			}
		}
		total++;
	}

	void normalize ()
	{
		int i = 0;
		int j = 0;
		while (i < MAX_SIZE && !contents[i].empty)
		{
			if (contents[i].num != 0)
			{
				contents[j] = contents[i];
				j++;
			}
			i++;
		}
		while (j < i)
		{
			contents[j] = RackEntry.NONE;
			j++;
		}
	}

	bool empty () @property const
	{
		return total == 0;
	}

	string toString () const
	{
		string res = "Rack: (" ~ to !(string) (total) ~ ")";
		int k = 0;
		foreach (c; contents)
		{
			if (c.empty)
			{
				break;
			}
			k++;
			res ~= ' ';
			res ~= to !(string) (c.num);
			res ~= (c.letter == LET) ? '?' : (c.letter + 'A');
		}
		if (k == 0)
		{
			res ~= " empty";
		}
		return res;
	}
}

struct TileBag
{
	immutable static int RESTRICTED_BIT = LET_BITS;
	immutable static byte IS_RESTRICTED = 1 << RESTRICTED_BIT;

	Rack rack;
	ByteString contents;
	TileCounter counter;
	int cursor;

	alias contents this;

	void fill_rack ()
	{
		while ((cursor < contents.length) &&
		    (rack.total < Rack.MAX_SIZE))
		{
			rack.add (contents[cursor]);
			cursor++;
		}
	}

	void dec (ref RackEntry c)
	{
		c.dec ();
		rack.total--;
		counter[c.letter]--;
	}

	void inc (ref RackEntry c)
	{
		c.inc ();
		rack.total++;
		counter[c.letter]++;
	}

	void dec_restricted (const ref BoardCell t)
	{
		rack.total--;
		counter[t.letter]--;
	}

	void inc_restricted (const ref BoardCell t)
	{
		rack.total++;
		counter[t.letter]++;
	}

	bool empty () @property const
	{
		return (cursor >= contents.length) && rack.empty;
	}

	static byte char_to_byte (const char c)
	{
		if (c == '?')
		{
			return LET;
		}
		if ('A' <= c && c <= 'Z' + 1)
		{
			return to !(byte) (c - 'A');
		}
		if ('a' <= c && c <= 'z' + 1)
		{
			return to !(byte) (c - 'a') | IS_RESTRICTED;
		}
		assert (false);
	}

	void update (const char [] data, bool was_virtual = false)
	{
		byte [] temp;
		foreach (c; data[contents.length..$])
		{
			byte v = char_to_byte (c);
			if (!was_virtual)
			{
				counter[v & LET_MASK]++;
			}
			temp ~= v;
		}
		contents ~= temp.idup;

		fill_rack ();
	}

	this (const char [] data, const char [] virtual = "")
	{
		byte [] temp;
		foreach (i, c; data ~ virtual)
		{
			byte v = char_to_byte (c);
			counter[v & LET_MASK]++;
			if (i < data.length)
			{
				temp ~= v;
			}
		}
		contents = temp.idup;
		cursor = 0;

		fill_rack ();
	}

	this (Problem problem)
	{
		this (problem.contents, problem.virtual);
	}

	string toString () const
	{
		string res = rack.toString () ~ "\nFuture tiles: ";
		foreach (c; contents[cursor..$])
		{
			res ~= (c == LET) ? '?' : (c + 'A');
		}
		res ~= "\n" ~ to !(string) (counter);
		return res;
	}
}

struct TileCounter
{
	byte [LET + 1] contents;

	alias contents this;

/*
	this (const char [] data)
	{
		foreach (c; data)
		{
			if (c == '?')
			{
				contents[LET]++;
			}
			else if ('A' <= c && c <= 'Z')
			{
				contents[c - 'A']++;
			}
			else if ('a' <= c && c <= 'z')
			{
				contents[c - 'a']++;
			}
			else
			{
				enforce (false);
			}
		}
	}
*/

	bool opBinary (string op) (ref const TileCounter other) const
	    if (op == "<<")
	{
		foreach (i; 0..LET + 1)
		{
			if (contents[i] > other.contents[i])
			{
				return false;
			}
		}
		return true;
	}

/*
	bool opBinary (string op) (ref const TileCounter other) const
	    if (op == "<<<")
	{
		int extra = contents[LET] - other.contents[LET];
		foreach (i; 0..LET)
		{
			int diff = contents[i] - other.contents[i];
			if (diff > 0)
			{
				extra -= diff;
				if (extra < 0)
				{
					return false;
				}
			}
		}
		return true;
	}
*/

	string toString () const
	{
		auto sink = appender !(string) ();
		formattedWrite (sink, "Counter: ");
		foreach (c; contents)
		{
			formattedWrite (sink, "%X", c);
		}
		return sink.data;
	}
}
