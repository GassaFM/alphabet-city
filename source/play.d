module play;

import board;
import game_move;
import game_state;
import general;
import scoring;
import tile_bag;
import trie;

struct Play (DictClass)
{
//	enum MoveGenerator {Rack, Word};
	
	DictClass dict;
	Scoring scoring;

	GameState * cur;
	int delegate (ref GameState) * process;

	byte row = byte.max;
	byte col = byte.max;
	byte connections = 0;
	byte active_tiles = 0;
	int vert_score = 0;
	int main_score = 0;
	int score_mult = 1;
	int vt = DictClass.ROOT;

	void consider ()
	{
		int add_score = vert_score + main_score * score_mult +
		    scoring.bingo * (active_tiles == Rack.MAX_SIZE);
		cur.board.score += add_score;
		scope (exit)
		{
			cur.board.score -= add_score;
		}
		(*process) (*cur);
	}

	int check_vertical ()
	{
		if (!cur.board[row][col].active)
		{
			return 0;
		}
		int cur_row = row;
		while (cur_row > 0 && !cur.board[cur_row][col].empty)
		{
			cur_row--;
		}
		if (cur_row == row)
		{
			if (cur_row == Board.SIZE - 1 ||
			    cur.board[cur_row + 1][col].empty)
			{
				return 0;
			}
		}
		int score = 0;
		int mult = 1;
		int v = DictClass.ROOT;
		do
		{
			v = dict.contents[v].next
			    (cur.board[cur_row][col].letter);
			scoring.account (score, mult,
			    cur.board[cur_row][col], cur_row, col);
			if (v == NA)
			{
				return NA;
			}
			cur_row++;
		}
		while (cur_row < Board.SIZE &&
		    !cur.board[cur_row][col].empty);
		if (!dict.contents[v].word)
		{
			return NA;
		}
		return score * mult;
	}

	void step_recur ()
	{
		assert (!cur.board[row][col].empty);
/*
		if (check_board.is_flipped == cur.board.is_flipped)
		{
			if (!check_board[row][col].empty &&
			    check_board[row][col].letter !=
			    cur.board[row][col].letter)
			{
				return;
			}
		}
		else
		{
			if (!check_board[col][row].empty &&
			    check_board[col][row].letter !=
			    cur.board[row][col].letter)
			{
				return;
			}
		}
*/
		int vt_saved = vt;
		vt = dict.contents[vt].next (cur.board[row][col]);
		if (vt == NA)
		{
			return;
		}

		int add = check_vertical ();
		if (add == NA)
		{
			return;
		}

		int main_score_saved = main_score;
		int score_mult_saved = score_mult;
		scoring.account (main_score, score_mult,
		    cur.board[row][col], row, col);
		connections += (add > 0);
		connections += (row == Board.CENTER &&
		    col == Board.CENTER);
		vert_score += add;
		scope (exit)
		{
			connections -= (add > 0);
			connections -= (row == Board.CENTER &&
			    col == Board.CENTER);
			vert_score -= add;
			main_score = main_score_saved;
			score_mult = score_mult_saved;
			vt = vt_saved;
		}

		if (col + 1 == Board.SIZE || cur.board[row][col + 1].empty)
		{
			if (dict.contents[vt].word &&
			    connections &&
			    (active_tiles >=
			    (1 + (cur.board.is_flipped && vert_score))))
			{ // make 1-letter h+v move almost always not flipped
				consider ();
			}
		}
		if (col + 1 < Board.SIZE)
		{
			col++;
			scope (exit)
			{
				col--;
			}
			move_recur ();
		}
	}

	void move_recur ()
	{
		if (cur.board[row][col].empty)
		{
			connections++;
			scope (exit)
			{
				connections--;
			}
			step_recur ();
			return;
		}

		cur.board.total++;
		active_tiles++;
		scope (exit)
		{
			cur.board[row][col] = BoardCell.NONE;
			cur.board.total--;
			active_tiles--;
		}

		foreach (ref c; cur.tiles.rack.contents)
		{
			if (c.empty)
			{
				break;
			}

			if (c.num != 0)
			{
				cur.tiles.dec (c);
				scope (exit)
				{
					cur.tiles.inc (c);
				}

				if (!c.is_wildcard)
				{
					cur.board[row][col] = c.letter |
					    (1 << BoardCell.ACTIVE_SHIFT);
					step_recur ();
					continue;
				}

				foreach (ubyte letter; 0..LET)
				{
					cur.board[row][col] = letter |
					    (1 << BoardCell.WILDCARD_SHIFT) |
					    (1 << BoardCell.ACTIVE_SHIFT);
					step_recur ();
				}
			}
		}
	}

	void move_horizontal ()
	{
		for (row = 0; row < Board.SIZE; row++)
		{
			for (col = 0; col < Board.SIZE; col++)
			{
				if (cur.board.suggest_start_move (row, col,
				    cur.tiles.rack.usable_total))
				{
					move_recur ();
				}
			}
		}
	}

	void move_start ()
	{
		move_horizontal ();
		cur.board.flip ();
		move_horizontal ();
		cur.board.flip ();
	}

	void opApply (ref GameState new_cur,
	    int delegate (ref GameState) new_process)
	{
		cur = &new_cur;
		process = &new_process;

		move_start ();
	}

	this (DictClass new_dict, Scoring new_scoring)
	{
		dict = new_dict;
		scoring = new_scoring;
	}
}

unittest
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
	auto s = new Scoring ();
	auto play = new Play !(Trie) (t, s);
}
