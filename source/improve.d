module improve;

import std.algorithm;
import std.conv;
import std.exception;
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

GameMove necessary_move (bool reduce_single_move,
    Dict, GameMoveRange1, GameMoveRange2)
    (Problem problem, Dict dict, GameMove cur_move,
    GameMoveRange1 pre_moves_range, GameMoveRange2 post_moves_range)
    if (isInputRange !(GameMoveRange1) &&
    is (Unqual !(ElementType !(GameMoveRange1)) == GameMove) &&
    isInputRange !(GameMoveRange2) &&
    is (Unqual !(ElementType !(GameMoveRange2)) == GameMove))
{
	if (cur_move.word.length == Board.SIZE)
	{ // fully needed
		return cur_move;
	}

	auto pre_moves = pre_moves_range.array;
	auto post_moves = post_moves_range.array;
	auto start = GameState (problem);
	play_moves_sequence !(Trie, RackUsage.Fake)
	    (dict, global_scoring, start, pre_moves);
	enforce (start.board.score != NA);

	auto finish = start;
	play_moves_sequence !(Trie, RackUsage.Fake)
	    (dict, global_scoring, finish, post_moves);
	if (finish.board.score != NA)
	{ // not needed
		return null;
	}

	static if (reduce_single_move)
	{
		auto res_move = new GameMove (cur_move);
		foreach (lo; 0..cur_move.word.length)
		{
			foreach (hi; lo + 1..cur_move.word.length + 1)
			{
				GameMove temp_move = new GameMove (cur_move);
				temp_move.score = 0;
				if (hi - lo > 1)
				{
					temp_move.col += lo;
					temp_move.word =
					    temp_move.word[lo..hi];
				}
				else
				{
					byte cur_row = temp_move.row;
					byte cur_col = to !(byte)
					    (temp_move.col + lo);
					if (temp_move.is_flipped !=
					    start.board.is_flipped)
					{
						start.board.flip ();
					}
					byte row_lo = cur_row;
					while (row_lo > 0 &&
					    !start.board[row_lo - 1][cur_col]
					    .empty)
					{
						row_lo--;
					}
					byte row_hi = cur_row;
					while (row_hi + 1 < Board.SIZE &&
					    !start.board[row_hi + 1][cur_col]
					    .empty)
					{
						row_hi++;
					}
					if (row_lo == row_hi)
					{
						continue;
					}
					row_hi++;
					start.board.flip ();
					temp_move.is_flipped ^= true;
					temp_move.row = cur_col;
					temp_move.col = row_lo;
					temp_move.word = start.board
					    .contents[cur_col][row_lo..row_hi]
					    .dup;
					temp_move.word[cur_row - row_lo] =
					    cur_move.word[lo];
				}

				auto temp = start;
//				writeln (temp_move);
				play_move !(Trie, RackUsage.Fake)
				    (dict, global_scoring, temp, temp_move);
				if (temp.board.score == NA)
				{ // can not perform temp_move
					continue;
				}
//				writeln ("here");
				play_moves_sequence !(Trie, RackUsage.Fake)
				    (dict, global_scoring, temp, post_moves);
				if (temp.board.score == NA)
				{ // can not perform post_moves
					continue;
				}

				if (res_move.word.length >
				    temp_move.word.length)
				{ // shorter than previous result
					res_move = temp_move;
				}
			}
		}
		return res_move;
	}
	else
	{
		return cur_move;
	}
}

Guide reduce_guide (Dict) (Guide guide,
    Problem problem, ref GameState cur, Dict dict)
{
	TargetBoard target_board;
	target_board = new TargetBoard (problem.contents.length);
	Board check_board;

	GameMove [] reduced_moves_history;

	foreach_reverse (num, ref loop_move; guide.moves_history)
	{
		auto cur_move = necessary_move !(true)
		    (problem, dict, loop_move,
		    guide.moves_history[0..num], reduced_moves_history.retro);
		if (cur_move is null)
		{
			continue;
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
