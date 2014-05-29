module game;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;
import std.math;
import std.stdio;
import std.string;

import board;
import general;
import goal;
import problem;
import scoring;
import tilebag;
import trie;

struct GameState
{
	Board board;
	TileBag tiles;
	GameMove recent_move;

	this (Problem new_problem)
	{
		tiles = TileBag (new_problem.contents);
		board.normalize ();
	}

	bool opEquals (const ref GameState other) const
	{
		return board == other.board;
	}

	string toString ()
	{
		string res = board.toString () ~ tiles.toString () ~ '\n';
		string [] moves;
		for (GameMove cur_move = recent_move; cur_move !is null;
		    cur_move = cur_move.prev_move)
		{
			moves ~= to !(string) (cur_move);
		}
		reverse (moves);
		res ~= join (moves, ",\n");
		return res;
	}
}

class GameMove
{
	BoardCell [] word;
	byte row;
	byte col;
	bool is_flipped;
	int score;
	GameMove prev_move;

//	this () @disable;

	this (ref GameState cur, int new_row, int new_col, int add_score = NA)
	{
		row = to !(byte) (new_row);
		col = to !(byte) (new_col);
		while (col > 0 && !cur.board[row][col - 1].empty)
		{
			col--;
		}
		foreach (cur_col; col..new_col + 1)
		{
			word ~= cur.board[row][cur_col];
		}
//		writeln (col, ' ', new_col, ' ', word, ' ', add_score);
		is_flipped = cur.board.is_flipped;
		score = add_score;
		prev_move = cur.recent_move;
	}

	static string row_str (const int val)
	{
		return to !(string) (val + 1);
	}

	static string col_str (const int val)
	{
		return "" ~ to !(char) (val + 'A');
	}

