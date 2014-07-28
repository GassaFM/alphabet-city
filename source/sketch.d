module sketch;

import std.algorithm;
import std.conv;
import std.range;
import std.stdio;
import std.string;

import board;
import general;
import goal;
import problem;
import scoring;
import tile_bag;

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
		return "TL(" ~ to !(string) (goal_num) ~ "," ~
		    to !(string) (pos) ~ ")";
	}
}

struct Sketch
{
	static immutable int VALUE_MUCH = int.max / 4;
	static immutable int TILE_TO_MOVE = TOTAL_TILES;
//	static immutable int TILE_TO_MOVE = 98;
//	static immutable int TILE_TO_MOVE = 94;

	TileLock [] tile_locks;
	int [] [] goal_locks;
	int [] last_final_pos;
	Problem problem;
	Goal [] goals;
	byte [] tiles;
	int value_good = -VALUE_MUCH;
	int value_bad = +VALUE_MUCH;
	int score_rating = 0;
	int first_move_lo = NA;
	int first_move_hi = NA;

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
		TileCounter total_counter;
		TileCounter goals_counter;

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

			score_rating = reduce !((a, b) => a + b.score_rating)
			    (0, goals);
			tile_locks = new TileLock [tiles.length];
			goal_locks = new int [] [0];
			foreach (ref goal; goals)
			{
				goal_locks ~= new int [goal.word.length];
				goal_locks[$ - 1][] = NA;
			}
			last_final_pos = new int [goals.length];
			last_final_pos[] = NA;

			foreach_reverse (num, tile; tiles)
			{
				if (!(tile & TileBag.IS_RESTRICTED))
				{
					tiles_by_letter[tile & LET_MASK] ~=
					    cast (int) (num);
					letters_by_tile[num] = cast (int)
					    (tiles_by_letter[tile & LET_MASK]
					    .length - 1);
					total_counter[tile & LET_MASK]++;
				}
			}

