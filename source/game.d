module game;

import std.algorithm;
import std.stdio;

import board;
import game_move;
import game_state;
import general;
import goal;
import plan;
import play;
import problem;
import scoring;
import search.beam;
import tools;
import trie;

final class Game (DictClass)
{
	const DictClass dict;
	const Scoring scoring;
	Plan plan;

	int bias = 0;

	bool process_pre_dup (ref GameState cur)
	{
		// TODO: check forbidden goal positions here
 
		return true;
	}

	bool can_fill_tile (ref GameState cur, int row, int col, int limit)
	{
		if (cur.board.is_flipped)
		{
			swap (row, col);
		}

		if (!cur.board.is_flipped &&
		    row == 1 && 0 < col && col + 1 < Board.SIZE)
		{ // heuristic
			if (!cur.board[row + 1][col - 1].empty &&
			    cur.board[row + 1][col].empty &&
			    !cur.board[row + 1][col + 1].empty)
			{
				return false;
			}
		}

		if (!cur.board.is_flipped &&
		    row == Board.SIZE - 2 && 0 < col && col + 1 < Board.SIZE)
		{ // heuristic
			if (!cur.board[row - 1][col - 1].empty &&
			    cur.board[row - 1][col].empty &&
			    !cur.board[row - 1][col + 1].empty)
			{
				return false;
			}
		}

		if (cur.board.is_flipped &&
		    col == 1 && 0 < row && row + 1 < Board.SIZE)
		{ // heuristic
			if (!cur.board[row - 1][col + 1].empty &&
			    cur.board[row][col + 1].empty &&
			    !cur.board[row + 1][col + 1].empty)
			{
				return false;
			}
		}

		if (cur.board.is_flipped &&
		    col == Board.SIZE - 2 && 0 < row && row + 1 < Board.SIZE)
		{ // heuristic
			if (!cur.board[row - 1][col - 1].empty &&
			    cur.board[row][col - 1].empty &&
			    !cur.board[row + 1][col - 1].empty)
			{
				return false;
			}
		}

		int s_row = row;
		while (s_row > 0 &&
		    !cur.board[s_row - 1][col].empty)
		{
			s_row--;
		}

		int t_row = row;
		while (t_row + 1 < Board.SIZE &&
		    !cur.board[t_row + 1][col].empty)
		{
			t_row++;
		}

		int s_col = col;
		while (s_col > 0 &&
		    !cur.board[row][s_col - 1].empty)
		{
			s_col--;
		}

		int t_col = col;
		while (t_col + 1 < Board.SIZE &&
		    !cur.board[row][t_col + 1].empty)
		{
			t_col++;
		}

		if (t_row - s_row < 2 && t_col - s_col < 2)
		{
			return true;
		}

//		writeln (s_row, ' ', s_col, ' ', t_row, ' ', t_col);
//		foreach (ch; "EAIOTLSUD")
//		foreach (ch; "EAIONRTLSUDG")
//		foreach (ch; "EAIONRTLSUDGBCMPFHVWY")
		auto mask = cur.tiles.get_next_mask (limit);
		foreach (ch; 0..LET)
		{
			if (!(mask & (1 << ch)))
			{
				continue;
			}
			BoardCell let = cast (byte) (ch);
			swap (let, cur.board[row][col]);
			scope (exit)
			{
				swap (let, cur.board[row][col]);
			}

			int vh = DictClass.ROOT;
			foreach (cur_col; s_col..t_col + 1)
			{
				vh = dict.contents[vh].next
				    (cur.board[row][cur_col]);
				if (vh == NA)
				{
					break;
				}
			}
			if (s_col != t_col)
			{
				if (vh == NA || !dict.contents[vh].word)
				{
					continue;
				}
			}
			
			int vv = DictClass.ROOT;
			foreach (cur_row; s_row..t_row + 1)
			{
				vv = dict.contents[vv].next
				    (cur.board[cur_row][col]);
				if (vv == NA)
				{
					break;
				}
			}
			if (s_row != t_row)
			{
				if (vv == NA || !dict.contents[vv].word)
				{
					continue;
				}
			}

			return true;
		}

		return false;
	}

