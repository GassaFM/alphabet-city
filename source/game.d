module game;

import std.algorithm;
import std.array;
import std.ascii;
import std.conv;
import std.exception;
import std.format;
import std.math;
import std.stdio;
import std.string;
import std.typecons;

import board;
import general;
import goal;
import problem;
import scoring;
import tilebag;
import tools;
import trie;

struct GameState
{
	Board board;
	TileBag tiles;
	GameMove closest_move;

	static GameState read (ref File f)
	{
		GameState res;
		bool to_end = false;
		while (!to_end)
		{
			auto s = f.readln ().strip ();
			if (s.empty)
			{
				break;
			}
			if (s[$ - 1] == ',')
			{
				s.length--;
			}
			else
			{
				to_end = true;
			}
			res.closest_move = new GameMove (s, res.closest_move);
			res.board.score += res.closest_move.score;
		}
		res.board.value = res.board.score;
		return res;
	}

	void write (ref File f, const char [] problem_name)
	{
		f.writefln ("%s %s (%s)", problem_name,
		    board.score, board.value);
		string [] moves;
		for (GameMove cur_move = closest_move; cur_move !is null;
		    cur_move = cur_move.chained_move)
		{
			moves ~= to !(string) (cur_move);
		}
		reverse (moves);
		f.writefln ("%-(%s,\n%)", moves);
	}