			foreach (goal; goals)
			{
				foreach (tile; goal.word)
				{
					goals_counter[tile & LET_MASK]++;
				}
			}
		}

		bool put_first_move ()
		{
			if (first_move_lo == NA || first_move_hi == NA)
			{
				return true;
			}

			foreach (goal_num, goal; goals)
			{
				if (!goal.is_center_goal ())
				{
					continue;
				}

				assert (goal.word.length == Board.SIZE);
				assert (goal.row == Board.CENTER);
				assert (goal.col == 0);
				foreach (pos; first_move_lo..first_move_hi)
				{
					if (goal.is_final_pos (pos))
					{
						assert (false);
					}
					auto let = goal.word[pos];

					bool found = false;
					foreach_reverse (num;
					    tiles_by_letter[let])
					{
						if ((num >= Rack.MAX_SIZE) ||
						    (tiles[num] &
						    TileBag.IS_RESTRICTED))
						{
							continue;
						}
						tiles[num] |=
						    TileBag.IS_RESTRICTED;
						tile_locks[num] =
						    TileLock (goal_num, pos);
						goal_locks[goal_num][pos] =
						    num;
						found = true;
						break;
					}
					if (!found)
					{
						return false;
					}
				}
			}

			return true;
		}

		bool place_letter (int goal_num, int pos, byte let,
		    int ceiling)
		{
			foreach (num; tiles_by_letter[let])
			{
				if (num >= ceiling ||
				    (tiles[num] & TileBag.IS_RESTRICTED))
				{
					continue;
				}
				tiles[num] |= TileBag.IS_RESTRICTED;
				tile_locks[num] = TileLock (goal_num, pos);
				goal_locks[goal_num][pos] = num;
				if (let == LET)
				{
					auto goal = goals[goal_num];
					score_rating -= goal.score_mult *
					    global_scoring.letter_bonus
					    (goal.row, cast (byte)
					    (goal.col + pos),
					    goal.is_flipped);
				}
				return true;
			}

			if (let != LET)
			{
				if (place_letter (goal_num, pos, LET, ceiling))
				{
					return true;
				}
			}

			return false;
		}

		void clear_goal_lock (int goal_num, int pos, ref int num)
		{
			tiles[num] &= ~TileBag.IS_RESTRICTED;
			tile_locks[num] = TileLock.init;
			if ((tiles[num] & LET_MASK) == LET)
			{
				auto goal = goals[goal_num];
				score_rating += goal.score_mult *
				    global_scoring.letter_bonus
				    (goal.row, cast (byte)
				    (goal.col + pos),
				    goal.is_flipped);
			}
			num = NA;
		}

		bool is_first_move_pos (T1) (Goal goal, T1 pos)
		{
			return goal.is_center_goal () &&
			    first_move_lo <= pos &&
			    pos < first_move_hi;
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

		bool decrease_lock () (int tile_num, int cur_floor)
		{
			version (debug_sketch)
			{
				writeln ("decrease_lock ", tile_num,
				    ' ', cur_floor);
			}
			assert (tile_num != NA);
			if (tile_num == tiles.length)
			{
				return false;
			}

			auto tile_lock = tile_locks[tile_num];
			int goal_num = tile_lock.goal_num;
			assert (goal_num != NA);
			int pos = tile_lock.pos;
			assert (pos != NA);

			auto let = tiles[tile_num] & LET_MASK;
			bool found = false;
			foreach (num; tiles_by_letter[let]
			    [letters_by_tile[tile_num]..$])
			{
				if (num < cur_floor)
				{
					break;
				}
				if ((tiles[num] & TileBag.IS_RESTRICTED))
				{
					continue;
				}
				tiles[tile_num] &= ~TileBag.IS_RESTRICTED;
				tile_locks[tile_num] = TileLock.init;
				tiles[num] |= TileBag.IS_RESTRICTED;
				tile_locks[num] = TileLock (goal_num, pos);
				goal_locks[goal_num][pos] = num;
				found = true;
				break;
			}

			return found;
		}

		void consider ()
		{
			// heuristic
			foreach (v; lock_count)
			{
				value_bad += 1 << (max (0, v - 3));
			}
			scope (exit)
			{
				foreach (v; lock_count)
				{
					value_bad -= 1 << (max (0, v - 3));
				}
			}

			if (tile_locks.length > TILE_TO_MOVE &&
			    tile_locks[TILE_TO_MOVE] != TileLock.init)
			{
				value_bad += 1000;
			}
			scope (exit)
			{
				if (tile_locks.length > TILE_TO_MOVE &&
				    tile_locks[TILE_TO_MOVE] != TileLock.init)
				{
					value_bad -= 1000;
				}
			}

			process (this);
		}

		void put_start_tiles (int goal_num)
		{
			version (debug_sketch)
			{
				writeln ("put_start_tiles ", goal_num);
			}
			if (goal_num >= goals.length)
			{
				consider ();
				return;
			}

			auto goal = goals[goal_num];
			bool found = true;
			immutable static int [] ORDER =
			    [0, 14, 1, 13, 2, 12, 3, 11, 4, 10, 5, 9, 6, 8, 7];
			foreach (pos; ORDER)
			{
				auto let = goal.word[pos];
				if (goal.is_final_pos (pos) ||
				    is_first_move_pos (goal, pos))
				{
					continue;
				}
				if (!place_letter (goal_num, pos, let,
				    last_final_pos[goal_num]))
				{
					found = false;
					break;
				}
			}

			scope (exit)
			{
				foreach (pos, ref num; goal_locks[goal_num])
				{
					if (goal.is_final_pos (pos) ||
					    num == NA ||
					    is_first_move_pos (goal, pos))
					{
						continue;
					}
					clear_goal_lock (goal_num,
					    cast (int) (pos), num);
				}
			}

			if (!found)
			{
				return;
			}

			// heuristic: monotonicity
//			writeln ("before: ", goal_locks[goal_num]);
/*
			foreach (lo; 0..cast (int) (goal.word.length))
			{
				if (goal.is_final_pos (lo))
				{
					continue;
				}
				if (!(lo == 0 || goal.is_final_pos (lo - 1)))
				{
					continue;
				}

				int hi = lo + 1;
				while (hi < goal.word.length &&
				    !goal.is_final_pos (hi))
				{
					hi++;
				}

				int me = lo;
				foreach (pos; lo + 1..hi)
				{
					if (goal_locks[goal_num][me] >
					    goal_locks[goal_num][pos])
					{
						me = pos;
					}
				}
//				writeln (goal_locks[goal_num][lo..hi]);
				foreach (pos; lo + 1..me)
				{
					while (goal_locks[goal_num][pos - 1] <
					    goal_locks[goal_num][pos])
					{
						if (!decrease_lock (goal_locks
						    [goal_num][pos],
						    goal_locks[goal_num]
						    [pos + 1]))
						{
							break;
						}
					}
				}
				foreach_reverse (pos; me + 1..hi)
				{
					while (goal_locks[goal_num][pos + 1] <
					    goal_locks[goal_num][pos])
					{
						if (!decrease_lock (goal_locks
						    [goal_num][pos],
						    goal_locks[goal_num]
						    [pos - 1]))
						{
							break;
						}
					}
				}
			}
*/
//			writeln ("after:  ", goal_locks[goal_num]);

			if (tile_locks.length > TILE_TO_MOVE &&
			    tile_locks[TILE_TO_MOVE] != TileLock.init &&
			    tile_locks[TILE_TO_MOVE].goal_num == goal_num &&
			    !goal.is_final_pos (tile_locks[TILE_TO_MOVE].pos))
			{
//				auto s = "before: " ~
//				    format ("[%(%s, %)]", tile_locks);
//				stderr.writeln ("before:  ", tile_locks);
				if (!decrease_lock (TILE_TO_MOVE, NA))
				{
					return;
				}
//				stderr.writeln (s);
//				stderr.writeln ("after:  ", tile_locks);
			}

			// heuristic
			foreach (pos, let; goal.word)
			{
				value_good += goal_locks[goal_num][pos];
			}
			scope (exit)
			{
				foreach (pos, let; goal.word)
				{
					value_good -=
					    goal_locks[goal_num][pos];
				}
			}
/*
			foreach (pos, let; goal.word)
			{
				value_bad += max (0, TOTAL_TILES / 2 -
				    goal_locks[goal_num][pos]);
			}
			scope (exit)
			{
				foreach (pos, let; goal.word)
				{
					value_bad -= max (0, TOTAL_TILES / 2 -
					    goal_locks[goal_num][pos]);
				}
			}
*/

			put_start_tiles (goal_num + 1);
		}

		void calc_last_final_pos (int goal_num)
		{
			auto goal = goals[goal_num];

			last_final_pos[goal_num] = NA;
			foreach (pos, let; goal.word)
			{
				if (!goal.is_final_pos (pos))
				{
					continue;
				}
				last_final_pos[goal_num] =
				    max (last_final_pos[goal_num],
				    goal_locks[goal_num][pos]);
			}
			if (last_final_pos[goal_num] == NA)
			{
				last_final_pos[goal_num] =
				    cast (int) (tiles.length);
			}
		}

		int first_final_pos (int goal_num)
		{
			auto goal = goals[goal_num];
 
			int res = NA;
			foreach (pos, let; goal.word)
			{
				if (!goal.is_final_pos (pos))
				{
					continue;
				}
				res = min (res, goal_locks[goal_num][pos]);
			}
			if (res == NA)
			{
				res = cast (int) (tiles.length);
			}
			return res;
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
				if (!goal.is_final_pos (pos))
				{
					continue;
				}
				if (!place_letter (goal_num, cast (int) (pos),
				    let, cur_ceiling))
				{
					found = false;
					break;
				}
			}

			scope (exit)
			{
				foreach (pos, ref num; goal_locks[goal_num])
				{
					if (!goal.is_final_pos (pos) ||
					    num == NA)
					{
						continue;
					}
					clear_goal_lock (goal_num,
					    cast (int) (pos), num);
				}
			}

			if (!found)
			{
				return;
			}
			calc_last_final_pos (goal_num);
			scope (exit)
			{
				last_final_pos[goal_num] = NA;
			}

			while (true)
			{
				foreach (pos, let; goal.word)
				{
					if (!goal.is_final_pos (pos))
					{
						continue;
					}
					locks_add (goal_locks[goal_num][pos],
					    last_final_pos[goal_num]);
				}

				if (!lock_errors)
				{
					int saved_ceiling =
					    last_final_pos[goal_num];
					swap (saved_ceiling, cur_ceiling);
					scope (exit)
					{
						swap (saved_ceiling,
						    cur_ceiling);
					}

					// heuristic
					static immutable int LEN_MULT = 1; //10
					int first_pos =
					    first_final_pos (goal_num);
					value_bad +=
					    last_final_pos[goal_num] -
					    first_pos;
					scope (exit)
					{
						value_bad -=
						    last_final_pos[goal_num] -
						    first_pos;
					}
/*
					static immutable int FIRST_POS_MULT =
					    4;
					int first_pos =
					    first_final_pos (goal_num);
					value_good +=
					    FIRST_POS_MULT * first_pos;
					value_bad +=
					    last_final_pos[goal_num];
					scope (exit)
					{
						value_good -=
						    FIRST_POS_MULT * first_pos;
						value_bad -=
						    last_final_pos[goal_num];
					}
*/

					put_final_tiles (goal_num + 1);
				}

				foreach (pos, let; goal.word)
				{
					if (!goal.is_final_pos (pos))
					{
						continue;
					}
					locks_sub (goal_locks[goal_num][pos],
					    last_final_pos[goal_num]);
				}

				if (!decrease_lock (last_final_pos[goal_num],
				    NA))
				{
					break;
				}
				calc_last_final_pos (goal_num);
			}
		}

		prepare ();
		if (!(goals_counter << total_counter))
		{
			return 0;
		}
		if (!put_first_move ())
		{
			return 0;
		}
		put_final_tiles (0);

		return 0;
	}

	this (ref Problem new_problem, Goal [] new_goals,
	    int new_lo = NA, int new_hi = NA)
	{
		problem = new_problem;
		goals = new_goals.dup;
		first_move_lo = new_lo;
		first_move_hi = new_hi;
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
		bool found = false;
		foreach (ref next; cur)
		{
			if (value < next.value)
			{
				found = true;
				this = next;
			}
		}
		if (!found)
		{
			goals = new Goal [0];
		}
	}

	string toString () const
	{
		string res;
		res ~= "Sketch: " ~ goals.length.to !(string) () ~ ' ' ~
		    value.to !(string) () ~ ' ' ~
		    value_good.to !(string) () ~ ' ' ~
		    value_bad.to !(string) () ~ ' ' ~
		    first_move_lo.to !(string) () ~ ' ' ~
		    first_move_hi.to !(string) () ~ '\n';

		foreach (num_goal, goal; goals)
		{
			res ~= goal.to_masked_string () ~ ' ' ~
			    last_final_pos[num_goal].to !(string) () ~ ' ' ~
			    goal_locks[num_goal].to !(string) () ~ '\n';
		}

		return res;
	}
}