	override string toString () const
	{
		string coord;
		if (is_flipped)
		{
			coord ~= col_str (row);
			coord ~= row_str (col);
		}
		else
		{
			coord ~= row_str (row);
			coord ~= col_str (col);
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

class Game
{
	enum Keep: bool {False, True};

	immutable static int FLAG_CONN = 1;
	immutable static int MULT_ACT = 2;

	Problem problem;
	Trie trie;
	Scoring scoring;
	Goal [] goals;
	GameState [] [] gs;
	int [] [] gsp;
	GameState best;
	int bests_num;
	int depth;
	int resume_step = NA;

	void consider (ref GameState cur, int row, int col,
	    int vert, int score, int mult, int flags)
	{
/*
		writeln ("got ", row, ' ', col, ' ',
		    vert, ' ', score, ' ', mult, ' ',
		    cur.tiles.rack);
*/
		// DIRTY HACK; TODO: parameterize!
		if ((cur.board[0][0].active + cur.board[0][7].active +
		    cur.board[0][14].active) % 3 != 0)
//		     + cur.board[7][0].active + cur.board[14][0].active
		{
			return;
		}

		int num = 0;
		foreach (cur_row; 0..Board.SIZE)
		{
			foreach (cur_col; 0..Board.SIZE)
			{
				num += !cur.board[cur_row][cur_col].empty;
			}
		}
		int add_score = vert + score * mult +
		    scoring.bingo * (flags >= Rack.MAX_SIZE * MULT_ACT);
		if (depth == 0 && gsp[num].length == bests_num &&
		    gs[num][gsp[num][$ - 1]].board.value >=
		    cur.board.value + add_score)
		{
			return;
		}

		auto next = cur;
		next.board.score += add_score;
//		next.board.value += add_score;
		next.tiles.rack.normalize ();
		next.tiles.fill_rack ();

		next.board.value = next.board.score;
		foreach (goal; goals)
		{
			int cur_value;
			final switch (goal.stage)
			{
				case Goal.Stage.PREPARE:
					cur_value = calc_goal_value_prepare
					    (next, goal);
					break;
				case Goal.Stage.MAIN:
					cur_value = calc_goal_value_main
					    (next, goal);
					break;
				case Goal.Stage.DONE:
					cur_value = calc_goal_value_done
					    (next, goal);
					break;
			}
//			writeln (cur_value);
			if (cur_value == NA)
			{
				return;
			}
			next.board.value += cur_value;
		}

		next.board.normalize ();
		next.recent_move = new GameMove (cur, row, col, add_score);
//		debug {writeln (next);}

		if (depth > 0)
		{
			depth--;
			move_start (next);
			depth++;
		}

		if (gsp[num].length == bests_num &&
		    gs[num][gsp[num][$ - 1]].board.value >= next.board.value)
		{
			return;
		}

		int i = 0;
		while (i < gsp[num].length &&
		    gs[num][gsp[num][i]].board.value >= next.board.value)
		{
			if ((gs[num][gsp[num][i]].board.contents_hash[0] ==
			    next.board.contents_hash[0]) ||
			    (gs[num][gsp[num][i]].board.contents_hash[0] ==
			    next.board.contents_hash[1]))
			{
				return;
			}
/*
			if (gsp[num].length >= (bests_num - 5) &&
			    gs[num][gsp[num][i]].board.value ==
			    next.board.value)
			{
				return;
			}
*/
			i++;
		}

		scope (exit)
		{
			if (best.board.value < next.board.value)
			{
				best = next;
			}
		}

		int j = i;
		while (j < gsp[num].length)
		{
			int d = gsp[num][j];
			if (gs[num][d].board.contents_hash ==
			    next.board.contents_hash)
			{
				gs[num][d] = next;
				foreach_reverse (k; i..j)
				{
					gsp[num][k + 1] = gsp[num][k];
				}
				gsp[num][i] = d;
				return;
			}
			j++;
		}

		if (gsp[num].length < bests_num)
		{
			int d = to !(int) (gsp[num].length);
			gs[num].assumeSafeAppend ();
			gs[num] ~= next;
			gsp[num].assumeSafeAppend ();
			gsp[num] ~= NA;
			foreach_reverse (k; i..d)
			{
				gsp[num][k + 1] = gsp[num][k];
			}
			gsp[num][i] = d;
		}
		else
		{
			int d = gsp[num][$ - 1];
			gs[num][d] = next;
			foreach_reverse (k; i..gsp[num].length - 1)
			{
				gsp[num][k + 1] = gsp[num][k];
			}
			gsp[num][i] = d;
		}
	}

	int calc_goal_value_prepare (ref GameState cur, Goal goal)
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

		foreach (pos, letter; goal.word)
		{
			if (!cur.board[row][col + pos].empty &&
			    ((cur.board[row][col + pos].letter != letter) ||
			    ((goal.mask_forbidden & (1 << pos)) != 0)))
			{
				return NA;
			}
		}

		int res = 0;
		if (goal.bias)
		{
			res += bias_value (cur, goal.bias);
		}
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
			int add = check_vertical (cur, row, col + pos);
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

	int calc_goal_value_main (ref GameState cur, Goal goal)
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
		foreach (pos, letter; goal.word)
		{
			if ((goal.mask_forbidden & (1 << pos)) != 0)
			{
				if (cur.board[row][col + pos].empty)
				{
					has_empty = true;
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
				return NA;
			}
		}

		return 0;
	}

	int calc_goal_value_done (ref GameState cur, Goal goal)
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

	int bias_value (ref GameState cur, int bias)
	{
		enforce (bias);
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

	int check_vertical (ref GameState cur,
	    const int row_init, const int col)
	{
		if (!cur.board[row_init][col].active)
		{
			return 0;
		}
		int row = row_init;
		while (row > 0 && !cur.board[row - 1][col].empty)
		{
			row--;
		}
		if (row == row_init)
		{
			if (row == Board.SIZE - 1 ||
			    cur.board[row + 1][col].empty)
			{
				return 0;
			}
		}
		int score = 0;
		int mult = 1;
		int v = Trie.ROOT;
		do
		{
			v = trie.contents[v].next (cur.board[row][col].letter);
			scoring.account (score, mult,
			    cur.board[row][col], row, col);
			if (v == NA)
			{
				return NA;
			}
			row++;
		}
		while (row < Board.SIZE && !cur.board[row][col].empty);
		if (!trie.contents[v].word)
		{
			return NA;
		}
		return score * mult;
	}

	void step_recur (ref GameState cur, int row, int col,
	    int vert, int score, int mult, int vt, int flags)
	{
		assert (!cur.board[row][col].empty);
		vt = trie.contents[vt].next (cur.board[row][col]);
		if (vt == NA)
		{
			return;
		}
		int add = check_vertical (cur, row, col);
		if (add == NA)
		{
			return;
		}
		if (add > 0)
		{
			flags |= FLAG_CONN;
		}
		vert += add;
		scoring.account (score, mult, cur.board[row][col], row, col);
		if (row == Board.CENTER && col == Board.CENTER)
		{
			flags |= FLAG_CONN;
		}
		if (col + 1 == Board.SIZE || cur.board[row][col + 1].empty)
		{
			if (trie.contents[vt].word &&
			    (flags & FLAG_CONN) &&
//			    (flags >= MULT_ACT * (1 + cur.board.is_flipped)))
//			    (flags >= MULT_ACT))
			    (flags >= MULT_ACT *
			    (1 + (cur.board.is_flipped && (vert > 0)))))
			{
				consider (cur, row, col,
				    vert, score, mult, flags);
			}
		}
		if (col + 1 < Board.SIZE)
		{
			move_recur (cur, row, col + 1,
			    vert, score, mult, vt, flags);
		}
	}

	void move_recur (ref GameState cur, int row, int col,
	    int vert, int score, int mult, int vt, int flags)
	{
/*
		debug {writeln ("move_recur in  ",
		    row, ' ', col, ' ', flags, ' ', score);}
		scope (exit)
		{
			debug {writeln ("move_recur out ",
			    row, ' ', col, ' ', flags, ' ', score);}
		}
*/
		if (!cur.board[row][col].empty)
		{
			step_recur (cur, row, col,
			    vert, score, mult, vt, flags | FLAG_CONN);
			return;
		}
		foreach (ref c; cur.tiles.rack.contents)
		{
			if (c.empty)
			{
				break;
			}
			if (c.num != 0)
			{
				c.dec ();
				scope (exit)
				{
					c.inc ();
				}
				if (c.letter != LET)
				{
					cur.board[row][col] = c.letter |
					    (1 << BoardCell.ACTIVE_SHIFT);
					step_recur (cur, row, col,
					    vert, score, mult, vt,
					    flags + MULT_ACT);
					continue;
				}
				foreach (ubyte letter; 0..LET)
				{
					cur.board[row][col] = letter |
					    (1 << BoardCell.WILDCARD_SHIFT) |
					    (1 << BoardCell.ACTIVE_SHIFT);
					step_recur (cur, row, col,
					    vert, score, mult, vt,
					    flags + MULT_ACT);
				}
			}
		}
		cur.board[row][col] = BoardCell.NONE;
	}

	void move_horizontal (ref GameState cur)
	{
		foreach (row; 0..Board.SIZE)
		{
			foreach (col; 0..Board.SIZE)
			{
				if (cur.board.can_start_move (row, col,
				    cur.tiles.rack.total))
				{
					move_recur (cur, row, col, 0, 0, 1,
					    Trie.ROOT, 0);
				}
			}
		}
	}

	void move_start (ref GameState cur)
	{
//		writeln (cur);
		move_horizontal (cur);
		if (!cur.board[Board.CENTER][Board.CENTER].empty)
		{
			cur.board.flip ();
			move_horizontal (cur);
			cur.board.flip ();
		}
	}

	void go (int upper_limit, Keep keep)
	{
		foreach (k; resume_step..upper_limit)
		{
			version (verbose)
			{
				writeln ("filled ", k, " tiles");
				stdout.flush ();
			}
			foreach (i, gsp_element; gsp[k])
			{
				version (verbose)
				{
					if (min (i, gsp[k].length - i) < 10)
					{
						writeln ("at:");
						writeln (gs[k][gsp_element]);
						stdout.flush ();
					}
				}
				move_start (gs[k][gsp_element]);
			}
			if (!keep)
			{
				gs[k] = null;
				gsp[k] = null;
			}
		}
		resume_step = upper_limit;
	}

	void cleanup (Keep keep)
	{
		if (!keep)
		{
			resume_step = NA;
			gs = null;
			gsp = null;
			foreach (k, gsp_line; gsp)
			{
				gs[k] = null;
				gsp[k] = null;
			}
		}
	}

	void play (int new_bests_num, int new_depth, Keep keep = Keep.False)
	{
		bests_num = new_bests_num;
		depth = new_depth;

		gs = new GameState [] [problem.contents.length + 1];
		gsp = new int [] [problem.contents.length + 1];
		foreach (k, gsp_line; gsp)
		{
			gs[k].reserve (bests_num);
			gsp[k].reserve (bests_num);
		}
		auto initial_state = GameState (problem);
		gs.assumeSafeAppend ();
		gs[0] ~= initial_state;
		gsp.assumeSafeAppend ();
		gsp[0] ~= 0;
		resume_step = 0;
		go (to !(int) (problem.contents.length), keep);
		cleanup (keep);
	}

	void resume (int new_bests_num, int new_depth, Keep keep = Keep.False)
	{
		if (new_bests_num != NA)
		{
			bests_num = new_bests_num;
		}
		if (new_depth != NA)
		{
			depth = new_depth;
		}

		enforce (gs != null);
		enforce (gsp != null);
		if (resume_step < problem.contents.length)
		{
			best.board.value = NA;
		}
/*
		if (!keep)
		{
			foreach (k; 0..resume_step)
			{
				gs[k] = null;
				gsp[k] = null;
			}
		}
*/
		gs.length = max (gs.length, problem.contents.length + 1);
		gsp.length = max (gsp.length, problem.contents.length + 1);
		foreach (k; resume_step..gs.length)
		{
			gs[k].reserve (bests_num);
			gsp[k].reserve (bests_num);
			foreach (ref gs_element; gs[k])
			{
				gs_element.tiles.update (problem.contents);
				// TODO: should clean up the following line
				gs_element.board.value =
				    gs_element.board.score;
			}
		}
		resume_step = max (0, resume_step - 6);
		go (to !(int) (problem.contents.length), keep);
		cleanup (keep);
	}

	this (Problem new_problem, Trie new_trie, Scoring new_scoring)
	{
		problem = new_problem;
		trie = new_trie;
		scoring = new_scoring;
	}

	override string toString ()
	{
		string [] moves;
		for (GameMove cur_move = best.recent_move; cur_move !is null;
		    cur_move = cur_move.prev_move)
		{
			moves ~= to !(string) (cur_move);
		}
		reverse (moves);
		return join (moves, ",\n");
	}
}
