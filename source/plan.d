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

	this (T1: long, T2: long)
	    (T1 new_tile, T2 new_row, T2 new_col, bool is_flipped,
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
	static immutable int ENHANCE_VALUE = 40;

	GameMove [] goal_moves;
	CheckPoint [] check_points;
	Problem problem;
	Board check_board;
	TargetBoard target_board;
	int score_rating = NA;
	int sketch_value;

	this (Plan other)
	{
		goal_moves = other.goal_moves.dup;
		check_points = other.check_points.dup;
		problem = other.problem;
		check_board = other.check_board;
		target_board = new TargetBoard (other.target_board);
		score_rating = other.score_rating;
		sketch_value = other.sketch_value;
	}

	void refine (Board board)
	{
		enforce (!board.is_flipped);
		
		int stage = 0;
		foreach (int num, ref check_point; check_points)
		{
			if (stage == 0 &&
			    board[check_point.row][check_point.col].empty)
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
				stage = 1;
			}
			else if (stage == 1 &&
			    !board[check_point.row][check_point.col].empty)
			{
				check_point.value -= uniform !("[]")
				    (RANDOM_ADD_LO, RANDOM_ADD_HI,
				    random_gen);
				check_point.value =
				    max (check_point.value, RANDOM_ADD_HI);
				stage = 2;
			}
		}
		if (stage > 0)
		{
			return;
		}

//		stderr.writeln ("BAD!");
//		stderr.writeln (board);
		stderr.writeln ("plan refine warning: " ~
		    "all checkpoints reached");
		stderr.flush ();
		foreach (int num, ref check_point; check_points)
		{
			check_point.value += uniform !("[]")
			    (-RANDOM_DELTA, +RANDOM_DELTA, random_gen);
			check_point.value =
			    max (check_point.value, RANDOM_ADD_HI);
		}
	}

	bool enhance (byte row, byte col)
	{
		if (target_board.tile_number[row][col] != NA)
		{
			return false;
		}
		byte best_pos = NA;
		int best_val = 0;
		foreach_reverse (pos, let; problem.contents)
		{
			if (pos * 2 < problem.contents.length)
			{
				break;
			}
			if (let & TileBag.IS_RESTRICTED)
			{
				continue;
			}
			int val = global_scoring.tile_value
			    [(let == '?') ? LET : ((let - 'A') & LET_MASK)];
			if (val > best_val)
			{
				best_pos = cast (byte) (pos);
				best_val = val;
			}
		}
		if (best_pos == NA)
		{
			return false;
		}

		stderr.writeln ("plan enhahce: found tile ",
		    problem.contents[best_pos], " of value ",
		    best_val, " at position ", best_pos,
		    " to place at (", row, ", ", col, ")");
		stderr.flush ();
		check_board.normalize_flip ();
		BoardCell tile = (problem.contents[best_pos] - 'A') & LET_MASK;
		check_board[row][col] = tile;
		target_board.place (best_pos, row, col, false);
		char [] temp_contents = problem.contents.dup;
		temp_contents[best_pos] |= TileBag.IS_RESTRICTED;
		problem.contents = to !(string) (temp_contents);
		check_points ~= CheckPoint (best_pos, row, col,
		    false, ENHANCE_VALUE);
		version (verbose)
		{
			writeln (check_board);
			writeln (target_board);
			stdout.flush ();
		}
		return true;
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
/*
				// HACK!!!
				if (min_pos == Board.SIZE - 2 &&
				    seg.x < min_pos)
				{
					min_pos--;
				}
*/
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

	this (GameMoveRange)
	    (ref Problem new_problem, TargetBoard new_target_board,
	    Board * new_check_board, GameMoveRange new_goal_moves)
	    if (isInputRange !(GameMoveRange) &&
	    is (Unqual !(ElementType !(GameMoveRange)) == GameMove))
	{
		problem = new_problem;
		if (new_check_board !is null)
		{
			check_board = *new_check_board;
		}
		target_board = new TargetBoard (new_target_board);
		goal_moves = new_goal_moves.array ();
		check_points = new CheckPoint [0];
		score_rating = 0;

		char [] new_contents;
		new_contents.reserve (problem.contents.length);
		foreach (num, tile; problem.contents)
		{
			char new_tile = tile;
			if (new_tile == '?')
			{
				new_tile = to !(char) (LET + 'A');
			}
			if (!target_board.coord[num].is_empty)
			{
				new_tile |= TileBag.IS_RESTRICTED;
			}
			new_contents ~= new_tile;
		}
/*
		writeln (problem.contents);
		writeln (new_contents);
		stdout.flush ();
*/
		problem.contents = to !(string) (new_contents);
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