	int put_value (ref GameState cur,
	    int value, int row, int col, bool is_flipped)
	{
		if (cur.board.is_flipped != is_flipped)
		{
			swap (row, col);
		}

		int s_row = row;
		while (s_row > 0 &&
		    !cur.board[s_row - 1][col].empty)
		{
			s_row--;
			int letter = (cur.board[s_row][col].wildcard ? LET :
			    cur.board[s_row][col].letter);
		}

		int t_row = row;
		while (t_row + 1 < Board.SIZE &&
		    !cur.board[t_row + 1][col].empty)
		{
			t_row++;
			int letter = (cur.board[t_row][col].wildcard ? LET :
			    cur.board[t_row][col].letter);
		}

		int s_col = col;
		while (s_col > 0 &&
		    !cur.board[row][s_col - 1].empty)
		{
			s_col--;
			int letter = (cur.board[row][s_col].wildcard ? LET :
			    cur.board[row][s_col].letter);
		}

		int t_col = col;
		while (t_col + 1 < Board.SIZE &&
		    !cur.board[row][t_col + 1].empty)
		{
			t_col++;
			int letter = (cur.board[row][t_col].wildcard ? LET :
			    cur.board[row][t_col].letter);
		}

		BoardCell cur_cell =
		    (cur.board.is_flipped == plan.check_board.is_flipped) ?
		    plan.check_board[row][col] : plan.check_board[col][row];
		GameMove check_move;
		if (s_col < t_col)
		{
			check_move = new GameMove ();
			check_move.start_at
			    (cast (byte) (row), cast (byte) (s_col));
			check_move.is_flipped = cur.board.is_flipped;
			check_move.word.length = t_col - s_col + 1;
			foreach (cur_col; s_col..t_col + 1)
			{
				check_move.word[cur_col - s_col] =
				    cur.board[row][cur_col];
			}
			check_move.word[col - s_col] =
			    cur_cell | BoardCell.IS_ACTIVE;
		}
		else if (s_row < t_row)
		{
			check_move = new GameMove ();
			check_move.start_at
			    (cast (byte) (s_row), cast (byte) (col));
			check_move.is_flipped = !cur.board.is_flipped;
			check_move.word.length = t_row - s_row + 1;
			foreach (cur_row; s_row..t_row + 1)
			{
				check_move.word[cur_row - s_row] =
				    cur.board[cur_row][col];
			}
			check_move.word[row - s_row] =
			    cur_cell | BoardCell.IS_ACTIVE;
		}
		
		if (check_move !is null)
		{
			GameState temp = cur;
			play_move !(DictClass, RackUsage.Ignore)
			    (dict, scoring, temp, check_move);
			if (temp.board.score == NA)
			{
				return NA;
			}
			return temp.board.score - cur.board.score;
		}
		else
		{
			return 0;
		}
	}

