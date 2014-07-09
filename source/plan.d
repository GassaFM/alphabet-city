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

struct TileLock
{
	byte goal_num = NA;
	byte pos = NA;

	this (T1, T2) (T1 new_goal_num, T2 new_pos)
	{
		version (DEBUG)
		{ // safe but slow
			goal_num = to !(typeof (goal_num)) (new_goal_num);
			pos = to !(typeof (pos)) (new_pos);
		}
		else
		{ // unsafe but fast
			goal_num = cast (typeof (goal_num)) (new_goal_num);
			pos = cast (typeof (pos)) (new_pos);
		}
	}

	string toString () const
	{
		return "(gn=" ~ to !(string) (goal_num) ~ ", p=" ~
		    to !(string) (pos) ~ ")";
	}
}

struct Sketch
{
	static immutable int VALUE_MUCH = int.max / 4;

	TileLock [] tile_locks;
	int [] [] goal_locks;
	int [] last_final_pos;
	Problem problem;
	Goal [] goals;
	byte [] tiles;
	int value_good = -VALUE_MUCH;
	int value_bad = +VALUE_MUCH;

	this (this)
	{
//		writeln ("huh?!");
		tile_locks = tile_locks.dup;
		goal_locks = goal_locks.dup;
		last_final_pos = last_final_pos.dup;
		foreach (ref goal_lock; goal_locks)
		{
			goal_lock = goal_lock.dup;
		}
		goals = goals.dup;
		tiles = tiles.dup;
	}

	int value () @property const
	{
		return value_good - value_bad;
	}

	int opApply (int delegate (ref Sketch) process)
	{
		int [] [] tiles_by_letter;
		int [] letters_by_tile;
		int cur_ceiling;
		int [] lock_count;
		int lock_errors;

		void prepare ()
		{
			version (debug_sketch)
			{
				writeln ("prepare");
			}
			tiles_by_letter = new int [] [LET + 1];
			letters_by_tile = new int [tiles.length];
			cur_ceiling = TOTAL_TILES;
			lock_count = new int [tiles.length];
			lock_errors = 0;

			value_good = 0;
			value_bad = 0;

			tile_locks = new TileLock [tiles.length];
			goal_locks = new int [] [0];
			foreach (ref goal; goals)
			{
				goal_locks ~= new int [goal.word.length];
				goal_locks[$ - 1][] = NA;
			}
			last_final_pos = new int [goals.length];
			last_final_pos[] = NA;

			TileCounter total_counter;
			foreach_reverse (num, tile; tiles)
			{
				if (!(tile & TileBag.IS_RESTRICTED))
				{
					tiles_by_letter[tile & LET_MASK] ~=
					    cast (int) (num);
					letters_by_tile[num] =
					total_counter[tile & LET_MASK]++;
				}
			}
		}

		void locks_add (int x, int y)
		{
			foreach (pos; x..y)
			{
				lock_count[pos]++;
				if (lock_count[pos] >= Rack.MAX_SIZE)
				{
					lock_errors++;
				}
			}
		}

		void locks_sub (int x, int y)
		{
			foreach (pos; x..y)
			{
				if (lock_count[pos] >= Rack.MAX_SIZE)
				{
					lock_errors--;
				}
				lock_count[pos]--;
			}
		}

		void put_start_tiles (int goal_num)
		{
			version (debug_sketch)
			{
				writeln ("put_start_tiles ", goal_num);
			}
			if (goal_num >= goals.length)
			{
				process (this);
				return;
			}

			auto goal = goals[goal_num];
			bool found = true;
			foreach (pos, let; goal.word)
			{
				if (((goal.mask_forbidden >> pos) & 1))
				{
					continue;
				}
				found = false;
				foreach (num; tiles_by_letter[let])
				{
					if ((num >=
					    last_final_pos[goal_num]) ||
					    (tiles[num] &
					    TileBag.IS_RESTRICTED))
					{
						continue;
					}
					tiles[num] |= TileBag.IS_RESTRICTED;
					tile_locks[num] =
					    TileLock (goal_num, pos);
					goal_locks[goal_num][pos] = num;
					found = true;
					break;
				}
				if (!found)
				{
					break;
				}
			}

			scope (exit)
			{
				foreach (pos, ref num; goal_locks[goal_num])
				{
					if (((goal.mask_forbidden >> pos) & 1))
					{
						continue;
					}
					if (num == NA)
					{
						continue;
					}
					tiles[num] &= ~TileBag.IS_RESTRICTED;
					tile_locks[num] = TileLock.init;
					num = NA;
				}
			}

			if (!found)
			{
				return;
			}

			put_start_tiles (goal_num + 1);
		}

		void put_final_tiles (int goal_num)
		{
			version (debug_sketch)
			{
				writeln ("put_final_tiles ", goal_num);
			}
			if (goal_num >= goals.length)
			{
				put_start_tiles (0);
				return;
			}

			auto goal = goals[goal_num];
			bool found = true;
			foreach (pos, let; goal.word)
			{
				if (!((goal.mask_forbidden >> pos) & 1))
				{
					continue;
				}
				found = false;
				foreach (num; tiles_by_letter[let])
				{
					if ((num >= cur_ceiling) ||
					    (tiles[num] &
					    TileBag.IS_RESTRICTED))
					{
						continue;
					}
					tiles[num] |= TileBag.IS_RESTRICTED;
					tile_locks[num] =
					    TileLock (goal_num, pos);
					goal_locks[goal_num][pos] = num;
					last_final_pos[goal_num] =
					    max (last_final_pos[goal_num],
					    num);
					found = true;
					break;
				}
				if (!found)
				{
					break;
				}
			}

			scope (exit)
			{
				foreach (pos, ref num; goal_locks[goal_num])
				{
					if (!((goal.mask_forbidden >>
					    pos) & 1))
					{
						continue;
					}
					if (num == NA)
					{
						continue;
					}
					tiles[num] &= ~TileBag.IS_RESTRICTED;
					tile_locks[num] = TileLock.init;
					num = NA;
				}
			}

			if (!found)
			{
				return;
			}
			if (last_final_pos[goal_num] == NA)
			{
				last_final_pos[goal_num] =
				    cast (int) (tiles.length);
			}
			scope (exit)
			{
				last_final_pos[goal_num] = NA;
			}

			foreach (pos, let; goal.word)
			{
				if (!((goal.mask_forbidden >> pos) & 1))
				{
					continue;
				}
				locks_add (goal_locks[goal_num][pos],
				    last_final_pos[goal_num]);
			}

			scope (exit)
			{
				foreach (pos, let; goal.word)
				{
					if (!((goal.mask_forbidden >>
					    pos) & 1))
					{
						continue;
					}
					locks_sub (goal_locks[goal_num][pos],
					    last_final_pos[goal_num]);
				}
			}

			if (lock_errors)
			{
				return;
			}

			int saved_ceiling = last_final_pos[goal_num];
			swap (saved_ceiling, cur_ceiling);
			scope (exit)
			{
				swap (saved_ceiling, cur_ceiling);
			}

			put_final_tiles (goal_num + 1);
		}

		prepare ();
		put_final_tiles (0);

		return 0;
	}

