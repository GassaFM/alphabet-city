module game;

import board;
import game_move;
import game_state;
import general;
import play;
import scoring;
import search.beam;
import trie;

class Game (DictClass)
{
	DictClass dict;
	Scoring scoring;

	Play play_regular;

	int bias = 0;

	bool process_pre_dup (ref GameState cur)
	{
		auto tiles_saved = cur.tiles;
		cur.tiles.rack.normalize ();
		cur.tiles.fill_rack ();
		scope (exit)
		{
			cur.tiles = tiles_saved;
		}

		// TODO: check forbidden goal positions here

		return true;
	}

	int calc_value (ref GameState cur)
	{
		int res = cur.board.score;

		// add bias value
		cur.board.value += GameTools.bias_value (cur, bias);

		// TODO: add goal values here
/*
		TileCounter counter;
		foreach (goal; goals)
		{
			int cur_value = GameTools.calc_goal_value
			    (next, goal, this, counter);
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
		cur.board.normalize ();
		cur.board.value = calc_value (cur);
		if (cur.board.value == NA)
		{
			return false;
		}

		return true;
	}

	private this ()
	{
		play_regular = new Play (dict, scoring);
	}

	this (DictClass new_dict, Scoring new_scoring)
	{
		dict = new_dict;
		scoring = new_scoring;

		this ();
	}
}

GameState beam_search (GameStateRange)
    (GameStateRange init_states, Game game, int width, int depth)
{
	return beam_search !(TOTAL_TILES,
	    a => a.num, // get_level
	    a => a.board.contents_hash[0], // get_hash
	    a => game.play_regular (a), // gen_next
	    a => game.process_pre_dup (a), // process_pre_dup
	    a => game.process_post_dup (a), // process_post_dup
	    (a, b) => (a.score > b.score) - (a.score < b.score), // cmp_best
	    (a, b) => (a.value > b.value) - (a.value < b.value)) // cmp_inner
	    (init_states, width, depth);
}

unittest
{
}
