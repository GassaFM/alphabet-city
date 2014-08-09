module improve;

import std.algorithm;
import std.range;
import std.stdio;

import board;
import game_move;
import game_state;
import general;
import play;
import problem;
import scoring;
import tile_bag;
import trie;

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

alias Guide = Tuple !(TargetBoard, "target_board", Board, "check_board",
    GameMove [], "moves_history");

Guide build_full_guide (Problem problem, ref GameState cur)
{
	TargetBoard target_board;
	target_board = new TargetBoard (problem.contents.length);
	Board check_board;

	auto tiles_by_letter = new byte [] [LET + 1];
	byte tiles_before = 0;

	auto temp = GameState (problem);
	foreach (num, tile; temp.tiles)
	{
		tiles_by_letter[tile & LET_MASK] ~= cast (byte) (num);
	}

	GameMove [] moves_history = build_moves_history (cur);

	foreach (ref cur_move; moves_history)
	{
		if (check_board.is_flipped != cur_move.is_flipped)
		{
			check_board.flip ();
		}
		cur_move.tiles_before = tiles_before;
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
				tiles_before++;
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
				check_board[row][col] =
				    tile & ~BoardCell.IS_ACTIVE;
			}
		}
	}
	check_board.normalize_flip ();

	return Guide (target_board, check_board, moves_history);
}

Guide reduce_guide (Dict) (Guide guide,
    Problem problem, ref GameState cur, Dict dict)
{
	TargetBoard target_board;
	target_board = new TargetBoard (problem.contents.length);
	Board check_board;

	GameMove [] reduced_moves_history;

	foreach_reverse (num, ref cur_move; guide.moves_history)
	{
		if (cur_move.word.length != Board.SIZE)
		{
			auto temp = GameState (problem);
			play_moves_sequence !(Trie, RackUsage.Fake)
			    (dict, global_scoring, temp,
			    guide.moves_history[0..num]);
			assert (temp.board.score != NA);
			play_moves_sequence !(Trie, RackUsage.Fake)
			    (dict, global_scoring, temp,
			    reduced_moves_history.retro ());
			if (temp.board.score != NA)
			{
				continue;
			}
		}

		reduced_moves_history ~= cur_move;
		foreach (pos, ref tile; cur_move.word)
		{
			byte row = cur_move.row;
			byte col = cast (byte) (cur_move.col + pos);

			byte tile_pos = (!cur_move.is_flipped ?
			    guide.target_board.tile_number[row][col] :
			    guide.target_board.tile_number[col][row]);
			assert (tile_pos != NA);
			assert ((0 <= tile_pos &&
			    tile_pos < problem.contents.length) ||
			    (0 <= tile_pos - byte.min &&
			    tile_pos - byte.min < problem.contents.length));
			target_board.place
			    (tile_pos, row, col, cur_move.is_flipped);

			if (cur_move.is_flipped)
			{
				swap (row, col);
			}
			check_board[row][col] =
			    guide.check_board[row][col];
		}
	}

	reverse (reduced_moves_history);

	return Guide (target_board, check_board, reduced_moves_history);
}
