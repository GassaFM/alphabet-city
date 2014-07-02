module game;

import std.stdio;

import board;
import game_move;
import game_state;
import general;
import play;
import problem;
import scoring;
import search.beam;
import tools;
import trie;

class Game (DictClass)
{
	DictClass dict;
	Scoring scoring;

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

	this (DictClass new_dict, Scoring new_scoring)
	{
		dict = new_dict;
		scoring = new_scoring;
	}
}

GameState game_beam_search (GameStateRange, DictClass)
    (GameStateRange init_states, Game !(DictClass) game, int width, int depth)
{
	return beam_search !(TOTAL_TILES,
	    (ref a) => a.board.total, // get_level
	    (ref GameState a) => a.get_board_hash (), // get_hash
	    (ref a) => game.play_regular () (a), // gen_next
	    (ref a) => game.process_pre_dup (a), // process_pre_dup
	    (ref a) => game.process_post_dup (a), // process_post_dup
	    (ref a, ref b) => (a.board.score > b.board.score) -
	        (a.board.score < b.board.score), // cmp_best
	    (ref a, ref b) => (a.board.value > b.board.value) -
	        (a.board.value < b.board.value), // cmp_inner
	    GameState, GameStateRange)
	    (init_states, width, depth);
}

unittest
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
	auto s = new Scoring ();
	auto game = new Game !(Trie) (t, s);
	auto cur = GameState (Problem ("?:", "ABCDEFG"));
	auto next = game_beam_search ([cur], game, 100, 1);
	writeln (next);
	stdout.flush ();
//	assert (next.board.score == 50 && next.board.value == 50);
}
