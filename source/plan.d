module plan;

import std.algorithm;
import std.conv;
import std.format;
import std.range;
import std.stdio;

import board;
import game_move;
import general;
import goal;
import problem;
import scoring;
import tile_bag;
import trie;

struct CheckPoint
{
	byte tile;
	byte row;
	byte col;

	this (int new_tile, int new_row, int new_col)
	{
		tile = cast (byte) (new_tile);
		row = cast (byte) (new_row);
		col = cast (byte) (new_col);
	}
}

final class Plan
{
	GameMove [] goal_moves;
	CheckPoint [] check_points;
	Problem problem;
	Board check_board;
	TargetBoard target_board;

	this (Problem new_problem, Goal new_goal)
	{
		auto cur_problem = new_problem;
		byte [] new_contents;
		new_contents.reserve (cur_problem.contents.length);
		foreach (tile; cur_problem.contents)
		{
			if (tile == '?')
			{
				new_contents ~= cast (byte) (LET);
			}
			else
			{
				new_contents ~= cast (byte) (tile - 'A');
			}
		}
		assert (new_contents.length < byte.max);

		auto goal = new Goal (new_goal);
		assert (goal.word.length < byte.max);

		Pair [] segments;
		int [] final_positions;
		int segment_start = NA;
		foreach (pos; 0..cast (int) (goal.word.length))
		{
			if ((goal.mask_forbidden >> pos) & 1)
			{
				if (segment_start != NA)
				{
					segments ~= Pair (segment_start, pos);
					segment_start = NA;
				}
				final_positions ~= pos;
			}
			else if (segment_start == NA)
			{
				segment_start = pos;
			}
		}
		if (segment_start != NA)
		{
			segments ~= Pair (segment_start,
			    cast (int) (goal.word.length));
			segment_start = NA;
		}

		int row = goal.row;
		int col = goal.col;

		Board cur_check_board;
		if (cur_check_board.is_flipped != goal.is_flipped)
		{
			cur_check_board.flip ();
		}
		auto tile_numbers = new int [goal.word.length];
		int last_final_pos = NA;
		foreach (pos; final_positions)
		{
			bool found = false;
			foreach_reverse (num, ref tile; new_contents)
			{
				if (tile == goal.word[pos] &&
				    (tile & TileBag.IS_RESTRICTED) == 0)
				{
					found = true;
					tile |= TileBag.IS_RESTRICTED;
					tile_numbers[pos] =
					    cast (int) (num);
					last_final_pos = max (last_final_pos,
					    cast (int) (num));
					cur_check_board.contents
					    [row][col + pos] = tile;
					break;
				}
			}
			if (!found)
			{ // bad plan
				return;
			}
		}
		if (last_final_pos == NA)
		{
			last_final_pos = cast (int) (new_contents.length);
		}

		auto cur_target_board = new TargetBoard ();
		foreach (seg; segments)
		{
			foreach (pos; seg.x..seg.y)
			{
				bool found = false;
				foreach_reverse (num, ref tile; new_contents)
				{
					if (tile == goal.word[pos] &&
					    !(tile & TileBag.IS_RESTRICTED))
					{
						found = true;
						tile |= TileBag.IS_RESTRICTED;
						tile_numbers[pos] =
						    cast (int) (num);
						cur_check_board
						    [row][col + pos] = tile;
						if (!goal.is_flipped)
						{
							cur_target_board
							    [row][col + pos] =
							    cast (byte) (num);
						}
						else
						{
							cur_target_board
							    [col + pos][row] =
							    cast (byte) (num);
						}
						break;
					}
				}
				if (!found)
				{ // bad plan
					return;
				}
			}
		}

		// good plan
		cur_problem.contents = map !(a => cast (char) (a + 'A'))
		    (new_contents).array ().to !(string) ();
		problem = cur_problem;
		target_board = cur_target_board;
		check_board = cur_check_board;

		goal_moves = new GameMove [0];
		if (true)
		{
			auto cur_move = new GameMove ();
			foreach (pos, tile; goal.word)
			{
				BoardCell cell = tile;
				if (goal.mask_forbidden & (1 << pos))
				{
					cell.active = true;
				}
				cur_move.word ~= cell;
			}
			cur_move.row = 0;
			cur_move.col = 0;
			cur_move.tiles_before =
			    cast (byte) (last_final_pos - Rack.MAX_SIZE + 1);
			cur_move.is_flipped = false;
			cur_move.score = NA;
			goal_moves ~= cur_move;
		}

		check_points = new CheckPoint [0];
		foreach (seg; segments)
		{
			int min_pos = seg.y - cast (int) (minPos
			   (tile_numbers[seg.x..seg.y]).length);
			assert (seg.x <= min_pos && min_pos < seg.y);
			if (!goal.is_flipped)
			{
				check_points ~=
				    CheckPoint (tile_numbers[min_pos],
				    row, col + min_pos);
			}
			else
			{
				check_points ~=
				    CheckPoint (tile_numbers[min_pos],
				    col + min_pos, row);
			}
		}
	}

	override string toString () const
	{
		string res;
		res ~= to !(string) (goal_moves) ~ '\n';
		res ~= to !(string) (check_points) ~ '\n';
		res ~= to !(string) (problem) ~ '\n';
		res ~= to !(string) (check_board);
		if (target_board !is null)
		{
			res ~= target_board.toString ();
		}
		return res;
	}
}

unittest
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
	auto s = new Scoring ();
	auto p = Problem ("?:", "OXYPHENBUTAZONE");
	auto goal = new Goal ("OXYPhenButaZonE", 0, 0, false);
	auto plan = new Plan (p, goal);
	writeln (plan);
//	auto game = new Game !(Trie) (t, s);
//	auto cur = GameState (Problem ("?:", "ABCDEFG"));
//	auto next = game_beam_search ([cur], game, 100, 1);
//	writeln (next);
//	stdout.flush ();
//	assert (next.board.score == 53 && next.board.value == 53);
}
