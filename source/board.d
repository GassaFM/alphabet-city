module board;

import std.algorithm;
import std.conv;
import std.random;

import general;

struct BoardCell
{
	immutable static int WILDCARD_SHIFT = LET_BITS;
	immutable static int ACTIVE_SHIFT = LET_BITS + 1;
	immutable static byte NONE = LET;

	byte contents = NONE;

	alias contents this;

	static assert (ACTIVE_SHIFT < contents.sizeof * 8);

	byte letter () @property const
	{
		return contents & LET_MASK;
	}

	byte letter (const byte new_letter) @property
	{
		contents = (contents & ~LET_MASK) | new_letter;
		return new_letter;
	}

	bool wildcard () @property const
	{
		return (contents & (1 << WILDCARD_SHIFT)) != 0;
	}

	byte wildcard (const byte new_wildcard) @property
	{
		contents = to !(byte) ((contents & ~(1 << WILDCARD_SHIFT)) |
		    (new_wildcard << WILDCARD_SHIFT));
		return new_wildcard;
	}

	bool active () @property const
	{
		return (contents & (1 << ACTIVE_SHIFT)) != 0;
	}

	byte active (const byte new_active) @property
	{
		contents = to !(byte) ((contents & ~(1 << ACTIVE_SHIFT)) |
		    (new_active << ACTIVE_SHIFT));
		return new_active;
	}

	string toString () const
	{
		string res;
		if (empty)
		{
			res ~= '.';
		}
		else
		{
// BUG! fixed in GIT HEAD
//			res ~= to !(char) (letter + (wildcard ? 'a' : 'A'));
			res ~= to !(dchar) (letter + (wildcard ? 'a' : 'A'));
		}
		return res;
	}

	bool empty () @property const
	{
		return letter == NONE;
	}
}

struct Board
{
	immutable static int SIZE = 15;
	immutable static int CENTER = SIZE >> 1;
	immutable static ulong [SIZE] [SIZE] hash_mults;

	static this ()
	{
		foreach (row; 0..SIZE)
		{
			foreach (col; 0..SIZE)
			{
				hash_mults[row][col] = uniform !(ulong) ();
			}
		}
	}

	BoardCell [SIZE] [SIZE] contents;
	ulong [2] contents_hash;
	int score;
	int value;
	bool is_flipped;

	alias contents this;

	bool can_start_move (int row, int col, int len)
	{
		// 1. Correctness part, can not be skipped.
		// non-empty tile immediately preceding the path
		if (col > 0 && !contents[row][col - 1].empty)
		{
			return false;
		}
		// version to check against
//		return true;
		// 2. Optimization part, can be skipped.
		// one tile only
		if (col + 1 == SIZE)
		{
			return false;
		}
		// no free tiles on the path
		if (!contents[row][col].empty)
		{
			foreach (cur_col; col + 1..SIZE)
			{
				if (contents[row][cur_col].empty)
				{
					return true;
				}
			}
			return false;
		}
		// path connected with the center
		if (row == CENTER && col <= CENTER && CENTER < col + len)
		{
			return true;
		}
		// path connected with a non-empty tile
		int row_lo = max (0, row - 1);
		int row_hi = min (row + 1, SIZE - 1);
		int col_hi = min (col + len, SIZE);
		foreach (cur_col; col..col_hi)
		{
			foreach (cur_row; row_lo..row_hi + 1)
			{
				if (!contents[cur_row][cur_col].empty)
				{
					return true;
				}
			}
		}
		// non-empty tile immediately after len empty tiles
		if (col_hi < SIZE && !contents[row][col_hi].empty)
		{
			return true;
		}
		return false;
	}

	void flip ()
	{
		foreach (i; 0..SIZE - 1)
		{
			foreach (j; i + 1..SIZE)
			{
				swap (contents[i][j], contents[j][i]);
			}
		}
		is_flipped ^= true;
	}

	void normalize_flip ()
	{
		if (is_flipped)
		{
			flip ();
		}
	}

	void normalize ()
	{
		normalize_flip ();
		foreach (row; 0..SIZE)
		{
			foreach (col; 0..SIZE)
			{
				contents[row][col].active = false;
			}
		}
		contents_hash[0] = 0;
		contents_hash[1] = 0;
		foreach (row; 0..SIZE)
		{
			foreach (col; 0..SIZE)
			{
				contents_hash[0] += hash_mults[row][col] *
				    contents[row][col];
				contents_hash[1] += hash_mults[row][col] *
				    contents[col][row];
			}
		}
	}

	string toString () const
	{
		string res;
		foreach (line; contents)
		{
			foreach (cell; line)
			{
				res ~= cell.toString ();
			}
			res ~= '\n';
		}
		res ~= to !(string) (score) ~ ' ';
		res ~= to !(string) (is_flipped) ~ '\n';
		return res;
	}
}
