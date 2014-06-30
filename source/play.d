module play;

import std.stdio;

import board;
import game_move;
import game_state;
import general;
import problem;
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

	GameMove cur_move;

	void consider ()
	{
		version (debug_play)
		{
			writeln ("consider ", row, ' ', col);
		}
		int add_score = scoring.calculate
		    (vert_score, main_score, score_mult, active_tiles);
		cur.board.score += add_score;
		cur.closest_move = new GameMove (cur_move);
		cur.closest_move.score = add_score;
		cur.closest_move.word = cur.closest_move.word.dup;
		auto tiles_saved = cur.tiles;
		cur.tiles.rack.normalize ();
		cur.tiles.fill_rack ();
		cur.xor_active ();
		scope (exit)
		{
			cur.xor_active ();
			cur.tiles = tiles_saved;
			cur.closest_move = cur_move.chained_move;
			cur.board.score -= add_score;
		}
		(*process) (*cur);
	}

	int check_vertical ()
	{
		version (debug_play)
		{
			writeln ("check_vertical ", row, ' ', col);
		}
		if (!cur.board[row][col].active)
		{
			return 0;
		}

		int cur_row = row;
		while (cur_row > 0 && !cur.board[cur_row - 1][col].empty)
		{
			cur_row--;
		}

		if (cur_row == row &&
		    (cur_row == Board.SIZE - 1 ||
		    cur.board[cur_row + 1][col].empty))
		{
			return 0;
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
		version (debug_play)
		{
			writeln ("step_recur ", row, ' ', col);
		}
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
		scope (exit)
		{
			vt = vt_saved;
		}
		vt = dict.contents[vt].next (cur.board[row][col]);
		if (vt == NA)
		{
			return;
		}

		int vert_add = check_vertical ();
		if (vert_add == NA)
		{
			return;
		}

		int main_score_saved = main_score;
		int score_mult_saved = score_mult;
		connections += (vert_add > 0) ||
		    (row == Board.CENTER && col == Board.CENTER);
		vert_score += vert_add;
		cur_move.word ~= cur.board[row][col];
		scope (exit)
		{
			main_score = main_score_saved;
			score_mult = score_mult_saved;
			connections -= (vert_add > 0) ||
			    (row == Board.CENTER && col == Board.CENTER);
			vert_score -= vert_add;
			cur_move.word.length--;
			cur_move.word.assumeSafeAppend ();
		}
		scoring.account (main_score, score_mult,
		    cur.board[row][col], row, col);

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
		version (debug_play)
		{
			writeln ("move_recur ", row, ' ', col);
		}
		if (!cur.board[row][col].empty)
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
			cur.board.total--;
			active_tiles--;
			cur.board[row][col] = BoardCell.NONE;
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
		version (debug_play)
		{
			writeln ("move_horizontal");
		}
		cur_move.initialize (*cur);
		for (row = 0; row < Board.SIZE; row++)
		{
			for (col = 0; col < Board.SIZE; col++)
			{
				if (cur.board.suggest_start_move (row, col,
				    cur.tiles.rack.usable_total))
				{
					cur_move.start_at (row, col);
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

	ref typeof (this) opCall (ref GameState new_cur)
	{
		cur = &new_cur;
		return this;
	}

	int opApply (int delegate (ref GameState) new_process)
	{
		process = &new_process;

		move_start ();

		return 0;
	}

	this (DictClass new_dict, Scoring new_scoring)
	{
		dict = new_dict;
		scoring = new_scoring;

		cur_move = new GameMove ();
	}
}

unittest
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
	auto s = new Scoring ();
	auto play = Play !(Trie) (t, s);
	auto cur = GameState (Problem ("?:", "ABCDEFG"));
	foreach (next; play (cur))
	{
//		writeln (next);
//		stdout.flush ();
		assert (next.board.score > 0);
	}
/*
	writeln (play.connections);
	writeln (play.active_tiles);
	writeln (play.vert_score);
	writeln (play.main_score);
	writeln (play.score_mult);
	writeln (play.vt);
	writeln (play.cur_move);
	stdout.flush ();
*/
}
