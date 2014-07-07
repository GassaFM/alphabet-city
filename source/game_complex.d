module game_complex;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.stdio;
import std.typecons;

import board;
import game_state;
import game_move;
import general;
import goal;
import problem;
import scoring;
import tile_bag;
import tools;
import trie;

final class GameComplex
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

	Board check_board;
	GameMove moves_guide;
	BoardCell [] forced_word;
	int forced_cur;
	int forced_move_bonus = 10_000;
	bool forced_imaginary;
	bool forced_lock_wildcards;
	bool forced_restricted;
	bool forced_allow_empty;
	GameState imaginary_result;

	bool allow_mirror () @property const
	{ // mirror boards not allowed if no goals and no moves_guide
//		return !goals.empty || moves_guide !is null;
		return true;
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
/*
		// DIRTY HACK; TODO: parameterize!
		if (cur.board.is_flipped)
		{
			if ((cur.board[0][0].active +
			    cur.board[7][0].active +
			    cur.board[14][0].active) % 3 != 0)
			{
				return;
			}
		}
		else
		{
			if ((cur.board[0][0].active +
			    cur.board[0][7].active +
			    cur.board[0][14].active) % 3 != 0)
			{
				return;
			}
		}
*/

		int num = cur.board.total;
		int add_score = vert + score * mult +
		    scoring.bingo * (flags >= Rack.MAX_SIZE * MULT_ACT);
		if (num > TOTAL_TILES)
		{
			writeln (cur);
		}
		if (depth == 0 && forced_word is null &&
		    gsp[num].length == bests_num &&
		    gs[num][gsp[num][$ - 1]].board.value >=
		    cur.board.value + add_score)
		{
			return;
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
				imaginary_result.board.score += add_score;
				imaginary_result.board.value += add_score;
				imaginary_result.board.normalize ();
				return;
			}
		}

		auto next = cur;
		next.board.score += add_score;
