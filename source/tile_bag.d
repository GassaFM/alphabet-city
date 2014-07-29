module tile_bag;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;
import std.range;
import std.stdio;

import board;
import general;
import problem;
import scoring;

struct RackEntry
{
	immutable static ubyte NONE = 0xFF;

	static assert (LET + (Rack.MAX_SIZE << LET_BITS) < NONE);

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

	string toString () const
	{
		string res;
		res ~= to !(string) (num);
		res ~= (letter == LET) ? '?' : (letter + 'A');
		return res;
	}
}

struct Rack
{
	immutable static byte MAX_SIZE = 7;
	immutable static byte IGNORED = -0x3F;

	static assert (cast (typeof (total)) (IGNORED - MAX_SIZE) < 0);
	static assert (cast (typeof (total)) (IGNORED + MAX_SIZE) < 0);

	RackEntry [MAX_SIZE] contents;
	byte total;
	byte active;
	alias usable_total = total;

	void add (const byte letter, bool is_active)
	{
		if (is_active)
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
				contents[i] = cast (ubyte)
				    (letter | (1 << LET_BITS));
			}
			active++;
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
			res ~= ' ' ~ to !(string) (c);
		}
		if (k == 0)
		{
			res ~= " empty";
		}
		return res;
	}
}

struct Coord
{
	byte row = NA;
	byte col = NA;
}

final class TargetBoard
{
	byte [Board.SIZE] [Board.SIZE] tile_number = NA.to !(byte) ()
	    .repeat (Board.SIZE).array ()
	    .repeat (Board.SIZE).array ();
	Coord [] coord;

//	alias tile_number this;

	static assert (TOTAL_TILES < tile_number[0][0].max);

	void place (byte val, byte row, byte col, bool is_flipped)
	{
		if (is_flipped)
		{
			swap (row, col);
		}
		assert (tile_number[row][col] == NA);
		tile_number[row][col] = val;
		if (val >= 0)
		{
			assert (0 <= val && val < coord.length);
			coord[val] = Coord (row, col);
		}
	}

	this (T1) (T1 tiles_length)
	{
		coord = new Coord [tiles_length];
	}

	string [] to_strings (const char [] letters) const
	{
		string [] res;
		foreach (line; tile_number)
		{
			auto sink = appender !(string) ();
			foreach (cell; line)
			{
				if (cell == NA)
				{
					formattedWrite (sink, "  %02d.",
					    NA);
				}
				else if (cell < NA)
				{
					formattedWrite (sink, " *%02d%s",
					    cell - byte.min,
					    cast (char) ('A' - 'a' +
					    letters[cell - byte.min]));
				}
				else
				{
					formattedWrite (sink, "  %02d%s",
					    cell, letters[cell]);
				}
			}
			res ~= sink.data;
		}
		return res;
	}

	string [] to_strings () const
	{
		string [] res;
		foreach (line; tile_number)
		{
			auto sink = appender !(string) ();
			foreach (cell; line)
			{
				if (cell < NA)
				{
					formattedWrite (sink, " x%02d",
					    cell - byte.min);
				}
				else
				{
					formattedWrite (sink, "  %02d", cell);
				}
			}
			res ~= sink.data;
		}
		return res;
	}

	override string toString () const
	{
		auto sink = appender !(string) ();
		formattedWrite (sink, "Target board:\n");
		foreach (line; to_strings ())
		{
			formattedWrite (sink, "%s\n", line);
		}
		return sink.data;
	}
}

struct TileBag
{
	immutable static int RESTRICTED_BIT = LET_BITS;
	immutable static byte IS_RESTRICTED = 1 << RESTRICTED_BIT;
	immutable static int MIN_NEXT = 16;

	Rack rack;
	ByteString contents;
	TileCounter counter;
	TargetBoard target_board;
	int cursor;

	alias contents this;

	void fill_rack (const ref Board board)
	{
		if (rack.total >= 0)
		{
			while ((cursor < contents.length) &&
			    (rack.total < Rack.MAX_SIZE))
			{
				auto letter = contents[cursor];
				bool is_active = !(letter & IS_RESTRICTED);
				if (!is_active && target_board !is null &&
				    target_board.coord[cursor] != Coord.init)
				{
					if (!board.is_flipped)
					{
						if (!board[target_board
						    .coord[cursor].row]
						    [target_board
						    .coord[cursor].col].empty)
						{
							is_active = true;
						}
					}
					else
					{
						if (!board[target_board
						    .coord[cursor].col]
						    [target_board
						    .coord[cursor].row].empty)
						{
							is_active = true;
						}
					}
				}
				rack.add (letter, is_active);
				cursor++;
			}
		}
	}

	void fill_rack ()
	{ // no board to check for target tiles
		static immutable Board board;
		fill_rack (board);
	}

	void dec (ref RackEntry c)
	{
		assert (0 <= c.letter && c.letter <= LET);
		c.dec ();
		rack.total--;
		rack.active--;
		counter[c.letter]--;
	}

	void inc (ref RackEntry c)
	{
		assert (0 <= c.letter && c.letter <= LET);
		c.inc ();
		rack.total++;
		rack.active++;
		counter[c.letter]++;
	}

	void dec_restricted (const ref BoardCell t)
	{
		rack.total--;
		if (t.wildcard)
		{
			counter[LET]--;
		}
		else
		{
			counter[t.letter]--;
		}
	}

	void inc_restricted (const ref BoardCell t)
	{
		rack.total++;
		if (t.wildcard)
		{
			counter[LET]++;
		}
		else
		{
			counter[t.letter]++;
		}
	}

	bool empty () @property const
	{
		return (cursor >= contents.length) && rack.empty;
	}

	int get_next_mask (int limit)
	{
		limit = max (limit, cursor + MIN_NEXT);
		limit = min (limit, contents.length);

		int res = 0;
		foreach (ref c; rack.contents)
		{
			if (c.empty)
			{
				break;
			}

			if (c.num == 0)
			{
				continue;
			}

			if (c.is_wildcard)
			{
				res = (1 << LET) - 1;
				break;
			}

			res |= 1 << c.letter;
		}

		foreach (c; contents[cursor..limit])
		{
			if (c & IS_RESTRICTED)
			{
				continue;
			}

			if ((c & LET_MASK) == LET)
			{
				res = (1 << LET) - 1;
				break;
			}

			res |= 1 << (c & LET_MASK);
		}

		return res;
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

	void account (const char [] data)
	{
		foreach (c; data)
		{
			if (c == '?')
			{
				contents[LET]++;
			}
			else if ('A' <= c && c <= 'Z' + 1)
			{
				contents[c - 'A']++;
			}
			else if ('a' <= c && c <= 'z' + 1)
			{
				contents[c - 'a']++;
			}
			else
			{
				enforce (false);
			}
		}
	}

	this (const char [] data)
	{
		account (data);
	}

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

	bool opBinary (string op) (ref const TileCounter other) const
	    if (op == ">>>")
	{
		int extra = contents[LET] - other.contents[LET];
		if (extra < 0)
		{
			return false;
		}
		foreach (i; 0..LET)
		{
			int diff = other.contents[i] - contents[i];
			if (diff > 0)
			{
/*
				if (global_scoring.tile_value[i] > 1)
				{
					return false;
				}
*/
				extra -= diff;
				if (extra < 0)
				{
					return false;
				}
			}
		}
		return true;
	}

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
