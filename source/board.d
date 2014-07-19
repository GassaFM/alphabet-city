module board;

import std.algorithm;
import std.conv;
import std.exception;
import std.math;
import std.random;
import std.string;

import general;

struct BoardCell
{
	immutable static int WILDCARD_SHIFT = LET_BITS;
	immutable static int ACTIVE_SHIFT = LET_BITS + 1;
	immutable static int IS_WILDCARD = 1 << WILDCARD_SHIFT;
	immutable static int IS_ACTIVE = 1 << ACTIVE_SHIFT;
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
		contents = cast (byte) ((contents & ~(1 << WILDCARD_SHIFT)) |
		    (new_wildcard << WILDCARD_SHIFT));
		return new_wildcard;
	}

	bool active () @property const
	{
		return (contents & (1 << ACTIVE_SHIFT)) != 0;
	}

	byte active (const byte new_active) @property
	{
		contents = cast (byte) ((contents & ~(1 << ACTIVE_SHIFT)) |
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

	this (byte new_contents)
	{
		contents = new_contents;
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
	byte total;
	bool is_flipped;

	alias contents this;

	bool can_start_move (int row, int col, int len)
	{
		// non-empty tile immediately preceding the path
		if (col > 0 && !contents[row][col - 1].empty)
		{
			return false;
		}
		return true;
	}

	bool suggest_start_move (int row, int col, int len)
	{
		// 1. Correctness part, can not be skipped.
		if (!can_start_move (row, col, len))
		{
			return false;
		}
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

	bool is_row_filled (int row) const
	{
		enforce (!is_flipped);
		foreach (col; 0..Board.SIZE)
		{
			if (contents[row][col].empty)
			{
				return false;
			}
		}
		return true;
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

	void normalize_active ()
	{
		foreach (row; 0..SIZE)
		{
			foreach (col; 0..SIZE)
			{
				contents[row][col].active = false;
			}
		}
	}

	void normalize_hash ()
	{
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

	void normalize ()
	{
		normalize_flip ();
		normalize_active ();
		normalize_hash ();
	}

	int distance_to_covered (int cur_row, int cur_col,
	    bool cur_is_flipped) const
	{
		if (cur_is_flipped != is_flipped)
		{
			swap (cur_row, cur_col);
		}
		if (!contents[cur_row][cur_col].empty)
		{ // optimization
			return 0;
		}

		static assert (Board.SIZE < int.sizeof * 8);
		int res = Board.SIZE;
		foreach (row; 0..Board.SIZE)
		{
			foreach (col; 0..Board.SIZE)
			{
				if (!contents[row][col].empty)
				{
					res = min (res,
					    abs (row - cur_row) +
					    abs (col - cur_col));
				}
			}
		}
		return res;
	}

	int distance_to_covered_no_horiz (int cur_row, int cur_col,
	    bool cur_is_flipped) const
	{
		if (cur_is_flipped != is_flipped)
		{
			swap (cur_row, cur_col);
		}
		if (!contents[cur_row][cur_col].empty)
		{ // optimization
			return 0;
		}

		int res = Board.SIZE;
		foreach (row; 0..Board.SIZE)
		{
			if (!is_flipped && row == cur_row)
			{
				continue;
			}
			foreach (col; 0..Board.SIZE)
			{
				if (is_flipped && col == cur_col)
				{
					continue;
				}
				if (!contents[row][col].empty)
				{
					res = min (res,
					    abs (row - cur_row) +
					    abs (col - cur_col));
				}
			}
		}

/*
		if (res == 2)
		{ // tweak: prevent being stuck
			res++;
		}
*/
		if (res > 0)
		{ // tweak: actual put should happen anyway
			res--;
		}
		return res;
	}

	int distance_to_covered_adjacent (int cur_row, int cur_col,
	    bool cur_is_flipped) const
	{
		if (cur_is_flipped != is_flipped)
		{
			swap (cur_row, cur_col);
		}
		if (!contents[cur_row][cur_col].empty)
		{ // optimization
			return 0;
		}
		assert (0 < cur_row && cur_row < Board.SIZE - 1 &&
		    0 < cur_col && cur_col < Board.SIZE - 1);
		if (!contents[cur_row - 1][cur_col - 1].empty ||
		    !contents[cur_row - 1][cur_col + 1].empty ||
		    !contents[cur_row + 1][cur_col - 1].empty ||
		    !contents[cur_row + 1][cur_col + 1].empty)
		{ // tweak: allow more options
			return 1;
		}

		int res = Board.SIZE;
		foreach (row; 0..Board.SIZE)
		{
			foreach (col; 0..Board.SIZE)
			{
				if (!contents[row][col].empty)
				{
					res = min (res,
					    abs (row - cur_row) +
					    abs (col - cur_col));
				}
			}
		}

		if (res == 1)
		{ // tweak: prevent being stuck
			res++;
		}
		return res;
	}

	string toString () const
	{
		string res;
		if (!is_flipped)
		{
			foreach (row; 0..Board.SIZE)
			{
				foreach (col; 0..Board.SIZE)
				{
					res ~= contents[row][col].toString ();
				}
				res ~= '\n';
			}
		}
		else
		{
			foreach (row; 0..Board.SIZE)
			{
				foreach (col; 0..Board.SIZE)
				{
					res ~= contents[col][row].toString ();
				}
				res ~= '\n';
			}
		}
		res ~= to !(string) (score) ~ ' ';
		res ~= '(' ~ to !(string) (value) ~ ") ";
		res ~= to !(string) (is_flipped) ~ '\n';
//		res ~= to !(string) (contents_hash[0]) ~ '\n';
		return res;
	}
}
