module tilebag;

import std.conv;
import std.exception;

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

	ByteString [] contents;
	
	void fill_rack ()
	{
		while ((contents.length > 0) && (rack.total < Rack.MAX_SIZE))
		{
			rack.add (contents[0]);
			contents = contents[1..$];
		}
	}

	bool empty () @property const
	{
		return (contents.length == 0) && rack.empty;
	}

	this (const string data)
	{
		byte [] temp;
		foreach (c; data)
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
		contents = temp.idup;

		fill_rack ();
	}
	
	string toString () const
	{
		string res = rack.toString () ~ "\nFuture tiles: ";
		foreach (c; contents)
		{
			res ~= (c == LET) ? '?' : (c + 'A');
		}
		return res;
	}
}
