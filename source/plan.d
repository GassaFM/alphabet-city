module plan;

import std.algorithm;
import std.conv;
import std.format;
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
		char [] new_contents;
		new_contents.reserve (cur_problem.contents.length);
		foreach (tile; cur_problem.contents)
		{
			if (tile == '?')
			{
				new_contents ~= cast (char) ('A' + LET);
			}
			else
			{
				new_contents ~= tile;
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
		writeln (final_positions);
		stdout.flush ();
		foreach (pos; final_positions)
		{
			writeln (pos);
			stdout.flush ();
			bool found = false;
			foreach_reverse (num, ref tile; new_contents)
			{
				writeln (num, ' ', tile, ' ', tile - 'A',
				    ' ', goal.word[pos],
				    ' ', tile & TileBag.IS_RESTRICTED);
				stdout.flush ();
				if (tile - 'A' == goal.word[pos] &&
				    (tile & TileBag.IS_RESTRICTED) == 0)
				{
					found = true;
					tile |= TileBag.IS_RESTRICTED;
					tile_numbers[pos] =
					    cast (int) (num);
					cur_check_board.contents
					    [row][col + pos] =
					    to !(byte) (tile - 'A');
					break;
				}
			}
			if (!found)
			{ // bad plan
				return;
			}
		}

		auto cur_target_board = new TargetBoard ();
		writeln (segments);
		stdout.flush ();
		foreach (seg; segments)
		{
			writeln (seg);
			stdout.flush ();
			foreach (pos; seg.x..seg.y)
			{
				writeln (pos);
				stdout.flush ();
				bool found = false;
				foreach_reverse (num, ref tile; new_contents)
				{
					if (tile - 'A' == goal.word[pos] &&
					    (tile &
					    TileBag.IS_RESTRICTED) == 0)
					{
						found = true;
						tile |= TileBag.IS_RESTRICTED;
						tile_numbers[pos] =
						    cast (int) (num);
						cur_check_board
						    [row][col + pos] =
						    to !(byte) (tile - 'A');
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
		cur_problem.contents = to !(string) (new_contents);
		problem = cur_problem;
		target_board = cur_target_board;
		check_board = cur_check_board;

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
	writeln (p);
	auto goal = new Goal ("OXYPhenButaZonE", 0, 0, false);
	writeln (goal);
	auto plan = new Plan (p, goal);
	writeln (plan);
//	auto game = new Game !(Trie) (t, s);
//	auto cur = GameState (Problem ("?:", "ABCDEFG"));
//	auto next = game_beam_search ([cur], game, 100, 1);
//	writeln (next);
//	stdout.flush ();
//	assert (next.board.score == 53 && next.board.value == 53);
}
