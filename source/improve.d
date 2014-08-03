module improve;

import std.algorithm;
import std.range;
import std.stdio;

import board;
import game_move;
import game_state;
import general;
import problem;
import tile_bag;

GameMove [] build_moves_history (ref GameState cur)
{
	GameMove [] moves_history;

	for (GameMove cur_move = cur.closest_move; cur_move !is null;
	    cur_move = cur_move.chained_move)
	{
		auto temp_move = new GameMove (cur_move);
		temp_move.chained_move = null;
		moves_history ~= temp_move;
	}

	reverse (moves_history);

	return moves_history;
}

TargetBoard build_full_target_board (Problem problem, ref GameState cur)
{
	TargetBoard target_board;
	target_board = new TargetBoard (problem.contents.length);

	auto tiles_by_letter = new byte [] [LET + 1];

	auto temp = GameState (problem);
	foreach (num, tile; temp.tiles)
	{
		tiles_by_letter[tile & LET_MASK] ~= cast (byte) (num);
	}

	GameMove [] moves_history = build_moves_history (cur);

	foreach (ref cur_move; moves_history)
	{
		foreach (pos, ref tile; cur_move.word)
		{
			byte row = cur_move.row;
			byte col = cast (byte) (cur_move.col + pos);
			bool to_activate = (!cur_move.is_flipped ?
				    target_board.tile_number[row][col] :
				    target_board.tile_number[col][row]) == NA;
			if (to_activate)
			{
				tile.active = true;
			}
			if (tile.active)
			{
				auto let = tile.wildcard ? LET : tile.letter;
				assert (!tiles_by_letter[let].empty);
				byte num = tiles_by_letter[let].front;
				if (cur_move.word.length == Board.SIZE)
				{
					num += byte.min;
				}
				tiles_by_letter[let].popFront ();
				target_board.place (num, row, col,
				    cur_move.is_flipped);
			}
		}
	}

	return target_board;
}