	this (Problem new_problem)
	{
		tiles = TileBag (new_problem);
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
		for (GameMove cur_move = closest_move; cur_move !is null;
		    cur_move = cur_move.chained_move)
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
	bool is_chain_forward;
	int score;
	GameMove chained_move;

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
				word[i].letter = to !(byte) (ch - 'A');
				word[i].wildcard = false;
			}
			else if ('a' <= ch && ch <= 'z')
			{
				word[i].letter = to !(byte) (ch - 'a');
				word[i].wildcard = true;
			}
			else
			{
				enforce (false);
			}
		}

		score = to !(int) (t[2]);

		chained_move = new_chained_move;
	}

	this (GameMove other)
	{
		word = other.word;
		row = other.row;
		col = other.col;
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

	void update_active (ref GameState cur)
	{
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
	int bias;
	int bests_num;
	int depth;
	int resume_step = NA;

	GameMove moves_guide;
	BoardCell [] forced_word;
	int forced_cur;
	int forced_move_bonus = 10_000;
	bool forced_imaginary;
	bool forced_lock_wildcards;
	GameState imaginary_result;

	bool allow_mirror () @property const
	{ // mirror boards not allowed if no goals and no moves_guide
		return !goals.empty || moves_guide !is null;
	}

	int is_move_present (ref GameState cur, GameMove cur_move)
	{
		int res = 1;
		if (cur.board.is_flipped ^ cur_move.is_flipped)
		{
			int row = cur_move.col;
			int col = cur_move.row;
			foreach (pos; 0..cur_move.word.length)
			{
				if (cur.board[row + pos][col].letter !=
				    cur_move.word[pos].letter)
				{
					res = min (res,
					    cur.board[row + pos][col].empty -
					    1);
				}
			}
		}
		else
		{
			int row = cur_move.row;
			int col = cur_move.col;
			foreach (pos; 0..cur_move.word.length)
			{
				if (cur.board[row][col + pos].letter !=
				    cur_move.word[pos].letter)
				{
					res = min (res,
					    cur.board[row][col + pos].empty -
					    1);
				}
			}
		}
		return res;
	}

	void consider (ref GameState cur, int row, int col,
	    int vert, int score, int mult, int flags)
	{
		// DIRTY HACK; TODO: parameterize!
		if (cur.board.is_flipped)
		{
			if ((cur.board[0][0].active +
			    cur.board[7][0].active +
			    cur.board[14][0].active) % 3 != 0)
			{
//				stderr.writeln ("!");
				return;
			}
		}
		else
		{
			if ((cur.board[0][0].active +
			    cur.board[0][7].active +
			    cur.board[0][14].active) % 3 != 0)
			{
//				stderr.writeln ("!");
				return;
			}
		}

		if (forced_word !is null)
		{
			if (forced_word.length != forced_cur)
			{
				return;
			}
			if (forced_imaginary)
			{
				imaginary_result = cur;
				imaginary_result.board.normalize ();
				return;
			}
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
		if (depth == 0 && forced_word is null &&
		    gsp[num].length == bests_num &&
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
					cur_value =
					    GameTools.calc_goal_value_prepare
					    (next, goal, this);
					break;
				case Goal.Stage.MAIN:
					cur_value =
					    GameTools.calc_goal_value_main
					    (next, goal, this);
					break;
				case Goal.Stage.DONE:
					cur_value =
					    GameTools.calc_goal_value_done
					    (next, goal, this);
					break;
				case Goal.Stage.COMBINED:
					cur_value =
					    GameTools.calc_goal_value_combined
					    (next, goal, this);
					break;
			}
			if (cur_value == NA)
			{
				return;
			}
			next.board.value += cur_value;
		}

		next.board.normalize ();
		next.closest_move = new GameMove (cur, row, col, add_score);
		if (bias)
		{
			next.board.value += GameTools.bias_value (next, bias);
		}

		if (moves_guide !is null)
		{
			int ok = 1;
			for (GameMove cur_move = moves_guide;
			    cur_move !is null;
			    cur_move = cur_move.chained_move)
			{
				ok = min (ok,
				    is_move_present (next, cur_move));
				if (ok == 1)
				{
					next.board.value += forced_move_bonus;
				}
				else if (ok == 0)
				{
					if (!moves_can_happen (null,
					    cur_move, next))
					{
						return;
					}
					break;
				}
				else if (ok == NA)
				{
					return;
				}
				else
				{
					assert (false);
				}
			}
//			writeln ("ok = ", ok);
		}

		if (depth > 0)
		{
			depth--;
			scope (exit)
			{
				depth++;
			}
			move_start (next);
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
			    (!allow_mirror &&
			    (gs[num][gsp[num][i]].board.contents_hash[0] ==
			    next.board.contents_hash[1])))
			{
				return;
			}
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
			    (flags >= MULT_ACT *
			    (1 + (cur.board.is_flipped && (vert > 0)))))
			{ // make 1-letter h+v move almost always not flipped
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
		if (forced_word !is null)
		{
			version (debug_forced)
			{
				writeln (">4:");
				stdout.flush ();
			}
			if (forced_word.length <= forced_cur)
			{
				return;
			}
			auto forced_tile = forced_word[forced_cur];
			forced_cur++;
			scope (exit)
			{
				forced_cur--;
			}
			if (!cur.board[row][col].empty)
			{
				version (debug_forced)
				{
					writeln (">6: ",
					    cur.board[row][col].letter,
					    ' ', forced_tile.letter);
				}
				if (cur.board[row][col].letter ==
				    forced_tile.letter &&
				    (!forced_lock_wildcards ||
				    cur.board[row][col].wildcard ==
				    forced_tile.wildcard))
				{
					step_recur (cur, row, col,
					    vert, score, mult, vt,
					    flags | FLAG_CONN);
				}
				return;
			}
			version (debug_forced)
			{
				writeln (">5:");
				stdout.flush ();
			}

			if (forced_imaginary)
			{
				int num = void;
				if (cur.tiles.counter[forced_tile.letter] > 0)
				{
					num = forced_tile.letter;
				}
				else if (cur.tiles.counter[LET] > 0)
				{
					num = LET;
				}
				else
				{
					return;
				}
				cur.tiles.counter[num]--;
				scope (exit)
				{
					cur.tiles.counter[num]++;
				}
				if (!forced_tile.active)
				{
					return;
				}
				cur.board[row][col] = forced_tile |
				    (1 << BoardCell.ACTIVE_SHIFT);
				version (debug_forced)
				{
					writeln (">3: ", forced_word, ' ',
					    forced_cur, ' ',
					    cur.board[row][col]);
					stdout.flush ();
				}
				step_recur (cur, row, col,
				    vert, score, mult, vt,
				    flags + MULT_ACT);
				cur.board[row][col] = BoardCell.NONE;
				return;
			}

			forced_cur++;
			scope (exit)
			{
				forced_cur--;
			}
			version (debug_forced)
			{
				writeln (">7:");
				stdout.flush ();
			}

			foreach (ref c; cur.tiles.rack.contents)
			{
				if (c.empty)
				{
					break;
				}
				if (forced_lock_wildcards &&
				    c.is_wildcard != forced_tile.wildcard)
				{
					continue;
				}
				if ((c.is_wildcard ||
				    (c.letter == forced_tile.letter)) &&
				    (c.num != 0))
				{
					c.dec ();
					cur.tiles.counter[c.letter]--;
					scope (exit)
					{
						c.inc ();
						cur.tiles.counter[c.letter]++;
					}
					cur.board[row][col] =
					    forced_tile.letter |
					    (1 << BoardCell.ACTIVE_SHIFT) |
					    ((c.is_wildcard) <<
					    BoardCell.WILDCARD_SHIFT);
					step_recur (cur, row, col,
					    vert, score, mult, vt,
					    flags + MULT_ACT);
					continue;
				}
			}
			cur.board[row][col] = BoardCell.NONE;
			return;
		}

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
				cur.tiles.counter[c.letter]--;
				scope (exit)
				{
					c.inc ();
					cur.tiles.counter[c.letter]++;
				}
				if (!c.is_wildcard)
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

	void perform_move (ref GameState cur, GameMove cur_move)
	{
		BoardCell [] remember_forced_word = cur_move.word;
		swap (forced_word, remember_forced_word);
		scope (exit)
		{
			swap (forced_word, remember_forced_word);
		}

		int row = cur_move.row;
		int col = cur_move.col;

		bool to_flip = (cur.board.is_flipped != cur_move.is_flipped);
		if (to_flip)
		{
			cur.board.flip ();
		}
		scope (exit)
		{
			if (to_flip)
			{
				cur.board.flip ();
			}
		}

		if (cur.board.can_start_move (row, col, Rack.MAX_SIZE))
		{
			move_recur (cur, row, col, 0, 0, 1, Trie.ROOT, 0);
		}
	}

	void move_start (ref GameState cur)
	{
		move_horizontal (cur);
		if (!cur.board[Board.CENTER][Board.CENTER].empty ||
		    allow_mirror) // first move direction matters
		{
			cur.board.flip ();
			move_horizontal (cur);
			cur.board.flip ();
		}
	}

//	bool moves_can_happen (GameMove first_inverted, GameMove second)
	bool moves_can_happen (GameMove first_inverted, GameMove second,
	    GameState cur)
	{ // if GameState becomes a reference type, make a copy!
		bool remember_forced_imaginary = true;
		swap (forced_imaginary, remember_forced_imaginary);
		scope (exit)
		{
			swap (forced_imaginary, remember_forced_imaginary);
		}
		GameMove first = GameMove.invert (first_inverted);
//		auto cur = GameState (problem);
		for (GameMove cur_move = first; cur_move !is null;
		    cur_move = cur_move.chained_move)
		{
			version (debug_forced)
			{
				writeln ("(1) trying ", cur_move);
			}
			imaginary_result = GameState ();
			imaginary_result.board.value = NA;
			perform_move (cur, cur_move);
			version (debug_forced)
			{
				writeln (">1: ", cur_move);
				writeln (cur);
				writeln (imaginary_result);
				stdout.flush ();
			}
			if (imaginary_result.board.value == NA)
			{
				version (debug_forced)
				{
					writeln ("(1) false");
				}
				return false;
			}
			cur = imaginary_result;
		}
		for (GameMove cur_move = second; cur_move !is null;
		    cur_move = cur_move.chained_move)
		{
			version (debug_forced)
			{
				writeln ("(2) trying ", cur_move);
			}
			imaginary_result = GameState ();
			imaginary_result.board.value = NA;
			perform_move (cur, cur_move);
			version (debug_forced)
			{
				writeln (">2: ", cur_move);
				writeln (cur);
				writeln (imaginary_result);
				stdout.flush ();
			}
			if (imaginary_result.board.value == NA)
			{
				version (debug_forced)
				{
					writeln ("(2) false");
			        }
				return false;
			}
			cur = imaginary_result;
		}
		version (debug_forced)
		{
			writeln ("true!");
		}
		return true;
	}

	Tuple !(GameMove, Problem) reduce_move_history (GameMove history)
	{
		GameMove gm_res = null;
		Problem p_res = problem;
		BoardCell [] freed_cells;
		GameMove start = GameMove.invert (history);
		for (GameMove cur_move = start; cur_move !is null;
		    cur_move = cur_move.chained_move)
		{
//			writeln ("considering ", cur_move);
			// TODO: parameterize!
			if (cur_move.word.length == Board.SIZE ||
			    !moves_can_happen (cur_move.chained_move, gm_res,
			        GameState (problem)))
			{
//				writeln ("taking ", cur_move);
				GameMove temp = new GameMove (cur_move);
				temp.chained_move = gm_res;
				gm_res = temp;
			}
			else
			{
				foreach (t; cur_move.word)
				{
					if (t.active)
					{
						freed_cells ~= t;
					}
				}
			}
		}
		char [] freed_tiles;
		foreach_reverse (t; freed_cells)
		{
			if (t.wildcard)
			{
				freed_tiles ~= '?';
			}
			else
			{
				freed_tiles ~= to !(char) (t.letter + 'A');
			}
		}
		p_res.contents = to !(string) (freed_tiles);
		return tuple (gm_res, p_res);
	}

	GameMove restore_moves (ref GameState cur)
	{
		bool remember_forced_imaginary = true;
		swap (forced_imaginary, remember_forced_imaginary);
		scope (exit)
		{
			swap (forced_imaginary, remember_forced_imaginary);
		}
		auto temp = GameState (problem);
		GameMove start = GameMove.invert (cur.closest_move);
		for (GameMove cur_move = start; cur_move !is null;
		    cur_move = cur_move.chained_move)
		{
			cur_move.update_active (temp);
			imaginary_result = GameState ();
			imaginary_result.board.value = NA;
			perform_move (temp, cur_move);
			if (imaginary_result.board.value == NA)
			{
				enforce (false);
			}
			temp = imaginary_result;
		}
		return GameMove.invert (start);
	}

	void go (int upper_limit, Keep keep)
	{
		foreach (k; resume_step..upper_limit + 1)
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
					if (min (i,
					    gsp[k].length - 1 - i) < 10)
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

	void resume (int new_bests_num, int new_depth,
	    int start_from = resume_step, Keep keep = Keep.False,
	    bool clear_value = false, bool was_virtual = false)
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
		gs.length = max (gs.length, problem.contents.length + 1);
		gsp.length = max (gsp.length, problem.contents.length + 1);
		resume_step = max (0, min (start_from, resume_step) - 6);

		if (resume_step < problem.contents.length)
		{
			best.board.value = NA;
		}
		if (!keep)
		{
			foreach (k; 0..resume_step)
			{
				gs[k] = null;
				gsp[k] = null;
			}
		}
		foreach (k; resume_step..gs.length)
		{
			gs[k].reserve (bests_num);
			gsp[k].reserve (bests_num);
			foreach (ref gs_element; gs[k])
			{
				gs_element.tiles.update (problem.contents,
				    was_virtual);
				if (clear_value)
				{
					gs_element.board.value =
					    gs_element.board.score;
				}
			}
			sort !((a, b) => gs[k][a].board.value >
			    gs[k][b].board.value, SwapStrategy.stable)
			    (gsp[k]);
		}
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
		for (GameMove cur_move = best.closest_move; cur_move !is null;
		    cur_move = cur_move.chained_move)
		{
			moves ~= to !(string) (cur_move);
		}
		reverse (moves);
		return join (moves, ",\n");
	}
}
