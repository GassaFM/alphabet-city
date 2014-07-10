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

	int calc_value (ref GameState cur)
	{
		int res = cur.board.score;

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
			}
			res += temp.board.score - prev_score;

			// add checkpoint values
			static immutable int WHOLE_VALUE = 10000;
			static immutable int MAX_SUB = 12;
			static immutable int TO_SUB = 4;
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
				if (sub > 0 || d > 1)
				{
					sub = min (WHOLE_VALUE, sub + TO_SUB);
				}
			}
		}

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
		        a.board.value - b.board.value, // cmp_inner
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
		        a.board.value - b.board.value, // cmp_inner
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
		auto cur = GameState (Problem ("?:", "ABCDEFG"));
		auto next = game_beam_search ([cur], game, 100, 1);
//		writeln (next);
		assert (next.board.score == 53 && next.board.value == 53);
	}

	void test_planned ()
	{
		auto p = Problem ("?:",
		    "AELSNEARTOAIE" ~ "AELSNRAETOAIE" ~
		    "OXYPHENBUTAZONE");
		auto goal = new Goal ("OXYPhenButaZonE", 0, 0, false);
		auto plan = new Plan (p, [goal]);
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