	int calc_value (ref GameState cur)
	{
		int res = cur.board.score;

		// add active tiles value
		immutable int ACTIVE_TILE_VALUE = 50;
		if (cur.tiles.rack.active >= 0)
		{ // if not ignored
			res += cur.tiles.rack.active * ACTIVE_TILE_VALUE;
		}

		// add individual scores for active tiles
		foreach (ref c; cur.tiles.rack.contents)
		{
			if (c.empty)
			{
				break;
			}

			res += c.num * scoring.tile_value[c.letter];
		}

		// add bias value
		res += GameTools.bias_value (cur, bias);

		// TODO: add goal values here
/*
		TileCounter counter;
		foreach (goal; goals)
		{
			int cur_value = GameTools.calc_goal_value
			    (cur, goal, ???, counter);
			if (cur_value == NA)
			{
				return NA;
			}
			res += cur_value;
		}
*/

		// TODO: add moves guide values here

		if (plan !is null)
		{
			// check goal moves
			GameState temp = cur;
			int prev_score = temp.board.score;
			foreach (goal_move; plan.goal_moves)
			{
				play_move !(DictClass, RackUsage.Ignore)
				    (dict, scoring, temp, goal_move);
				if (temp.board.score == NA)
				{
					return NA;
				}

				// add value for each present goal letter
				static immutable int LETTER_BONUS = 100;
//				bool goal_achieved = true;
				foreach (pos; 0..goal_move.word.length)
				{
					if (cur.board.is_flipped ==
					    goal_move.is_flipped)
					{
						if (!cur.board
						    [goal_move.row]
						    [goal_move.col + pos]
						    .empty)
						{
							res += LETTER_BONUS;
						}
//						else
//						{
//							goal_achieved = false;
//						}
					}
					else
					{
						if (!cur.board
						    [goal_move.col + pos]
						    [goal_move.row]
						    .empty)
						{
							res += LETTER_BONUS;
						}
//						else
//						{
//							goal_achieved = false;
//						}
					}
				}

/*
				// add value for tiles near border goals
				static immutable int NEAR_TILE_BONUS = 15;
				if (!goal_achieved)
				{
					int near_row = goal_move.row;
					if (!(goal_move.word.length ==
					    Board.SIZE &&
					    !goal_move.is_flipped))
					{
						continue;
					}
					if (near_row == 0)
					{
						near_row++;
					}
					else if (near_row == Board.SIZE - 1)
					{
						near_row--;
					}
					else
					{
						continue;
					}
					foreach (pos; 0..Board.SIZE)
					{
						if (cur.board.is_flipped ==
						    goal_move.is_flipped)
						{
							if (!cur.board
							    [near_row][pos]
							    .empty)
							{
								res += NEAR_TILE_BONUS;
							}
						}
						else
						{
							if (!cur.board
							    [pos][near_row]
							    .empty)
							{
								res += NEAR_TILE_BONUS;
							}
						}
					}
				}
*/
			}
			res += temp.board.score - prev_score;

			// check checkpoint possibility
			foreach (check_point; plan.check_points)
			{
				if (check_point.row != 0 &&
				    check_point.row != Board.SIZE - 1)
				{ // leave only border goal checkpoints
					continue;
				}

				if (!cur.board.is_flipped)
				{
					if (!cur.board[check_point.row]
					    [check_point.col].empty ||
					    (check_point.col > 0 &&
					    !cur.board[check_point.row]
					    [check_point.col - 1].empty) ||
					    (check_point.col <
					    Board.SIZE - 1 &&
					    !cur.board[check_point.row]
					    [check_point.col + 1].empty))
					{ // also look at two adjacent cells
						continue;
					}
				}
				else
				{
					if (!cur.board[check_point.col]
					    [check_point.row].empty ||
					    (check_point.col > 0 &&
					    !cur.board[check_point.col - 1]
					    [check_point.row].empty) ||
					    (check_point.col <
					    Board.SIZE - 1 &&
					    !cur.board[check_point.col + 1]
					    [check_point.row].empty))
					{ // also look at two adjacent cells
						continue;
					}
				}

				int row = check_point.row;
				// move away from border row
				if (row == 0)
				{
					row++;
				}
				if (row == Board.SIZE - 1)
				{
					row--;
				}

				if (!can_fill_tile (temp, row,
				    check_point.col, check_point.tile))
				{
					return NA;
				}
			}

			// add checkpoint values
/*
			static immutable int WHOLE_VALUE = 10_000;
			static immutable int MAX_SUB = 12;
			static immutable int TO_SUB = 4;
//			static immutable int WHOLE_VALUE = 400;
//			static immutable int MAX_SUB = WHOLE_VALUE;
//			static immutable int TO_SUB = WHOLE_VALUE / 8;
			int sub = 0;
			foreach (check_point; plan.check_points)
			{
				int d = cur.board.distance_to_covered
				    (check_point.row, check_point.col, false);
				if (d == 2)
				{ // tweak: prevent being stuck
					d++;
				}
				if (d > 0)
				{ // tweak: actual put should happen anyway
					d--;
				}
				res += (WHOLE_VALUE >> sub) >> d;
//				res += (WHOLE_VALUE - sub) >> d;
				if (sub > 0 || d > 1)
				{
					sub = min (MAX_SUB, sub + TO_SUB);
				}
			}
*/
			int sub = 0;
			int rows_visited_mask = 0;
			foreach (check_point; plan.check_points)
			{
//				int d = cur.board.distance_to_covered_adjacent
//				int d = cur.board.distance_to_covered
//				int d = cur.board.distance_to_covered_no_horiz
//				    (check_point.row, check_point.col, false);
				bool is_lone_point = !(check_point.row == 0 ||
				    check_point.row == Board.CENTER ||
				    check_point.row == Board.SIZE - 1);
				int d;
				if (is_lone_point)
				{
					d = cur.board
					    .distance_to_covered
					    (check_point.row, check_point.col,
					    false);
				}
				else
				{
					d = cur.board
					    .distance_to_covered_no_horiz
					    (check_point.row, check_point.col,
					    false);
				}
				int d2 = d;
				if (check_point.row - 2 >= 0)
				{
					d2 = min (d2,
					    cur.board.distance_to_covered
					    (check_point.row - 2,
					    check_point.col, false));
				}
				if (check_point.row + 2 < Board.SIZE)
				{
					d2 = min (d2,
					    cur.board.distance_to_covered
					    (check_point.row + 2,
					    check_point.col, false));
				}
				if (is_lone_point)
				{
					d2 = d;
				}
//				d = max (0, d - 1);
//				d2 = max (0, d2 - 1);
				int time_left = check_point.tile -
				    cur.board.total;
				time_left = max (time_left, 0);
				time_left = min (time_left, 32);
				int value = check_point.value *
				    (16 + 32 - time_left);
				if (!is_lone_point &&
				    rows_visited_mask & (1 << check_point.row))
				{
//					value *= 1;
					value *= 2;
				}
				rows_visited_mask |= 1 << check_point.row;
				if (check_point.row == Board.CENTER)
				{
					value /= 4;
				}
				res += (value >> sub) * ((20 - d) *
				    (20 - d2)) /
				    (480 * 1); // 480 is a single-tile value
//				if (d > 0)
				if (!is_lone_point && d > 1)
				{
//					sub = min (1, sub + 1);
					sub = min (2, sub + 1);
				}
/*
				int value = 1024 * (8 + 32) / (8 + time_left);
				res += (value >> sub) >> d;
				if (d > 0)
				{
					sub = max (2, sub + 1);
				}
*/
				if (is_lone_point && d == 1)
				{
					int point_value = put_value (cur,
					    global_scoring.tile_value
					    [cur.tiles[check_point.tile] &
					    LET_MASK], check_point.row,
					    check_point.col, false);
					if (point_value == NA)
					{
						return NA;
					}
					res += point_value;
				}
			}
		}

//		return res + cur.board.score;
		return res;
	}

