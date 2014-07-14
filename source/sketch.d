module sketch;

import std.algorithm;
import std.conv;
import std.stdio;

import general;
import goal;
import problem;
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
			{ // tried the other direction here
				if (goal.is_final_pos (pos))
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
					if (goal.is_final_pos (pos))
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

			// heuristic
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
					if (!goal.is_final_pos (pos))
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

				int tile_num = last_final_pos[goal_num];
				if (tile_num == tiles.length)
				{
					break;
				}
				auto tile_lock =
				    tile_locks[tile_num];
				assert (tile_lock.goal_num == goal_num);
				int pos = tile_lock.pos;
				assert (goal.is_final_pos (pos));

				auto let = tiles[tile_num] & LET_MASK;
				found = false;
				foreach (num; tiles_by_letter[let]
				    [letters_by_tile[tile_num]..$])
				{
					assert (num < cur_ceiling);
					if ((tiles[num] &
					    TileBag.IS_RESTRICTED))
					{
						continue;
					}
					tiles[tile_num] &=
					    ~TileBag.IS_RESTRICTED;
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
				calc_last_final_pos (goal_num);
			}
		}

		prepare ();
		if (!(goals_counter << total_counter))
		{
			return 0;
		}
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
			writeln (next);
//			writeln ("!!! ", value, ' ', next.value);
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
		    value_bad.to !(string) () ~ '\n';

		foreach (num_goal, goal; goals)
		{
			res ~= goal.to_masked_string () ~ ' ' ~
			    last_final_pos[num_goal].to !(string) () ~ ' ' ~
			    goal_locks[num_goal].to !(string) () ~ '\n';
		}

		return res;
	}
}
