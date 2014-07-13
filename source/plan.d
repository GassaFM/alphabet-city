module plan;

import std.algorithm;
import std.conv;
import std.range;
import std.stdio;

import board;
import game_move;
import general;
import goal;
import problem;
import scoring;
import sketch;
import tile_bag;
import trie;

struct CheckPoint
{
	byte tile;
	byte row;
	byte col;

	this (T1, T2, T3) (T1 new_tile, T2 new_row, T3 new_col)
	{
		version (DEBUG)
		{ // safe but slow
			tile = to !(typeof (tile)) (new_tile);
			row = to !(typeof (row)) (new_row);
			col = to !(typeof (col)) (new_col);
		}
		else
		{ // unsafe but fast
			tile = cast (typeof (tile)) (new_tile);
			row = cast (typeof (row)) (new_row);
			col = cast (typeof (col)) (new_col);
		}
	}

	string toString () const
	{
		return "" ~ to !(string) (tile) ~ "(" ~
		    to !(string) (row) ~ "," ~ to !(string) (col) ~ ")";
	}
}

final class Plan
{
	GameMove [] goal_moves;
	CheckPoint [] check_points;
	Problem problem;
	Board check_board;
	TargetBoard target_board;
	int score_rating = NA;

	this (ref Problem new_problem, Goal [] new_goals)
	{
		auto sketch = Sketch (new_problem, new_goals);
		if (sketch.value < -Sketch.VALUE_MUCH / 2)
		{ // bad plan
			return;
		}

		// good plan
		problem = new_problem;
		problem.contents = map !(a => cast (char) (a + 'A'))
		    (sketch.tiles).array ().to !(string) ();

		check_board = Board.init;
		target_board = new TargetBoard ();
		goal_moves = new GameMove [0];
		check_points = new CheckPoint [0];
		score_rating = reduce !((a, b) => a + b.score_rating)
		    (0, sketch.goals);

		foreach (goal_num, goal; sketch.goals)
		{
			Pair [] segments;
			int [] final_positions;
			int segment_start = NA;
			foreach (pos, let; goal.word)
			{
				if (goal.is_final_pos (pos))
				{
					if (segment_start != NA)
					{
						segments ~=
						    Pair (segment_start,
						    cast (int) (pos));
						segment_start = NA;
					}
					final_positions ~= cast (int) (pos);
				}
				else if (segment_start == NA)
				{
					segment_start = cast (int) (pos);
				}
			}
			if (segment_start != NA)
			{
				segments ~= Pair (segment_start,
				    cast (int) (goal.word.length));
				segment_start = NA;
			}

			if (check_board.is_flipped != goal.is_flipped)
			{
				check_board.flip ();
			}
			auto tile_numbers = sketch.goal_locks[goal_num];
//			writeln ("??? ", tile_numbers);
			int row = goal.row;
			int col = goal.col;

			foreach (pos, let; goal.word)
			{
				check_board.contents[row][col + pos] = let;
				int num = tile_numbers[pos];
				assert (num != NA);
				byte val = cast (byte) (num +
				    goal.is_final_pos (pos) * byte.min);
				if (!goal.is_flipped)
				{
					target_board[row][col + pos] = val;
				}
				else
				{
					target_board[col + pos][row] = val;
				}
			}

			auto cur_move = new GameMove ();
			foreach (pos, tile; goal.word)
			{
				BoardCell cell = tile;
				if (goal.is_final_pos (pos))
				{
					cell.active = true;
				}
				cur_move.word ~= cell;
			}
			cur_move.row = goal.row;
			cur_move.col = goal.col;
			cur_move.tiles_before =
			    cast (byte) (sketch.last_final_pos[goal_num] -
			    Rack.MAX_SIZE + 1);
			cur_move.is_flipped = false;
			cur_move.score = NA;
			goal_moves ~= cur_move;

			foreach (seg; segments)
			{
				int min_pos = seg.y - cast (int) (minPos
				   (tile_numbers[seg.x..seg.y]).length);
				assert (seg.x <= min_pos && min_pos < seg.y);
				int cur_row = row;
				if (cur_row == 0)
				{
					cur_row++;
				}
				if (cur_row + 1 == Board.SIZE)
				{
					cur_row--;
				}
				if (!goal.is_flipped)
				{
					check_points ~=
					    CheckPoint (tile_numbers[min_pos],
					    cur_row, col + min_pos);
				}
				else
				{
					check_points ~=
					    CheckPoint (tile_numbers[min_pos],
					    col + min_pos, cur_row);
				}
			}
		}

		sort !((a, b) => a.tile < b.tile, SwapStrategy.stable)
		    (check_points);
/*
		while (true)
		{
			bool found = false;
			first_loop:
			foreach (i; 0..check_points.length)
			{
				foreach (j; i + 1..check_points.length)
				{
					if (check_points[i].row !=
					    check_points[j].row)
					{
						continue;
					}
					foreach (k; j + 1..check_points.length)
					{
						if (check_points[i].row !=
						    check_points[k].row)
						{
							continue;
						}
						if ((check_points[i].col <
						    check_points[k].col) !=
						    (check_points[k].col <
						    check_points[j].col))
						{
							continue;
						}

						foreach_reverse (p; j..k)
						{
							swap (check_points[p],
							    check_points
							    [p + 1]);
						}
						found = true;
						break first_loop;
					}
				}
			}

			if (!found)
			{
				break;
			}
		}
*/
	}

	override string toString () const
	{
		string res;
		res ~= "Plan: " ~ to !(string) (goal_moves.length) ~ ' ' ~
		    to !(string) (score_rating) ~ '\n';
		res ~= to !(string) (goal_moves) ~ '\n';
		res ~= to !(string) (check_points) ~ '\n';
		if (target_board !is null)
		{
			res ~= target_board.to_strings ()
			    .stride (Board.CENTER).join ("\n");
			res ~= '\n';
		}
		res ~= to !(string) (problem); // ~ '\n';
//		res ~= to !(string) (check_board);
//		if (target_board !is null)
//		{
//			res ~= target_board.toString ();
//		}
		return res;
	}

	// TODO: add invert row order ability to plan
}

unittest
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
	auto s = new Scoring ();
	auto p = Problem ("?:", "OXYPHENBUTAZONE");
	auto goal = new Goal ("OXYPhenButaZonE", 0, 0, false);
	auto plan = new Plan (p, [goal]);
//	writeln (plan);
	assert (plan.check_points.length == 3);
}
