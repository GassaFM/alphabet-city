module game_move;

import std.array;
import std.ascii;
import std.conv;
import std.exception;
import std.format;
import std.string;

import board;
import game_state;
import general;
import tile_bag;

class GameMove
{
	BoardCell [] word;
	byte row;
	byte col;
	byte tiles_before;
	bool is_flipped;
	bool is_chain_forward;
	int score;
	GameMove chained_move;

	int count_active () const
	{
		int res = 0;
		foreach (tile; word)
		{
			res += tile.active;
		}
		return res;
	}

	void xor_active (ref Board board)
	{
		assert (is_flipped == board.is_flipped);
		// easy to implement otherwise if needed
		foreach (pos; 0..word.length)
		{
			board.contents[row][col + pos] ^= word[pos] &
			    (1 << BoardCell.ACTIVE_SHIFT);
		}
	}

	void add_hash (ref Board board)
	{
		assert (is_flipped == board.is_flipped);
		// easy to implement otherwise if needed
		if (is_flipped)
		{
			foreach (pos; 0..word.length)
			{
				if (word[pos].active)
				{
					board.contents_hash[0] +=
					    board.hash_mults[row][col + pos] *
					    (word[pos] ^
					    (1 << BoardCell.ACTIVE_SHIFT));
				}
			}
		}
		else
		{
			foreach (pos; 0..word.length)
			{
				if (word[pos].active)
				{
					board.contents_hash[0] +=
					    board.hash_mults[col + pos][row] *
					    (word[pos] ^
					    (1 << BoardCell.ACTIVE_SHIFT));
				}
			}
		}
	}

	void start_at (byte new_row, byte new_col)
	{
		row = new_row;
		col = new_col;
	}

	void initialize (ref GameState cur)
	{
		tiles_before = cur.board.total; // cur.board is BEFORE the move
		is_flipped = cur.board.is_flipped;
		chained_move = cur.closest_move;
		word.reserve (Board.SIZE + 1);
	}

	this ()
	{
	}

	this (ref GameState cur, int new_row, int new_col, int add_score = NA)
	{
		row = cast (byte) (new_row);
		col = cast (byte) (new_col);
		while (col > 0 && !cur.board[row][col - 1].empty)
		{
			col--;
		}
		tiles_before = cur.board.total; // cur.board is AFTER the move
		foreach (cur_col; col..new_col + 1)
		{
			auto cur_tile = cur.board[row][cur_col];
			tiles_before -= cur_tile.active;
			word ~= cur_tile;
		}
		is_flipped = cur.board.is_flipped;
		score = add_score;
		chained_move = cur.closest_move;
	}

	this (const char [] data, GameMove new_chained_move = null)
	{
		auto t = data.split ();
		if (t[0][0].isDigit ())
		{
			is_flipped = false;
			row = str_to_row (t[0][0..$ - 1]);
			col = str_to_col (t[0][$ - 1..$]);
		}
		else
		{
			is_flipped = true;
			row = str_to_col (t[0][0..1]);
			col = str_to_row (t[0][1..$]);
		}

		word = new BoardCell [t[1].length];
		foreach (i, ch; t[1])
		{
			if ('A' <= ch && ch <= 'Z')
			{
				word[i].letter = cast (byte) (ch - 'A');
				word[i].wildcard = false;
			}
			else if ('a' <= ch && ch <= 'z')
			{
				word[i].letter = cast (byte) (ch - 'a');
				word[i].wildcard = true;
			}
			else
			{
				enforce (false);
			}
		}

		score = to !(int) (t[2]);

		tiles_before = NA;
		chained_move = new_chained_move;
	}

	this (GameMove other)
	{
		word = other.word;
		row = other.row;
		col = other.col;
		tiles_before = other.tiles_before;
		is_flipped = other.is_flipped;
		is_chain_forward = other.is_chain_forward;
		score = other.score;
		chained_move = other.chained_move;
	}

	static GameMove invert (GameMove cur_move)
	{
		if (cur_move is null)
		{
			return null;
		}
		auto cur = new GameMove (cur_move);
		GameMove next = null;
		while (cur !is null)
		{
			auto prev = cur.chained_move;
			if (prev !is null)
			{
				prev = new GameMove (prev);
			}
			cur.is_chain_forward ^= true;
			cur.chained_move = next;
			next = cur;
			cur = prev;
		}
		return next;
	}

	static GameMove merge_guides (GameMove first, GameMove second)
	{
		GameMove res;
		while (first !is null || second !is null)
		{
			GameMove next;
			if (first is null)
			{
				next = second;
			}
			else if (second is null)
			{
				next = first;
			}
			else if (first.tiles_before < second.tiles_before)
			{
				next = first;
			}
			else if (first.tiles_before > second.tiles_before)
			{
				next = second;
			}
			else
			{
				enforce (false);
			}

			next = new GameMove (next);
			next.is_chain_forward ^= true;
			next.chained_move = res;
			res = next;
		}
		res = GameMove.invert (res);
		return res;
	}

	void normalize (ref GameState cur)
	{
		tiles_before = cur.board.total; // cur.board is before the move
		if (cur.board.is_flipped ^ is_flipped)
		{
			foreach (pos; 0..word.length)
			{
				if (cur.board[col + pos][row].letter !=
				    word[pos].letter)
				{
					enforce
					    (cur.board[col + pos][row].empty);
					word[pos].active = true;
				}
				else
				{
					word[pos].active = false;
				}
			}
		}
		else
		{
			foreach (pos; 0..word.length)
			{
				if (cur.board[row][col + pos].letter !=
				    word[pos].letter)
				{
					enforce
					    (cur.board[row][col + pos].empty);
					word[pos].active = true;
				}
				else
				{
					word[pos].active = false;
				}
			}
		}
	}

	static string row_to_str (const int val)
	{
		return to !(string) (val + 1);
	}

	static string col_to_str (const int val)
	{
		return "" ~ to !(char) (val + 'A');
	}

	static byte str_to_row (const char [] val)
	{
		return to !(byte) (to !(int) (val) - 1);
	}

	static byte str_to_col (const char [] val)
	{
		return to !(byte) (val[0] - 'A');
	}

	override string toString () const
	{
		string coord;
		if (is_flipped)
		{
			coord ~= col_to_str (row);
			coord ~= row_to_str (col);
		}
		else
		{
			coord ~= row_to_str (row);
			coord ~= col_to_str (col);
		}

		auto sink = appender !(string) ();
		formattedWrite (sink, "%3s %(%s%)", coord, word);
		if (score != NA)
		{
			formattedWrite (sink, " %4s", score);
		}
		return sink.data;
	}
}