//		next.board.value += add_score;
		next.tiles.rack.normalize ();
		next.tiles.fill_rack ();

		next.board.value = next.board.score;
		TileCounter counter;
		foreach (goal; goals)
		{
			int cur_value;
			final switch (goal.stage)
			{
				case Goal.Stage.PREPARE:
					cur_value =
					    GameTools.calc_goal_value_prepare
					    (next, goal, this, counter);
					break;
				case Goal.Stage.MAIN:
					cur_value =
					    GameTools.calc_goal_value_main
					    (next, goal, this, counter);
					break;
				case Goal.Stage.DONE:
					cur_value =
					    GameTools.calc_goal_value_done
					    (next, goal, this, counter);
					break;
				case Goal.Stage.COMBINED:
					cur_value =
					    GameTools.calc_goal_value_combined
					    (next, goal, this, counter);
					break;
				case Goal.Stage.GREEDY:
					cur_value =
					    GameTools.calc_goal_value_greedy
					    (next, goal, this, counter);
					break;
				case Goal.Stage.CENTER:
					cur_value =
					    GameTools.calc_goal_value_center
					    (next, goal, this, counter);
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
//					next.board.value += forced_move_bonus;
				}
				else if (ok == 0)
				{
					int future_score =
					    moves_can_happen (null,
					    cur_move, next, true);
					if (future_score == NA)
					{
						return;
					}
					next.board.value += future_score -
					    next.board.score;
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
			if (best.board.score < next.board.score)
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
			bool put_fake = forced_allow_empty &&
			    !forced_tile.active &&
			    cur.board[row][col].empty;
			BoardCell temp_tile = forced_tile;
			if (put_fake)
			{
//				writeln ("!", row, ' ', col, ' ', forced_tile);
				swap (cur.board[row][col], temp_tile);
			}
			scope (exit)
			{
				if (put_fake)
				{
					swap (cur.board[row][col], temp_tile);
				}
			}
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
				cur.board.total++;
				scope (exit)
				{
					cur.board[row][col] = BoardCell.NONE;
					cur.board.total--;
				}
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
				return;
			}

			version (debug_forced)
			{
				writeln (">7:");
				stdout.flush ();
			}

			if (forced_restricted)
			{
				cur.tiles.dec_restricted (forced_tile);
				scope (exit)
				{
					cur.tiles.inc_restricted (forced_tile);
				}
				cur.board[row][col] = forced_tile;
				cur.board.total++;
				scope (exit)
				{
					cur.board[row][col] = BoardCell.NONE;
					cur.board.total--;
				}
				step_recur (cur, row, col,
				    vert, score, mult, vt,
				    flags + MULT_ACT);
				return;
			}

			cur.board.total++;
			scope (exit)
			{
				cur.board[row][col] = BoardCell.NONE;
				cur.board.total--;
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
					cur.tiles.dec (c);
					scope (exit)
					{
						cur.tiles.inc (c);
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
			return;
		}

		if (!cur.board[row][col].empty)
		{
			step_recur (cur, row, col,
			    vert, score, mult, vt, flags | FLAG_CONN);
			return;
		}
		cur.board.total++;
		scope (exit)
		{
			cur.board[row][col] = BoardCell.NONE;
			cur.board.total--;
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
	}

	void move_horizontal (ref GameState cur)
	{
		foreach (row; 0..Board.SIZE)
		{
			foreach (col; 0..Board.SIZE)
			{
				if (cur.board.suggest_start_move (row, col,
				    cur.tiles.rack.usable_total))
				{
					move_recur (cur, row, col, 0, 0, 1,
					    Trie.ROOT, 0);
				}
			}
		}
	}

	void perform_move (ref GameState cur, GameMove cur_move,
	    bool allow_empty)
	{
		BoardCell [] remember_forced_word = cur_move.word;
		bool remember_forced_allow_empty = allow_empty;
		swap (forced_word, remember_forced_word);
		swap (remember_forced_allow_empty, forced_allow_empty);
		scope (exit)
		{
			swap (forced_word, remember_forced_word);
			swap (remember_forced_allow_empty, forced_allow_empty);
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
			move_recur (cur, row, col, 0, 0, 1, Trie.ROOT,
			    allow_empty ? FLAG_CONN : 0);
		}
	}

	bool move_start_guided (ref GameState cur)
	{
		for (GameMove cur_move = moves_guide;
		    cur_move !is null;
		    cur_move = cur_move.chained_move)
		{
			int ok = is_move_present (cur, cur_move);
			if (ok == 1)
			{
			}
			else if (ok == 0)
			{
				int tiles_cursor = cur.tiles.cursor;
				int move_cursor = min (TOTAL_TILES,
				    cur_move.tiles_before + Rack.MAX_SIZE);
				if (move_cursor > tiles_cursor)
				{
					return false;
				}

				bool remember_forced_restricted = true;
				swap (forced_restricted,
				    remember_forced_restricted);
				scope (exit)
				{
					swap (forced_restricted,
					    remember_forced_restricted);
				}
				perform_move (cur, cur_move, false);
				return true;
			}
			else if (ok == NA)
			{
				enforce (false);
				break;
			}
			else
			{
				assert (false);
			}
		}
		return false;
	}

	void move_start (ref GameState cur)
	{
		if (moves_guide !is null)
		{
			if (move_start_guided (cur))
			{ // allow making the move after a free one
				assert (true);
//				return;
			}
		}
		move_horizontal (cur);
		if (!cur.board[Board.CENTER][Board.CENTER].empty ||
		    allow_mirror) // first move direction matters
		{
			cur.board.flip ();
			move_horizontal (cur);
			cur.board.flip ();
		}
	}

//	int moves_can_happen (GameMove first_inverted, GameMove second)
	int moves_can_happen (GameMove first_inverted, GameMove second,
	    GameState cur, bool allow_empty)
	{ // if GameState becomes a reference type, make a copy!
		bool remember_forced_imaginary = true;
		swap (forced_imaginary, remember_forced_imaginary);
		bool remember_forced_restricted = false;
		swap (forced_restricted, remember_forced_restricted);
		int remember_forced_cur = 0;
		swap (forced_cur, remember_forced_cur);
		scope (exit)
		{
			swap (forced_imaginary, remember_forced_imaginary);
			swap (forced_restricted, remember_forced_restricted);
			swap (forced_cur, remember_forced_cur);
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
			perform_move (cur, cur_move, allow_empty);
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
				return NA;
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
			perform_move (cur, cur_move, allow_empty);
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
				return NA;
			}
			cur = imaginary_result;
		}
		version (debug_forced)
		{
			writeln ("true!");
		}
		return imaginary_result.board.value;
	}

	Tuple !(GameMove, Problem) reduce_move_history
	    (alias pred) (GameMove history)
	{
		GameMove gm_res = null;
		Problem p_res = problem;
		char [] tiles;
		tiles.reserve (problem.contents.length);
		GameMove start = GameMove.invert (history);
		for (GameMove cur_move = start; cur_move !is null;
		    cur_move = cur_move.chained_move)
		{
			// TODO: parameterize!
			bool is_necessary =
			    (cur_move.word.length == Board.SIZE) ||
			    moves_can_happen (cur_move.chained_move, gm_res,
			    GameState (problem), false) == NA;

			is_necessary &= pred (cur_move);

			if (is_necessary)
			{
				GameMove temp = new GameMove (cur_move);
				temp.chained_move = gm_res;
				gm_res = temp;
			}

			foreach (t; cur_move.word)
			{
				if (t.active)
				{
					tiles ~= to !(char)
					    (((t.wildcard ? LET : t.letter) |
					    (is_necessary <<
					    TileBag.RESTRICTED_BIT)) + 'A');
				}
			}
		}
		enforce (tiles.length <= problem.contents.length);

		immutable char USED = '@';
		char [] temp = problem.contents.dup;
		reverse (tiles); // moves are considered in reverse order
		p_res.contents = "";
		foreach (ref c; temp)
		{
			if (c == '?')
			{
				c = to !(char) ('Z' + 1);
			}
		}
		foreach (ref c; temp)
		{
			bool found = false;
			foreach (ref t; tiles)
			{
				if (t == c || t == c + TileBag.IS_RESTRICTED)
				{
					p_res.contents ~= t;
					t = USED;
					found = true;
					break;
				}
			}
			if (!found)
			{
				p_res.contents ~= c;
			}
		}
		enforce (p_res.contents.length == problem.contents.length);

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
			cur_move.normalize (temp);
			imaginary_result = GameState ();
			imaginary_result.board.value = NA;
			perform_move (temp, cur_move, false);
			if (imaginary_result.board.value == NA)
			{
				enforce (false);
			}
			temp = imaginary_result;
		}
		return GameMove.invert (start);
	}

	bool suggest_check_board_tile (byte row, byte col, byte tile)
	{
		if (check_board[row][col].empty)
		{
			check_board[row][col].letter = tile;
			check_board.total++;
		}
		else if (check_board[row][col].letter != tile)
		{
			stderr.writeln ("check_board conflict ", row, ' ',
			    col, ' ', tile, ' ', check_board[row][col]);
			return false;
		}
		return true;
	}
	
	bool prepare_check_board ()
	{
		check_board = Board ();

		for (GameMove cur_move = moves_guide; cur_move !is null;
		    cur_move = cur_move.chained_move)
		{
			if (cur_move.is_flipped != check_board.is_flipped)
			{
				check_board.flip ();
			}
			byte row = cur_move.row;
			byte col = cur_move.col;
			foreach (pos; 0..cur_move.word.length)
			{
				if (!suggest_check_board_tile (row,
				    cast (byte) (col + pos),
				    cur_move.word[pos].letter))
				{
					return false;
				}
			}
		}

		foreach (cur_goal; goals)
		{
			if (cur_goal.is_flipped != check_board.is_flipped)
			{
				check_board.flip ();
			}
			byte row = cur_goal.row;
			byte col = cur_goal.col;
			foreach (pos; 0..cur_goal.word.length)
			{
				if (!suggest_check_board_tile (row,
				    cast (byte) (col + pos),
				    cur_goal.word[pos]))
				{
					return false;
				}
			}
		}

		check_board.normalize ();
		return true;
	}
	
	void go (int upper_limit, Keep keep)
	{
		if (!prepare_check_board ())
		{
			return;
		}

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
//		auto initial_state = GameState (problem, moves_guide);
		// TODO: use moves_guide and complete guide!
		auto initial_state = GameState (problem);
		gs.assumeSafeAppend ();
		gs[0] ~= initial_state;
		gsp.assumeSafeAppend ();
		gsp[0] ~= 0;
		resume_step = 0;
		go (to !(int) (problem.contents.length), keep);
		cleanup (keep);
	}

	void play_from (int new_bests_num, int new_depth,
	    ref GameState start_state, Keep keep = Keep.False)
	{
		bests_num = new_bests_num;
		depth = new_depth;

		auto initial_state = start_state;
		initial_state.tiles.update (problem.contents);
		int num = initial_state.board.total;

		gs = new GameState [] [problem.contents.length + 1];
		gsp = new int [] [problem.contents.length + 1];
		foreach (k, gsp_line; gsp[num + 1..$])
		{
			gs[k].reserve (bests_num);
			gsp[k].reserve (bests_num);
		}

		gs[num] ~= initial_state;
		gsp[num] ~= 0;

		resume_step = num;
		go (to !(int) (problem.contents.length), keep);
		cleanup (keep);
	}

	void resume (int new_bests_num, int new_depth,
	    int start_from = resume_step, Keep keep = Keep.False,
	    bool clear_value = false, bool was_virtual = false,
	    bool leave_only_best = false)
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
		if (leave_only_best)
		{
			resume_step = best.board.total;
			swap (gs[resume_step][0],
			    gs[resume_step][gsp[resume_step][0]]);
			gsp[resume_step][0] = 0;
			gs[resume_step].length = 1;
			gsp[resume_step].length = 1;
			foreach (k, ref gsp_line; gsp)
			{
				gs[k].length = (k == resume_step);
				gsp[k].length = (k == resume_step);
			}
		}
		else
		{
			resume_step = max (0,
			    min (start_from, resume_step) - 6);
		}

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
