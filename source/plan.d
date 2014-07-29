module plan;

import std.algorithm;
import std.conv;
import std.exception;
import std.random;
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
	int value;

	this (T1, T2) (T1 new_tile, T2 new_row, T2 new_col, bool is_flipped,
	    int new_value)
	{
		if (is_flipped)
		{
			swap (new_row, new_col);
		}
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
		value = new_value;
	}

	string toString () const
	{
		return "" ~ to !(string) (tile) ~ "(" ~
		    to !(string) (row) ~ "," ~ to !(string) (col) ~ ")" ~
		    to !(string) (value);
	}
}

final class Plan
{
	static immutable int RANDOM_DELTA = 25 * 1;
	static immutable int RANDOM_ADD_LO = 60 * 2;
	static immutable int RANDOM_ADD_HI = 120 * 2;

	GameMove [] goal_moves;
	CheckPoint [] check_points;
	Problem problem;
	Board check_board;
	TargetBoard target_board;
	int score_rating = NA;
	int sketch_value;

	void refine (Board board)
	{
		enforce (!board.is_flipped);

		foreach (int num, ref check_point; check_points)
		{
			if (board[check_point.row][check_point.col].empty)
			{
				check_point.value += uniform !("[]")
				    (RANDOM_ADD_LO, RANDOM_ADD_HI,
				    random_gen);
				if (num > 0)
/*
				if (num > 0 &&
				    (num + 1 >= check_points.length ||
				    check_point.tile <
				    check_points[num + 1].tile))
*/
				{
					swap (check_points[num - 1],
					    check_points[num]);
				}
				return;
			}
		}

		stderr.writeln ("BAD!");
		stderr.writeln (board);
		stderr.flush ();
		foreach (int num, ref check_point; check_points)
		{
			if (board[check_point.row][check_point.col].empty)
			{
				check_point.value += uniform !("[]")
				    (-RANDOM_DELTA, +RANDOM_DELTA,
				    random_gen);
				check_point.value =
				    max (check_point.value, RANDOM_ADD_HI);
			}
		}
//		enforce (false);
	}

	this (ref Problem new_problem, Goal [] new_goals,
	    int lo = NA, int hi = NA)
	{
		auto sketch = Sketch (new_problem, new_goals, lo, hi);
		sketch_value = sketch.value;
		if (sketch.value < -Sketch.VALUE_MUCH / 2)
		{ // bad plan
			return;
		}

		// good plan
		problem = new_problem;
		problem.contents = map !(a => cast (char) (a + 'A'))
		    (sketch.tiles).array ().to !(string) ();

		check_board = Board.init;
		target_board = new TargetBoard (problem.contents.length);
		goal_moves = new GameMove [0];
		check_points = new CheckPoint [0];
//		auto check_points_add = new CheckPoint [0];
		score_rating = sketch.score_rating;

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
				if ((sketch.tiles[num] & LET_MASK) == LET)
				{
					check_board.contents[row][col + pos]
					    .wildcard = true;
				}
				byte val = cast (byte) (num +
				    goal.is_final_pos (pos) * byte.min);
				target_board.place (val, to !(byte) (row),
				    to !(byte) (col + pos), goal.is_flipped);
			}

			auto cur_move = new GameMove ();
			foreach (pos, tile; goal.word)
			{
				BoardCell cell = tile;
				if (goal.is_final_pos (pos))
				{
					cell.active = true;
				}
				int num = tile_numbers[pos];
				if ((sketch.tiles[num] & LET_MASK) == LET)
				{
					cell.wildcard = true;
				}
				cur_move.word ~= cell;
			}
			cur_move.row = goal.row;
			cur_move.col = goal.col;
			cur_move.tiles_before =
			    cast (byte) (sketch.last_final_pos[goal_num] -
			    Rack.MAX_SIZE + 1);
			cur_move.is_flipped = goal.is_flipped;
			cur_move.score = NA;
			goal_moves ~= cur_move;

			foreach (seg; segments)
			{
				int min_pos = seg.y - cast (int) (minPos
				   (tile_numbers[seg.x..seg.y]).length);
				assert (seg.x <= min_pos && min_pos < seg.y);
				int cur_row = row;
/*
				if (cur_row == 0)
				{
					cur_row++;
				}
				if (cur_row + 1 == Board.SIZE)
				{
					cur_row--;
				}
*/
				int cur_value = 160; // 320;
				if (sketch.tiles[tile_numbers[min_pos]] &
				    BoardCell.IS_WILDCARD)
				{
					cur_value += 40 * 5;
				}
				else
				{
					cur_value += 40 *
					    global_scoring.tile_value
					    [sketch.tiles[tile_numbers
					    [min_pos]] & LET_MASK];
				}
				foreach (pos; seg.x..seg.y)
				{
					cur_value += 10 * max (0,
					    16 - tile_numbers[pos] +
					    tile_numbers[min_pos]);
				}
				// randomize value
				cur_value += uniform !("[]") (-RANDOM_DELTA,
				    +RANDOM_DELTA, random_gen);
				check_points ~=
				    CheckPoint (tile_numbers[min_pos],
				    cur_row, col + min_pos, goal.is_flipped,
				    cur_value);

/*
				foreach (pos; seg.x..seg.y)
				{
					check_points_add ~=
					    CheckPoint (tile_numbers[pos],
					    row, col + pos, goal.is_flipped,
					    10 * 16);
				}
*/
			}
		}

		sort !((a, b) => a.tile < b.tile, SwapStrategy.stable)
		    (check_points);
/*
		sort !((a, b) => a.tile < b.tile, SwapStrategy.stable)
		    (check_points_add);
		check_points ~= check_points_add;
*/

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
		res ~= "Plan: " ~
		    "goals=" ~ to !(string) (goal_moves.length) ~ ' ' ~
		    "points=" ~ to !(string) (check_points.length) ~ ' ' ~
		    "score=" ~ to !(string) (score_rating) ~ ' ' ~
		    "value=" ~ to !(string) (sketch_value) ~ '\n';
		res ~= to !(string) (goal_moves) ~ '\n';
		res ~= to !(string) (check_points) ~ '\n';
		if (target_board !is null)
		{
			res ~= target_board.to_strings (problem.contents)
			    .stride (Board.CENTER).join ("\n");
			res ~= '\n';
		}
		res ~= to !(string) (problem);
//		res ~= to !(string) (problem) ~ '\n';
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

	void test_regular ()
	{
		auto p = Problem ("?:", "OXYPHENBUTAZONE");
		auto goal = new Goal ("OXYPhenButaZonE", 0, 0, false);
		auto plan = new Plan (p, [goal]);
//		writeln (plan);
		assert (plan.check_points.length == 3);
	}

	void test_wildcards ()
	{
		auto p = Problem ("?:", "OXY?HENBU?A?ONE");
		auto goal = new Goal ("OXYPhenButaZonE", 0, 0, false);
		auto plan = new Plan (p, [goal]);
//		writeln (plan);
		assert (plan.check_points.length == 3);
		assert (plan.score_rating < 900);
//		assert (plan.score_rating == 779);
	}

	test_regular ();
	test_wildcards ();
}
