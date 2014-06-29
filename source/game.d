module game;

import board;
import game_move;
import game_state;
import general;
import scoring;
import search.beam;
import trie;

class Game (DictClass)
{
	enum MoveGenerator {Rack, Word};

	DictClass dict;
	Scoring scoring;

	this (DictClass new_dict, Scoring new_scoring)
	{
		dict = new_dict;
		scoring = new_scoring;
	}
}

GameState beam_search (GameStateRange)
    (GameStateRange init_states, Game game, int width, int depth)
{
	return beam_search !(TOTAL_TILES,
	    a => a.num, // get_level
	    a => a.board.contents_hash[0], // get_hash
	    a => game.play (a), // gen_next
	    a => game.check_good_pre_dup (a), // check_good_pre_dup
	    a => game.check_good_post_dup (a), // check_good_post_dup
	    (a, b) => (a.score > b.score) - (a.score < b.score), // cmp_best
	    (a, b) => (a.value > b.value) - (a.value < b.value)) // cmp_inner
	    (init_states, width, depth);
}
