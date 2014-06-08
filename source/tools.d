module tools;

import std.exception;
import std.math;
import std.stdio;

import board;
import game;
import general;
import goal;
import tilebag;

static class GameTools
{
	static int calc_goal_value_prepare (ref GameState cur, Goal goal,
	    Game game)
	{
		if (cur.board.is_flipped != goal.is_flipped)
		{
			cur.board.flip ();
		}
		int row = goal.row;
		int col = goal.col;
		assert (col == 0);
		// else: check to the left not implemented
		assert (col + goal.word.length == Board.SIZE);
		// else: check to the right not implemented

		TileCounter counter;
		foreach (pos, letter; goal.word)
		{
			if (cur.board[row][col + pos].empty)
			{
				counter[letter]++;
/*
				if ((goal.mask_forbidden & (1 << pos)) == 0)
				{
					counter[letter]++;
				}
*/			}
			else
			{
				if (((goal.mask_forbidden &
				    (1 << pos)) != 0) ||
				    (cur.board[row][col + pos].letter !=
				    letter))
				{
					return NA;
				}
			}
		}
		if (!(counter << cur.tiles.counter))
		{
			return NA;
		}

		int res = 0;
		foreach (int pos, letter; goal.word)
		{
			bool is_empty = cur.board[row][col + pos].empty;
			if (is_empty)
			{
				cur.board[row][col + pos] = letter |
				    (1 << BoardCell.ACTIVE_SHIFT);
			}
			else
			{
				res += goal.letter_bonus >>
				    cur.board[row][col + pos].wildcard;
			}
			int add = game.check_vertical (cur, row, col + pos);
			if (is_empty)
			{
				cur.board[row][col + pos] = BoardCell.NONE;
			}
			if (add == NA)
			{
				return NA;
			}
			res += add;
		}
		return res;
	}

	static int calc_goal_value_main (ref GameState cur, Goal goal,
	    Game game)
	{
		if (cur.board.is_flipped != goal.is_flipped)
		{
			cur.board.flip ();
		}
		int row = goal.row;
		int col = goal.col;
		assert (col == 0);
		// else: check to the left not implemented
		assert (col + goal.word.length == Board.SIZE);
		// else: check to the right not implemented

		bool has_empty = false;
		bool has_full = false;
		TileCounter counter;
		foreach (pos, letter; goal.word)
		{
			if ((goal.mask_forbidden & (1 << pos)) != 0)
			{
				if (cur.board[row][col + pos].empty)
				{
					has_empty = true;
					counter[letter]++;
				}
				else
				{
					has_full = true;
				}
				if (has_empty && has_full)
				{
					return NA;
				}
			}
			else if (cur.board[row][col + pos].empty)
			{
				// soft prepare stage completion requirement
				counter[letter]++;
				// hard prepare stage completion requirement
//				return NA;
			}
		}

		if (!(counter << cur.tiles.counter))
		{
			return NA;
		}
		return 0;
	}

	static int calc_goal_value_done (ref GameState cur, Goal goal,
	    Game game)
	{
		if (cur.board.is_flipped != goal.is_flipped)
		{
			cur.board.flip ();
		}
		int row = goal.row;
		int col = goal.col;

		foreach (pos, letter; goal.word)
		{
			if (cur.board[row][col + pos].empty)
			{
				return NA;
			}
		}

		return 0;
	}

	static int calc_goal_value_combined (ref GameState cur, Goal goal,
	    Game game)
	{
		if (cur.board.is_flipped != goal.is_flipped)
		{
			cur.board.flip ();
		}
		int row = goal.row;
		int col = goal.col;
		assert (col == 0);
		// else: check to the left not implemented
		assert (col + goal.word.length == Board.SIZE);
		// else: check to the right not implemented

		// cast should be safe since goal.word.length is surely int32
		int max_num = cast (int) (goal.word.length - Rack.MAX_SIZE);

		bool has_empty = false;
		bool has_full = false;
		TileCounter counter;
		foreach (pos, letter; goal.word)
		{
			if ((goal.mask_forbidden & (1 << pos)) != 0)
			{
				if (cur.board[row][col + pos].empty)
				{
					has_empty = true;
					counter[letter]++;
				}
				else
				{
					if (letter !=
					    cur.board[row][col + pos].letter)
					{
						return NA;
					}
					has_full = true;
				}
				if (has_empty && has_full)
				{
					return NA;
				}
			}
			else
			{
				if (cur.board[row][col + pos].empty)
				{
					counter[letter]++;
				}
				else
				{
					if (letter !=
					    cur.board[row][col + pos].letter)
					{
						return NA;
					}
				}
			}
		}

		if (!has_empty)
		{
			return goal.letter_bonus * max_num;
		}

		int res = 0;
		int num = 0;
		foreach (int pos, letter; goal.word)
		{
			if (cur.board[row][col + pos].empty)
			{
				cur.board[row][col + pos] = letter |
				    (1 << BoardCell.ACTIVE_SHIFT);
				scope (exit)
				{
					cur.board[row][col + pos] =
					    BoardCell.NONE;
				}
				int add = game.check_vertical (cur,
				    row, col + pos);
				if (add == NA)
				{
					return NA;
				}
				res += add;
			}
			else
			{
				if (goal.word.length == Board.SIZE &&
				    (pos == 3 || pos == 11 || num >= max_num))
				{ // encourage bingo and double-letter bonus
					assert (true);
				}
				else
				{
					res += goal.letter_bonus >>
					    cur.board[row][col + pos].wildcard;
				}
				num++;
			}
		}
		return res;
	}

	static int bias_value (ref GameState cur, int bias)
	{
		enforce (bias);
		enforce (!cur.board.is_flipped);
		int res = 0;
		if (bias > 0)
		{
			foreach (row; 0..Board.CENTER)
			{
				foreach (col; 0..Board.SIZE)
				{
					if (!cur.board[row][col].empty)
					{
						res += Board.CENTER - row;
					}
				}
			}
		}
		else
		{
			foreach (row; 0..Board.CENTER)
			{
				foreach (col; 0..Board.SIZE)
				{
					if (!cur.board[Board.SIZE - 1 -
					    row][col].empty)
					{
						res += Board.CENTER - row;
					}
				}
			}
		}
		return res * abs (bias);
	}
}