	bool process_post_dup (ref GameState cur)
	{
//		cur.board.normalize ();
		cur.board.value = calc_value (cur);
		if (cur.board.value == NA)
		{
			return false;
		}

		return true;
	}

	Play !(DictClass) play_regular ()
	{
		return Play !(DictClass) (dict, scoring);
	}

	CompoundPlay !(DictClass) play_compound ()
	{
		return CompoundPlay !(DictClass) (dict, scoring,
		    &plan.check_board);
	}

	this (const DictClass new_dict, const Scoring new_scoring,
	    Plan new_plan = null)
	{
		dict = new_dict;
		scoring = new_scoring;
		plan = new_plan;
	}
}

GameState game_beam_search (GameStateRange, DictClass)
    (GameStateRange init_states, Game !(DictClass) game, int width, int depth)
{
	if (game.plan is null)
	{
		return beam_search !(TOTAL_TILES,
		    (const ref a) => a.board.total, // get_level
		    (const ref GameState a) => a.get_board_hash (), // get_hash
		    (ref a) => game.play_regular () (a), // gen_next
		    (ref a) => game.process_pre_dup (a), // process_pre_dup
		    (ref a) => game.process_post_dup (a), // process_post_dup
		    (const ref a, const ref b) =>
		        a.board.score - b.board.score, // cmp_best
//		    (ref a, ref b) => (a.board.score > b.board.score) -
//		        (a.board.score < b.board.score), // cmp_best
		    (const ref a, const ref b) =>
		        (a.board.value - b.board.value) ?
		        (a.board.value - b.board.value) :
		        (a.board.score - b.board.score), // cmp_inner
//		        a.board.value - b.board.value, // cmp_inner
//		    (ref a, ref b) => (a.board.value > b.board.value) -
//		        (a.board.value < b.board.value), // cmp_inner
		    GameState, GameStateRange)
		    (init_states, width, depth);
	}
	else
	{
		return beam_search !(TOTAL_TILES,
		    (const ref a) => a.board.total, // get_level
		    (const ref GameState a) => a.get_board_hash (), // get_hash
		    (ref a) => game.play_compound ()
		        (a, game.plan.goal_moves), // gen_next
		    (ref a) => game.process_pre_dup (a), // process_pre_dup
		    (ref a) => game.process_post_dup (a), // process_post_dup
		    (const ref a, const ref b) =>
		        a.board.score - b.board.score, // cmp_best
//		    (ref a, ref b) => (a.board.score > b.board.score) -
//		        (a.board.score < b.board.score), // cmp_best
		    (const ref a, const ref b) =>
		        (a.board.value - b.board.value) ?
		        (a.board.value - b.board.value) :
		        (a.board.score - b.board.score), // cmp_inner
//		        a.board.value - b.board.value, // cmp_inner
//		    (ref a, ref b) => (a.board.value > b.board.value) -
//		        (a.board.value < b.board.value), // cmp_inner
		    GameState, GameStateRange)
		    (init_states, width, depth);
	}
}