	this (ref Problem new_problem, Goal [] new_goals)
	{
		problem = new_problem;
		goals = new_goals.dup;
		foreach (goal; goals)
		{
			assert (goal.word.length < byte.max);
		}

		tiles = new byte [0];
		tiles.reserve (problem.contents.length);
		foreach (tile; problem.contents)
		{
			if (tile == '?')
			{
				tiles ~= cast (byte) (LET);
			}
			else
			{
				tiles ~= cast (byte) (tile - 'A');
			}
		}
		assert (tiles.length < byte.max);

		auto cur = this;
//		writeln ("here");
		bool found = false;
		foreach (ref next; cur)
		{
//			writeln ("!!! ", value, ' ', next.value);
			if (value < next.value)
			{
				found = true;
				this = next;
//				writeln (this);
			}
		}
		if (!found)
		{
			goals = new Goal [0];
		}
		writeln (this);
	}

	string toString () const
	{
		string res;
		res ~= "Sketch: " ~ goals.length.to !(string) () ~ ' ' ~
		    value.to !(string) () ~ ' ' ~
		    value_good.to !(string) () ~ ' ' ~
		    value_bad.to !(string) () ~ '\n';

		foreach (num_goal, goal; goals)
		{
			res ~= goal.word.map !(a => cast (char) (a + 'A'))
			    .array ().to !(string) () ~ ' ' ~
			    last_final_pos[num_goal].to !(string) () ~ ' ' ~
			    goal_locks[num_goal].to !(string) () ~ '\n';
		}

		return res;
	}
}

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
		return "(t=" ~ to !(string) (tile) ~ ", r=" ~
		    to !(string) (row) ~ ", c=" ~ to !(string) (col) ~ ")";
	}
}

final class Plan
{
	GameMove [] goal_moves;
	CheckPoint [] check_points;
	Problem problem;
	Board check_board;
	TargetBoard target_board;

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

		foreach (goal_num, goal; sketch.goals)
		{
			Pair [] segments;
			int [] final_positions;
			int segment_start = NA;
			foreach (pos, let; goal.word)
			{
				if ((goal.mask_forbidden >> pos) & 1)
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
				    ((goal.mask_forbidden >> pos) & 1) *
				    byte.min);
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
				if (goal.mask_forbidden & (1 << pos))
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
	auto plan = new Plan (p, [goal]);
//	writeln (plan);
	assert (plan.check_points.length == 3);
}
