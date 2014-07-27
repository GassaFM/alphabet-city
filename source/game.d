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
	DictClass dict;
	Scoring scoring;
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
		{
			if (!cur.board[row + 1][col - 1].empty &&
			    cur.board[row + 1][col].empty &&
			    !cur.board[row + 1][col + 1].empty)
			{
				return false;
			}
		}

		if (!cur.board.is_flipped &&
		    row == Board.SIZE - 2 && 0 < col && col + 1 < Board.SIZE)
		{
			if (!cur.board[row - 1][col - 1].empty &&
			    cur.board[row - 1][col].empty &&
			    !cur.board[row - 1][col + 1].empty)
			{
				return false;
			}
		}

		if (cur.board.is_flipped &&
		    col == 1 && 0 < row && row + 1 < Board.SIZE)
		{
			if (!cur.board[row - 1][col + 1].empty &&
			    cur.board[row][col + 1].empty &&
			    !cur.board[row + 1][col + 1].empty)
			{
				return false;
			}
		}

		if (cur.board.is_flipped &&
		    col == Board.SIZE - 2 && 0 < row && row + 1 < Board.SIZE)
		{
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
//		foreach (ch; 'A'..'Z' + 1)
		// TODO: Get mask from cur of next 16 | up to tile_num tiles.
		// Only non-restricted.
		// That should be returned by a TileBag function.
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

	int calc_value (ref GameState cur)
	{
		int res = cur.board.score;

		// add active tiles value
		immutable int ACTIVE_TILE_VALUE = 50;
		if (cur.tiles.rack.active >= 0)
		{ // if not ignored
			res += cur.tiles.rack.active * ACTIVE_TILE_VALUE;
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
					}
				}

				// add value for tiles near border goals
				static immutable int NEAR_TILE_BONUS = 15;
				int near_row = goal_move.row;
				if (!(goal_move.word.length == Board.SIZE &&
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
						if (!cur.board[near_row][pos]
						    .empty)
						{
							res +=
							    NEAR_TILE_BONUS;
						}
					}
					else
					{
						if (!cur.board[pos][near_row]
						    .empty)
						{
							res +=
							    NEAR_TILE_BONUS;
						}
					}
				}
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
					    [check_point.col].empty)
					{
						continue;
					}
				}
				else
				{
					if (!cur.board[check_point.col]
					    [check_point.row].empty)
					{
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
				int d = cur.board.distance_to_covered_no_horiz
				    (check_point.row, check_point.col, false);
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
//				d = max (0, d - 1);
//				d2 = max (0, d2 - 1);
				int time_left = check_point.tile -
				    cur.board.total;
				time_left = min (time_left, 0);
				time_left = max (time_left, 32);
				int value = check_point.value *
				    (8 + 32 - time_left);
				if (rows_visited_mask & (1 << check_point.row))
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
				if (d > 1)
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

	this (DictClass new_dict, Scoring new_scoring, Plan new_plan = null)
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
		writeln (plan);
		auto game = new Game !(Trie) (t, s, plan);
		auto cur = GameState (plan.problem);
		cur.tiles.target_board = plan.target_board;
		auto next = game_beam_search ([cur], game, 10, 0);
//		writeln (next);
		assert (next.board.score >= 1400);
//		assert (next.board.score == 1693);
	}

	test_regular ();
	test_planned ();
}
