module tilebag;

import std.conv;
import std.exception;
import std.stdio;

import general;

struct RackEntry
{
	immutable static ubyte NONE = 0xFF;

	ubyte contents = NONE;

	alias contents this;
	
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

	void add (const byte letter)
	{
		int i = 0;
		while (!contents[i].empty && (contents[i].letter < letter))
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
			contents[i] = cast (ubyte) (letter + (1 << LET_BITS));
		}
		total++;
	}

	void normalize ()
	{
		int i = 0;
		int j = 0;
		total = 0;
		while (i < MAX_SIZE && !contents[i].empty)
		{
			if (contents[i].num != 0)
			{
				total += contents[i].num;
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
		string res = "Rack:";
		foreach (c; contents)
		{
			if (c.empty)
			{
				break;
			}
			res ~= ' ';
			res ~= to !(string) (c.num);
			res ~= (c.letter == LET) ? '?' : (c.letter + 'A');
		}
		if (contents.length == 0)
		{
			res ~= " empty";
		}
		return res;
	}
}

struct TileBag
{
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
			counter[contents[cursor]]--;
			cursor++;
		}
	}

	bool empty () @property const
	{
		return (cursor >= contents.length) && rack.empty;
	}

	void update (const char [] data)
	{
		byte [] temp;
		foreach (c; data[contents.length..$])
		{
			byte v = void;
			if (c == '?')
			{
				v = LET;
			}
			else if ('A' <= c && c <= 'Z')
			{
				v = to !(byte) (c - 'A');
			}
			else
			{
				enforce (false);
			}
			counter[v]++;
			temp ~= v;
		}
		contents ~= temp.idup;

		fill_rack ();
	}

	this (const char [] data)
	{
		byte [] temp;
		foreach (c; data)
		{
			byte v = void;
			if (c == '?')
			{
				v = LET;
			}
			else if ('A' <= c && c <= 'Z')
			{
				v = to !(byte) (c - 'A');
			}
			else
			{
				enforce (false);
			}
			counter[v]++;
			temp ~= v;
		}
		contents = temp.idup;
		cursor = 0;

		fill_rack ();
	}

	string toString () const
	{
		string res = rack.toString () ~ "\nFuture tiles: ";
		foreach (c; contents[cursor..$])
		{
			res ~= (c == LET) ? '?' : (c + 'A');
		}
		return res;
	}
}

struct TileCounter
{
	byte [LET + 1] contents;

	alias contents this;

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

	bool opBinary (string op) (ref const TileCounter other) const
	    if (op == "<<")
	{
		writeln ("lo " ~ contents);
		writeln ("hi " ~ other.contents);
		foreach (i; 0..LET + 1)
		{
			if (contents[i] > other.contents[i])
			{
				return false;
			}
		}
		return true;
	}
}