unittest
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
	auto s = new Scoring ();

	void test_regular ()
	{
		auto game = new Game !(Trie) (t, s);
		auto cur = GameState (Problem ("?:", "ABCDEFGH"));
		auto next = game_beam_search ([cur], game, 100, 1);
//		writeln (next);
		assert (next.board.score >= 50 && next.board.value >= 50);
//		assert (next.board.score == 53 && next.board.value == 53);
	}

	void test_planned ()
	{
		auto p = Problem ("?:",
		    "AELSNEARTOAIE" ~ "AELSNRAETOAIE" ~
		    "OXYPHENBUTAZONE");
		auto goal = new Goal ("OXYPhenButaZonE", 0, 0, false);
		auto plan = new Plan (p, [goal]);
//		writeln (plan);
		auto game = new Game !(Trie) (t, s, plan);
		auto cur = GameState (plan.problem);
		cur.tiles.target_board = plan.target_board;
		auto next = game_beam_search ([cur], game, 10, 0);
//		writeln (next);
		assert (next.board.score >= 1400);
//		assert (next.board.score == 1693);
	}

	void test_planned_wildcard_start ()
	{
		auto p = Problem ("?:",
		    "AELSNEARTOAIE" ~ "AELSNRAUETOAIE" ~
		    "OXYP?ENBUTAZONE");
		auto goal = new Goal ("OXYPhenButaZonE", 0, 0, false);
		auto plan = new Plan (p, [goal]);
//		writeln (plan);
		auto game = new Game !(Trie) (t, s, plan);
		auto cur = GameState (plan.problem);
		cur.tiles.target_board = plan.target_board;
		auto next = game_beam_search ([cur], game, 10, 0);
		writeln (next);
		assert (next.board.score >= 1250);
	}


	void test_planned_wildcard_final ()
	{
		auto p = Problem ("?:",
		    "AELSNEARTOAIE" ~ "AELSNRAETOAIE" ~
		    "OXYPHENBUTA?ONE");
		auto goal = new Goal ("OXYPhenButaZonE", 0, 0, false);
		auto plan = new Plan (p, [goal]);
		writeln (plan);
		auto game = new Game !(Trie) (t, s, plan);
		auto cur = GameState (plan.problem);
		cur.tiles.target_board = plan.target_board;
		auto next = game_beam_search ([cur], game, 10, 0);
		writeln (next);
		assert (next.board.score >= 800);
	}

	void test_planned_wildcard_both ()
	{
		auto p = Problem ("?:",
		    "AELSNEARTOAIE" ~ "AELSNPRAETOAIE" ~
		    "OXYP?ENBUTA?ONE");
		auto goal = new Goal ("OXYPhenButaZonE", 0, 0, false);
		auto plan = new Plan (p, [goal]);
//		writeln (plan);
		auto game = new Game !(Trie) (t, s, plan);
		auto cur = GameState (plan.problem);
		cur.tiles.target_board = plan.target_board;
		auto next = game_beam_search ([cur], game, 10, 0);
		writeln (next);
		assert (next.board.score >= 650);
	}

	void test_planned_wildcard_many ()
	{
		auto p = Problem ("?:",
		    "AELSNEARTOAIE" ~ "?ELABSNECARTOAI?" ~
		    "OXYP?ENBUTA?ONE");
		auto goal = new Goal ("OXYPhenButaZonE", 0, 0, false);
		auto plan = new Plan (p, [goal]);
//		writeln (plan);
		auto game = new Game !(Trie) (t, s, plan);
		auto cur = GameState (plan.problem);
		cur.tiles.target_board = plan.target_board;
		auto next = game_beam_search ([cur], game, 10, 0);
		writeln (next);
		assert (next.board.score >= 650);
	}

	test_regular ();
	test_planned ();
	test_planned_wildcard_start ();
	test_planned_wildcard_final ();
	test_planned_wildcard_both ();
	test_planned_wildcard_many ();
}
